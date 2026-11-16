import re
import shutil
import uuid
import zipfile
from pathlib import Path

from django.conf import settings
from django.core.files import File
from django.db import transaction
from django.db.models import Max

from .models import (
    DIFFICULTY_CHOICES, Concept, Language, Topic, TopicTranslate, Word,
)

IMAGE_EXT = {'.png', '.jpg', '.jpeg', '.webp'}
AUDIO_EXT = {'.mp3', '.wav', '.ogg', '.m4a', '.aac'}
MAX_FILES = 5000
MAX_UNPACKED = 1024 * 1024 * 1024  # 1 ГБ
IGNORED = {'.ds_store', 'thumbs.db'}
TMP_ROOT = Path(settings.MEDIA_ROOT) / 'import_tmp'
DIFFICULTIES = dict(DIFFICULTY_CHOICES)
NUM_PREFIX = re.compile(r'^(\d+)_(.+)$')


class ArchiveError(Exception):
    pass


# ---------- распаковка ----------

def extract_archive(uploaded_file):
    token = uuid.uuid4().hex
    dest = TMP_ROOT / token
    dest.mkdir(parents=True)
    try:
        with zipfile.ZipFile(uploaded_file) as zf:
            _safe_extract(zf, dest)
    except zipfile.BadZipFile:
        shutil.rmtree(dest, ignore_errors=True)
        raise ArchiveError('Файл не является корректным ZIP-архивом.')
    except ArchiveError:
        shutil.rmtree(dest, ignore_errors=True)
        raise
    return token


def _fix_name(info):
    """Если флаг UTF-8 не выставлен, Python читает имя как cp437.
    Восстанавливаем байты и пробуем UTF-8, затем cp866 (Проводник Windows)."""
    if info.flag_bits & 0x800:
        return info.filename
    try:
        raw = info.filename.encode('cp437')
    except UnicodeEncodeError:
        return info.filename
    try:
        return raw.decode('utf-8')
    except UnicodeDecodeError:
        try:
            return raw.decode('cp866')
        except UnicodeDecodeError:
            return info.filename


def _safe_extract(zf, dest):
    infos = zf.infolist()
    if len(infos) > MAX_FILES:
        raise ArchiveError(f'Слишком много файлов в архиве (максимум {MAX_FILES}).')
    if sum(i.file_size for i in infos) > MAX_UNPACKED:
        raise ArchiveError('Архив слишком большой после распаковки.')

    base = dest.resolve()
    for info in infos:
        name = _fix_name(info)
        parts = Path(name).parts
        if name.startswith('__MACOSX') or any(p.startswith('.') for p in parts):
            continue
        if Path(name).name.lower() in IGNORED:
            continue
        target = (dest / name).resolve()
        if base not in target.parents and target != base:
            raise ArchiveError('Недопустимый путь в архиве.')
        if info.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        with zf.open(info) as src, open(target, 'wb') as out:
            shutil.copyfileobj(src, out)


def get_dir(token):
    if not re.fullmatch(r'[0-9a-f]{32}', token or ''):
        raise ArchiveError('Некорректный идентификатор импорта.')
    path = TMP_ROOT / token
    if not path.is_dir():
        raise ArchiveError('Сессия импорта устарела, загрузите архив заново.')
    return path


def cleanup(token):
    try:
        shutil.rmtree(get_dir(token), ignore_errors=True)
    except ArchiveError:
        pass


# ---------- разбор структуры папок ----------

def _url(path):
    return settings.MEDIA_URL + path.relative_to(settings.MEDIA_ROOT).as_posix()


def _sort_key(p):
    m = NUM_PREFIX.match(p.name)
    return (int(m.group(1)) if m else 10 ** 9, p.name.lower())


def _parse_name(name):
    m = NUM_PREFIX.match(name)
    return (int(m.group(1)), m.group(2).strip()) if m else (None, name.strip())


def _first_image(directory, preferred_stem):
    images = [p for p in sorted(directory.iterdir())
              if p.is_file() and p.suffix.lower() in IMAGE_EXT]
    for p in images:
        if p.stem.lower() == preferred_stem:
            return p
    return images[0] if images else None


def _find_audio(directory, code):
    for p in sorted(directory.iterdir()):
        if p.is_file() and p.stem.lower() == code.lower() and p.suffix.lower() in AUDIO_EXT:
            return p
    return None


