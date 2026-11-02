import csv
import secrets
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from account.models import Kindergarten, PromoCode, TariffPlan


ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'


class Command(BaseCommand):
    help = 'Генерирует один или набор универсальных промокодов Zenvia Kids.'

    def add_arguments(self, parser):
        parser.add_argument('--tariff-code', required=True)
        parser.add_argument(
            '--mode',
            choices=[PromoCode.MODE_DIRECT_ACCESS, PromoCode.MODE_GOOGLE_PLAY],
            required=True,
        )
        parser.add_argument(
            '--channel',
            choices=[value for value, _ in PromoCode.CHANNEL_CHOICES],
            default=PromoCode.CHANNEL_OTHER,
        )
        parser.add_argument('--count', type=int, default=1)
        parser.add_argument('--prefix', default='ZK')
        parser.add_argument('--fixed-code', default='')
        parser.add_argument('--kindergarten-id', type=int)
        parser.add_argument('--partner', default='')
        parser.add_argument('--campaign', default='')
        parser.add_argument('--manager', default='')
        parser.add_argument('--access-days', type=int)
        parser.add_argument(
            '--max-uses',
            type=int,
            help='1 = одноразовый; 0 = без общего лимита. По умолчанию для direct_access используется 1.',
        )
        parser.add_argument('--output', default='')

    def handle(self, *args, **options):
        count = options['count']
        if count < 1 or count > 10000:
            raise CommandError('--count должен быть от 1 до 10000.')
        fixed_code = (options['fixed_code'] or '').strip().upper()
        if fixed_code and count != 1:
            raise CommandError('--fixed-code можно использовать только с --count 1.')

        tariff = TariffPlan.objects.filter(code=options['tariff_code']).first()
        if tariff is None:
            raise CommandError(f"Тариф {options['tariff_code']!r} не найден.")

        kindergarten = None
        if options.get('kindergarten_id'):
            kindergarten = Kindergarten.objects.filter(pk=options['kindergarten_id']).first()
            if kindergarten is None:
                raise CommandError('Детский сад с указанным ID не найден.')

        mode = options['mode']
        if mode == PromoCode.MODE_GOOGLE_PLAY and not tariff.google_play_enabled:
            raise CommandError('Для режима google_play тариф должен иметь google_play_enabled=True.')

        access_days = options.get('access_days')
        if mode == PromoCode.MODE_GOOGLE_PLAY and access_days is not None:
            raise CommandError('--access-days применяется только к direct_access.')
        if access_days is not None and access_days < 1:
            raise CommandError('--access-days должен быть не меньше 1.')

        max_uses_arg = options.get('max_uses')
        if max_uses_arg is None:
            max_uses = 1 if mode == PromoCode.MODE_DIRECT_ACCESS else None
        elif max_uses_arg == 0:
            max_uses = None
        elif max_uses_arg > 0:
            max_uses = max_uses_arg
        else:
            raise CommandError('--max-uses не может быть отрицательным.')

        prefix = ''.join(ch for ch in (options['prefix'] or 'ZK').upper() if ch.isalnum())[:12] or 'ZK'
        rows = []

        with transaction.atomic():
            for index in range(count):
                code = fixed_code or self._unique_code(prefix)
                promo = PromoCode(
                    code=code,
                    mode=mode,
                    channel=options['channel'],
                    kindergarten=kindergarten,
                    partner_name=(options['partner'] or '').strip(),
                    campaign_name=(options['campaign'] or '').strip(),
                    manager_name=(options['manager'] or '').strip(),
                    tariff=tariff,
                    access_days=access_days,
                    max_uses=max_uses,
                    one_use_per_parent=True,
                    is_active=True,
                )
                promo.full_clean()
                promo.save()
                rows.append(promo)

        output = (options['output'] or '').strip()
        if output:
            path = Path(output).expanduser()
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('w', newline='', encoding='utf-8-sig') as handle:
                writer = csv.writer(handle)
                writer.writerow([
                    'code', 'mode', 'channel', 'campaign', 'partner', 'manager',
                    'kindergarten', 'tariff', 'access_days', 'max_uses',
                ])
                for promo in rows:
                    writer.writerow([
                        promo.code,
                        promo.mode,
                        promo.channel,
                        promo.campaign_name,
                        promo.partner_name,
                        promo.manager_name,
                        promo.kindergarten.name if promo.kindergarten_id else '',
                        promo.tariff.code,
                        promo.effective_access_days if promo.mode == PromoCode.MODE_DIRECT_ACCESS else '',
                        promo.max_uses if promo.max_uses is not None else '',
                    ])
            self.stdout.write(self.style.SUCCESS(f'CSV сохранён: {path}'))

        self.stdout.write(self.style.SUCCESS(f'Создано промокодов: {len(rows)}'))
        for promo in rows:
            self.stdout.write(promo.code)

    def _unique_code(self, prefix):
        for _ in range(100):
            suffix = ''.join(secrets.choice(ALPHABET) for _ in range(8))
            code = f'{prefix}-{suffix[:4]}-{suffix[4:]}'
            if not PromoCode.objects.filter(code=code).exists():
                return code
        raise CommandError('Не удалось сгенерировать уникальный промокод.')