def _content_root(base):
    dirs = [p for p in base.iterdir() if p.is_dir()]
    files = [p for p in base.iterdir() if p.is_file()]
    # архив запакован вместе с общей папкой-обёрткой: обёртка/тема/слово/файлы
    if len(dirs) == 1 and not files:
        inner = [p for p in dirs[0].iterdir() if p.is_dir()]
        if any(any(q.is_dir() for q in d.iterdir()) for d in inner):
            return dirs[0]
    return base


def _find_topic(src, title):
    title = (title or '').strip()
    if not title:
        return None
    tr = (TopicTranslate.objects
          .filter(language__code=src, title__iexact=title)
          .select_related('topic').order_by('topic_id').first())
    return tr.topic if tr else None


def _find_concept(topic, src, text):
    text = (text or '').strip()
    if not topic or not topic.pk or not text:
        return None
    w = (Word.objects
         .filter(concept__topic=topic, language__code=src, text__iexact=text)
         .select_related('concept').order_by('concept_id').first())
    return w.concept if w else None


def scan(token, src):
    """Строит черновик из структуры папок. Ничего не пишет в БД."""
    root = _content_root(get_dir(token))
    codes = list(Language.objects.values_list('code', flat=True))  # порядок: position, id
    if src not in codes:
        raise ArchiveError('Неизвестный язык названий.')

    topic_dirs = sorted((p for p in root.iterdir() if p.is_dir()), key=_sort_key)
    if not topic_dirs:
        raise ArchiveError('В архиве нет папок с темами.')

    draft = []
    for ti, tdir in enumerate(topic_dirs):
        pos, title = _parse_name(tdir.name)
        existing = _find_topic(src, title)

        titles = dict.fromkeys(codes, '')
        base_pos = 0
        if existing:
            for tr in existing.translations.select_related('language'):
                if tr.language.code in titles:
                    titles[tr.language.code] = tr.title
            base_pos = existing.concepts.aggregate(m=Max('position'))['m'] or 0
        titles[src] = titles[src] or title

        icon = _first_image(tdir, 'icon')
        topic = {
            'i': ti,
            'dir': tdir.name,
            'include': True,
            'existing': existing is not None,
            'difficulty': existing.difficulty if existing else 'Easy',
            'position': existing.position if existing else (pos if pos is not None else ti + 1),
            'is_active': existing.is_active if existing else True,
            'icon': icon,
            'icon_url': _url(icon) if icon else None,
            'titles': titles,
            'concepts': [],
        }

        next_pos = 0
        concept_dirs = sorted((p for p in tdir.iterdir() if p.is_dir()), key=_sort_key)
        for ci, cdir in enumerate(concept_dirs):
            cpos, word = _parse_name(cdir.name)
            concept_obj = _find_concept(existing, src, word)

            texts = dict.fromkeys(codes, '')
            trs = dict.fromkeys(codes, '')
            if concept_obj:
                for w in concept_obj.words.select_related('language'):
                    if w.language.code in texts:
                        texts[w.language.code] = w.text
                        trs[w.language.code] = w.transcription or ''
            texts[src] = texts[src] or word

            if concept_obj:
                position = concept_obj.position
            elif existing:
                next_pos += 1
                position = base_pos + next_pos
            else:
                position = cpos if cpos is not None else ci + 1

            image = _first_image(cdir, 'image')
            words = []
            for code in codes:
                audio = _find_audio(cdir, code)
                words.append({
                    'code': code,
                    'text': texts[code],
                    'transcription': trs[code],
                    'audio': audio,
                    'audio_url': _url(audio) if audio else None,
                })

            topic['concepts'].append({
                'i': ci,
                'dir': cdir.name,
                'include': True,
                'existing': concept_obj is not None,
                'difficulty': concept_obj.difficulty if concept_obj else topic['difficulty'],
                'position': position,
                'image': image,
                'image_url': _url(image) if image else None,
                'words': words,
            })
        draft.append(topic)
    return draft


def overlay(draft, post):
    """Накладывает на черновик значения, введённые на странице."""
    def num(v, default):
        v = (v or '').strip()
        return int(v) if v.isdigit() else default

    for t in draft:
        p = f't{t["i"]}'
        t['include'] = f'{p}-include' in post
        t['is_active'] = f'{p}-active' in post
        t['difficulty'] = post.get(f'{p}-difficulty', t['difficulty'])
        t['position'] = num(post.get(f'{p}-position'), t['position'])
        for code in t['titles']:
            t['titles'][code] = post.get(f'{p}-title-{code}', '').strip()
        for c in t['concepts']:
            q = f'{p}c{c["i"]}'
            c['include'] = post.get(f'{q}-include', '1') == '1'
            c['difficulty'] = post.get(f'{q}-difficulty', c['difficulty'])
            c['position'] = num(post.get(f'{q}-position'), c['position'])
            for w in c['words']:
                w['text'] = post.get(f'{q}-text-{w["code"]}', '').strip()
                w['transcription'] = post.get(f'{q}-tr-{w["code"]}', '').strip()


def validate(draft, src):
    errors = []

    seen_topics = set()
    for t in draft:
        if t['include']:
            key = t['titles'].get(src, '').strip().lower()
            if key and key in seen_topics:
                errors.append(f'[{t["titles"][src]}] тема встречается в архиве дважды, объедините папки')
            seen_topics.add(key)

    for t in draft:
        if not t['include']:
            continue
        title = t['titles'].get(src, '')
        label = title or t['dir']
        if not title:
            errors.append(f'[{label}] пустое название темы на языке «{src}»')
        if t['difficulty'] not in DIFFICULTIES:
            errors.append(f'[{label}] некорректная сложность')
        if any(len(v) > 128 for v in t['titles'].values()):
            errors.append(f'[{label}] название темы длиннее 128 символов')

        existing = _find_topic(src, title)
        if not existing and not t['icon']:
            errors.append(f'[{label}] для новой темы нужна картинка в папке темы (иконка)')

        seen = set()
        for c in t['concepts']:
            if not c['include']:
                continue
            clabel = f'{label} / {c["dir"]}'
            key = next((w['text'] for w in c['words'] if w['code'] == src), '')
            if not key:
                errors.append(f'[{clabel}] пустое слово на языке «{src}»')
                continue
            if key.lower() in seen:
                errors.append(f'[{clabel}] слово «{key}» повторяется в теме')
            seen.add(key.lower())
            if c['difficulty'] not in DIFFICULTIES:
                errors.append(f'[{clabel}] некорректная сложность')
            if any(len(w['text']) > 255 or len(w['transcription']) > 128 for w in c['words']):
                errors.append(f'[{clabel}] слишком длинный текст или транскрипция')
            if not (existing and _find_concept(existing, src, key)) and not c['image']:
                errors.append(f'[{clabel}] нет картинки слова')
    return errors


# ---------- запись в БД ----------

def _save_file(field_file, path):
    with path.open('rb') as f:
        field_file.save(f'{uuid.uuid4().hex[:8]}_{path.name}', File(f), save=False)


@transaction.atomic
def apply_draft(draft, src, update_existing=False):
    langs = {l.code: l for l in Language.objects.all()}
    stats = {'topics': 0, 'concepts': 0, 'words': 0, 'skipped': 0}

    for t in draft:
        if not t['include']:
            continue
        topic = _find_topic(src, t['titles'][src])
        is_new_topic = topic is None
        if is_new_topic:
            topic = Topic()
            stats['topics'] += 1

        # настройки существующей темы не трогаем без явной галочки
        if is_new_topic or update_existing:
            topic.difficulty = t['difficulty']
            topic.position = t['position']
            topic.is_active = t['is_active']
        if t['icon'] and (is_new_topic or update_existing or not topic.icon):
            _save_file(topic.icon, t['icon'])
        topic.save()

        for code, title in t['titles'].items():
            if not title:
                continue
            if is_new_topic or update_existing:
                TopicTranslate.objects.update_or_create(
                    topic=topic, language=langs[code], defaults={'title': title},
                )
            else:
                TopicTranslate.objects.get_or_create(
                    topic=topic, language=langs[code], defaults={'title': title},
                )

        for c in t['concepts']:
            if not c['include']:
                continue
            key = next(w['text'] for w in c['words'] if w['code'] == src)
            concept = None if is_new_topic else _find_concept(topic, src, key)
            if concept is not None and not update_existing:
                stats['skipped'] += 1
                continue
            if concept is None:
                concept = Concept(topic=topic)
                stats['concepts'] += 1
            concept.difficulty = c['difficulty']
            concept.position = c['position']
            if c['image']:
                _save_file(concept.image, c['image'])
            concept.save()

            for w in c['words']:
                if not w['text']:
                    continue
                word, created = Word.objects.get_or_create(
                    concept=concept, language=langs[w['code']],
                    defaults={'text': w['text']},
                )
                stats['words'] += created
                word.text = w['text']
                word.transcription = w['transcription'] or None
                if w['audio']:
                    _save_file(word.audio, w['audio'])
                word.save()
    return stats