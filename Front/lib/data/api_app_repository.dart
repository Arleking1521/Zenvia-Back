import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/achievement.dart';
import '../models/dragon_evolution.dart';
import '../models/daily_lesson.dart';
import '../models/learned_word.dart';
import '../models/literary_content.dart';
import '../models/language.dart';
import '../models/topic.dart';
import '../theme/app_colors.dart';
import 'api/api_client.dart';
import 'api/api_config.dart';
import 'app_repository.dart';

class ApiAppRepository implements AppRepository {

  final ApiClient client;

  ApiAppRepository(this.client);

  @override
  Future<List<LanguageOption>> getAvailableLanguages() async {
    final rows = await _getList(ApiConfig.api('languages/'));
    final result = <LanguageOption>[];

    for (final raw in rows) {
      final row = _asMap(raw);
      if (row == null) continue;

      final code = row['code']?.toString().trim() ?? '';
      final title = row['title']?.toString().trim() ?? '';
      if (code.isEmpty || title.isEmpty) continue;

      final icon = ApiConfig.absoluteMediaUrl(row['icon']?.toString());

      result.add(
        LanguageOption(
          id: _asInt(row['id']),
          code: code,
          title: title,
          position: _asInt(row['position']),
          iconUrl: icon.isEmpty ? null : icon,
        ),
      );
    }

    result.sort((a, b) {
      final byPosition = a.position.compareTo(b.position);
      if (byPosition != 0) return byPosition;
      return a.id.compareTo(b.id);
    });

    return result;
  }


  @override
  Future<List<LearnedWord>> getLearnedWordsAllLanguages() async {
    final results = await Future.wait<dynamic>([
      _getList(ApiConfig.api('progress/')),
      _getList(ApiConfig.api('words/')),
      _getList(ApiConfig.api('concepts/')),
    ]);

    final progressRows = results[0] as List<dynamic>;
    final wordRows = results[1] as List<dynamic>;
    final conceptRows = results[2] as List<dynamic>;

    final learnedKeys = <String>{};
    for (final raw in progressRows) {
      final row = _asMap(raw);
      if (row == null || _asInt(row['mastery']) < 5) continue;
      final conceptId = _asInt(row['concept']);
      final languageId = _asInt(row['language']);
      if (conceptId > 0 && languageId > 0) {
        learnedKeys.add('$conceptId:$languageId');
      }
    }

    final imageByConcept = <int, String?>{};
    for (final raw in conceptRows) {
      final row = _asMap(raw);
      if (row == null) continue;
      final conceptId = _asInt(row['id']);
      final image = ApiConfig.absoluteMediaUrl(row['image']?.toString());
      imageByConcept[conceptId] = image.isEmpty ? null : image;
    }

    final result = <LearnedWord>[];
    for (final raw in wordRows) {
      final row = _asMap(raw);
      if (row == null) continue;

      final wordId = _asInt(row['id']);
      final conceptId = _asInt(row['concept']);
      final languageId = _asInt(row['language']);
      if (!learnedKeys.contains('$conceptId:$languageId')) continue;

      final text = row['text']?.toString().trim() ?? '';
      final code = row['language_code']?.toString();
      final language = AppLanguageX.tryFromApiCode(code);
      if (wordId <= 0 || conceptId <= 0 || text.isEmpty || language == null) {
        continue;
      }

      final audio = ApiConfig.absoluteMediaUrl(row['audio']?.toString());
      final transcription = row['transcription']?.toString().trim();

      result.add(
        LearnedWord(
          wordId: wordId,
          conceptId: conceptId,
          language: language,
          text: text,
          transcription: transcription == null || transcription.isEmpty
              ? null
              : transcription,
          imageUrl: imageByConcept[conceptId],
          audioUrl: audio.isEmpty ? null : audio,
        ),
      );
    }

    result.shuffle(Random());
    return result;
  }

  List<LiteraryContentItem> _parseLiteraryContentRows(List<dynamic> rows) {
    final result = <LiteraryContentItem>[];
    for (final raw in rows) {
      final row = _asMap(raw);
      if (row == null) continue;

      final image = ApiConfig.absoluteMediaUrl(row['image']?.toString());
      final audio = ApiConfig.absoluteMediaUrl(row['audio']?.toString());
      final title = row['title']?.toString().trim();
      final author = row['author']?.toString().trim();

      result.add(
        LiteraryContentItem(
          id: _asInt(row['id']),
          title: title == null || title.isEmpty
              ? LiteraryContentTypeX.fromApiCode(
                  row['content_type']?.toString(),
                ).title
              : title,
          text: row['text']?.toString() ?? '',
          type: LiteraryContentTypeX.fromApiCode(
            row['content_type']?.toString(),
          ),
          language: AppLanguageX.fromApiCode(
            row['language_code']?.toString(),
          ),
          imageUrl: image.isEmpty ? null : image,
          audioUrl: audio.isEmpty ? null : audio,
          author: author == null || author.isEmpty ? null : author,
          difficulty: row['difficulty']?.toString() ?? '',
        ),
      );
    }
    return result;
  }

  @override
  Future<List<LiteraryContentItem>> getLiteraryContent(
    AppLanguage language,
  ) async {
    final rows = await _getList(
      ApiConfig.api('literary-content/'),
      queryParameters: {'language': language.apiCode},
    );
    return _parseLiteraryContentRows(rows);
  }

  @override
  Future<LiteraryContentPage> getLiteraryContentPage(
    AppLanguage language, {
    LiteraryContentType? type,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final query = <String, dynamic>{
        'language': language.apiCode,
        'page': page,
        'page_size': pageSize,
      };
      if (type != null && type != LiteraryContentType.other) {
        query['content_type'] = type.apiCode;
      }

      final response = await client.dio.get<dynamic>(
        ApiConfig.api('literary-content/'),
        queryParameters: query,
      );
      final data = _asMap(response.data);
      if (data == null || data['results'] is! List) {
        throw const AppApiException('Сервер вернул неожиданный формат страницы');
      }

      final rows = data['results'] as List;
      final availableTypes = <LiteraryContentType>{};
      final rawTypes = data['available_content_types'];
      if (rawTypes is List) {
        for (final rawType in rawTypes) {
          final type = LiteraryContentTypeX.fromApiCode(rawType?.toString());
          if (type != LiteraryContentType.other) {
            availableTypes.add(type);
          }
        }
      }

      return LiteraryContentPage(
        items: _parseLiteraryContentRows(rows),
        totalCount: _asInt(data['count']),
        hasNext: data['next'] != null,
        page: page,
        availableTypes: availableTypes,
      );
    } on DioException catch (e) {
      throw AppApiException(_dioMessage(e));
    }
  }

  @override
  Future<void> markLiteraryContentListened(int contentId) async {
    try {
      await client.dio.post<dynamic>(
        ApiConfig.api('content-progress/listen/'),
        data: {'content': contentId},
      );
    } on DioException catch (e) {
      throw AppApiException(_dioMessage(e));
    }
  }


  @override
  Future<DragonEvolutionData> getDragonEvolution() async {
    final current = await _getMap(ApiConfig.api('levels/current/'));
    final levelRows = await _getList(ApiConfig.api('levels/'));

    DragonLevel? parseLevel(dynamic raw) {
      final row = _asMap(raw);
      if (row == null) return null;

      final icon = ApiConfig.absoluteMediaUrl(row['icon']?.toString());
      return DragonLevel(
        id: _asInt(row['id']),
        number: _asInt(row['number']),
        title: row['title']?.toString() ?? 'Уровень',
        xpRequired: _asInt(row['xp_required']),
        iconUrl: icon.isEmpty ? null : icon,
      );
    }

    final levels = <DragonLevel>[];
    for (final raw in levelRows) {
      final level = parseLevel(raw);
      if (level != null) levels.add(level);
    }
    levels.sort((a, b) => a.number.compareTo(b.number));

    return DragonEvolutionData(
      totalXp: _asInt(current['total_xp']),
      dragonColor: current['dragon_color']?.toString() ?? 'blue',
      currentLevel: parseLevel(current['current_level']),
      nextLevel: parseLevel(current['next_level']),
      xpToNextLevel: _asInt(current['xp_to_next_level']),
      levels: levels,
    );
  }

  @override
  Future<String?> getLevelDragonUrl() async {
    final current = await _getMap(ApiConfig.api('levels/current/'));
    final currentLevel = _asMap(current['current_level']);
    final currentIcon = ApiConfig.absoluteMediaUrl(
      currentLevel?['icon']?.toString(),
    );
    if (currentIcon.isNotEmpty) return currentIcon;

    final levels = await _getList(ApiConfig.api('levels/'));
    if (levels.isNotEmpty) {
      final first = _asMap(levels.first);
      final firstIcon = ApiConfig.absoluteMediaUrl(
        first?['icon']?.toString(),
      );
      if (firstIcon.isNotEmpty) return firstIcon;
    }
    return null;
  }

  @override
  Future<String> getChildName() async {
    final childId = await _selectedChildId();
    final child = await _getMap(ApiConfig.account('children/$childId/'));
    final name = child['name']?.toString().trim();
    return (name == null || name.isEmpty) ? 'Друг' : name;
  }

  @override
  Future<int> getXp() async {
    final response = await _getMap(ApiConfig.api('levels/current/'));
    return _asInt(response['total_xp']);
  }

  @override
  Future<int> getLevel() async {
    final response = await _getMap(ApiConfig.api('levels/current/'));
    final level = _asMap(response['current_level']);
    return _asInt(level?['number']);
  }

  @override
  Future<AppLanguage> getSelectedLanguage() async {
    final childId = await _selectedChildId();
    final prefs = await SharedPreferences.getInstance();
    final key = 'selected_learning_language_$childId';
    final savedCode = prefs.getString(key);
    if (savedCode != null && savedCode.isNotEmpty) {
      return AppLanguageX.fromApiCode(savedCode);
    }

    // По умолчанию предлагаем язык, отличный от базового языка ребёнка.
    final child = await _getMap(ApiConfig.account('children/$childId/'));
    final base = _asMap(child['base_language']);
    final baseCode = base?['code']?.toString();
    final defaultLanguage = baseCode == 'en'
        ? AppLanguage.russian
        : AppLanguage.english;
    await prefs.setString(key, defaultLanguage.apiCode);
    return defaultLanguage;
  }

  @override
  Future<void> setSelectedLanguage(AppLanguage lang) async {
    final childId = await _selectedChildId();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_learning_language_$childId', lang.apiCode);
  }

  @override
  Future<List<Topic>> getTopics() async {
    final selectedLanguage = await getSelectedLanguage();

    final topicRows = await _getList(
      ApiConfig.api('topics/by-language/'),
      queryParameters: {'language': selectedLanguage.apiCode},
    );

    final conceptRows = await _getList(ApiConfig.api('concepts/'));
    final wordRows = await _getList(ApiConfig.api('words/'));
    final wordsByConcept = <int, List<Map<String, dynamic>>>{};
    for (final raw in wordRows) {
      final row = _asMap(raw);
      if (row == null) continue;
      final conceptId = _asInt(row['concept']);
      if (conceptId <= 0) continue;
      wordsByConcept.putIfAbsent(conceptId, () => []).add(row);
    }

    final conceptsByTopic = <int, List<Map<String, dynamic>>>{};
    for (final raw in conceptRows) {
      final row = _asMap(raw);
      if (row == null) continue;
      final topicId = _asInt(row['topic']);
      if (topicId <= 0) continue;
      conceptsByTopic.putIfAbsent(topicId, () => []).add(row);
    }

    const topicColors = <Color>[
      AppColors.accentYellow,
      AppColors.accentBlue,
      AppColors.accentCoral,
      AppColors.accentPurple,
      AppColors.accentTeal,
    ];

    final result = <Topic>[];

    for (var i = 0; i < topicRows.length; i++) {
      final topicRow = _asMap(topicRows[i]);
      if (topicRow == null) continue;

      final topicId = _asInt(topicRow['id']);
      final conceptList = List<Map<String, dynamic>>.from(
        conceptsByTopic[topicId] ?? const [],
      )..sort(
          (a, b) => _asInt(a['position']).compareTo(_asInt(b['position'])),
        );

      final learnedConceptIds = <int>{};
      final rawLearnedIds = topicRow['learned_concept_ids'];
      if (rawLearnedIds is List) {
        for (final rawId in rawLearnedIds) {
          final id = _asInt(rawId);
          if (id > 0) learnedConceptIds.add(id);
        }
      }

      final items = <WordItem>[];

      for (final concept in conceptList) {
        final conceptId = _asInt(concept['id']);
        final translations = <AppLanguage, String>{};
        final audioUrls = <AppLanguage, String?>{};
        final transcriptions = <AppLanguage, String?>{};

        for (final word in wordsByConcept[conceptId] ?? const []) {
          final code = word['language_code']?.toString();
          if (code == null || code.isEmpty) continue;

          final language = AppLanguageX.fromApiCode(code);
          translations[language] = word['text']?.toString() ?? '';

          final audio = ApiConfig.absoluteMediaUrl(
            word['audio']?.toString(),
          );
          audioUrls[language] = audio.isEmpty ? null : audio;

          final transcription = word['transcription']?.toString();
          transcriptions[language] =
              (transcription == null || transcription.isEmpty)
                  ? null
                  : transcription;
        }

        final image = ApiConfig.absoluteMediaUrl(
          concept['image']?.toString(),
        );

        items.add(
          WordItem(
            id: conceptId.toString(),
            translations: translations,
            audioUrls: audioUrls,
            transcriptions: transcriptions,
            imageUrl: image.isEmpty ? null : image,
          ),
        );
      }

      final learnedCount = conceptList
          .where((concept) => learnedConceptIds.contains(_asInt(concept['id'])))
          .length;

      final preview = items
          .map((word) => word.translationFor(selectedLanguage))
          .where((text) => text.isNotEmpty)
          .take(3)
          .join(', ');

      final difficulty = topicRow['difficulty']?.toString() ?? '';
      final description = preview.isNotEmpty
          ? preview
          : '${items.length} слов${difficulty.isEmpty ? '' : ' · $difficulty'}';

      final icon = ApiConfig.absoluteMediaUrl(
        topicRow['icon']?.toString(),
      );

      result.add(
        Topic(
          id: topicId.toString(),
          number: i + 1,
          title: topicRow['title']?.toString() ?? 'Тема',
          description: description,
          emoji: '',
          iconUrl: icon.isEmpty ? null : icon,
          color: topicColors[i % topicColors.length],
          words: items,
          learnedCount: learnedCount,
          learnedWordIds: learnedConceptIds.map((id) => id.toString()).toSet(),
        ),
      );
    }

    return result;
  }


  @override
  Future<DailyLessonPlan> getDailyLesson({
    required Topic topic,
    required AppLanguage language,
  }) async {
    final topicId = int.tryParse(topic.id);
    if (topicId == null) {
      throw const AppApiException('Не удалось определить ID темы.');
    }

    final row = await _getMap(
      ApiConfig.api('daily-lessons/current/'),
      queryParameters: {
        'topic': topicId,
        'language': language.apiCode,
      },
    );
    return _dailyLesson(row);
  }

  @override
  Future<DailyLessonPlan> markDailyWordListened({
    required int lessonId,
    required String wordId,
  }) async {
    final conceptId = int.tryParse(wordId);
    if (conceptId == null) {
      throw const AppApiException('Не удалось определить ID слова.');
    }

    try {
      final response = await client.dio.post<dynamic>(
        ApiConfig.api('daily-lessons/$lessonId/listen/'),
        data: {'concept': conceptId},
      );
      final row = _asMap(response.data);
      if (row == null) {
        throw const AppApiException('Сервер вернул неожиданный формат ежедневного урока.');
      }
      return _dailyLesson(row);
    } on DioException catch (e) {
      throw AppApiException(_dioMessage(e));
    }
  }

  DailyLessonPlan _dailyLesson(Map<String, dynamic> row) {
    final languageCode = row['language_code']?.toString();
    final language = AppLanguageX.tryFromApiCode(languageCode);
    if (language == null) {
      throw AppApiException('Неизвестный язык ежедневного урока: $languageCode');
    }

    final words = <WordItem>[];
    final studied = <String>{};
    final rawItems = row['items'];

    if (rawItems is List) {
      for (final raw in rawItems) {
        final item = _asMap(raw);
        if (item == null) continue;
        final conceptId = _asInt(item['concept']);
        final word = _asMap(item['word']);
        if (conceptId <= 0 || word == null) continue;

        final text = word['text']?.toString() ?? '';
        final audio = ApiConfig.absoluteMediaUrl(word['audio']?.toString());
        final image = ApiConfig.absoluteMediaUrl(item['image']?.toString());
        final transcription = word['transcription']?.toString().trim();

        words.add(
          WordItem(
            id: conceptId.toString(),
            translations: {language: text},
            audioUrls: {language: audio.isEmpty ? null : audio},
            transcriptions: {
              language: transcription == null || transcription.isEmpty
                  ? null
                  : transcription,
            },
            imageUrl: image.isEmpty ? null : image,
          ),
        );

        if (item['listened'] == true) {
          studied.add(conceptId.toString());
        }
      }
    }

    return DailyLessonPlan(
      lessonId: _asInt(row['id']),
      words: words,
      studiedWordIds: studied,
      requiredCount: _asInt(row['required_count']),
      isComplete: row['is_complete'] == true,
      date: row['date']?.toString(),
    );
  }

  @override
  Future<List<Achievement>> getAchievements() async {
    final achievements = await _getList(ApiConfig.api('achievements/'));
    final earnedRows = await _getList(ApiConfig.api('my-achievements/'));

    final earnedIds = <int>{};
    for (final raw in earnedRows) {
      final row = _asMap(raw);
      final achievement = _asMap(row?['achievement']);
      if (achievement != null) {
        earnedIds.add(_asInt(achievement['id']));
      }
    }

    // Данные ниже позволяют вычислить текущий прогресс без дополнительного
    // backend-endpoint. Если позже backend будет отдавать current напрямую,
    // эту часть можно будет упростить.
    final progressRows = await _getList(ApiConfig.api('progress/'));
    final gameRows = await _getList(ApiConfig.api('game-sessions/'));
    final conceptRows = await _getList(ApiConfig.api('concepts/'));
    final topicRows = await _getList(ApiConfig.api('topics/'));
    final contentProgressRows =
        await _getList(ApiConfig.api('content-progress/'));
    final languageRows = await _getList(ApiConfig.api('languages/'));
    final levelInfo = await _getMap(ApiConfig.api('levels/current/'));

    final languageCodeById = <int, String>{};
    for (final raw in languageRows) {
      final row = _asMap(raw);
      if (row == null) continue;
      languageCodeById[_asInt(row['id'])] = row['code']?.toString() ?? '';
    }

    final allContentRows = <Map<String, dynamic>>[];
    for (final code in languageCodeById.values.where((c) => c.isNotEmpty)) {
      final rows = await _getList(
        ApiConfig.api('literary-content/'),
        queryParameters: {'language': code},
      );
      for (final raw in rows) {
        final row = _asMap(raw);
        if (row != null) allContentRows.add(row);
      }
    }

    final conceptTopicById = <int, int>{};
    final conceptsByTopic = <int, List<int>>{};
    for (final raw in conceptRows) {
      final row = _asMap(raw);
      if (row == null) continue;
      final conceptId = _asInt(row['id']);
      final topicId = _asInt(row['topic']);
      conceptTopicById[conceptId] = topicId;
      conceptsByTopic.putIfAbsent(topicId, () => []).add(conceptId);
    }

    final contentById = <int, Map<String, dynamic>>{};
    for (final row in allContentRows) {
      contentById[_asInt(row['id'])] = row;
    }

    const achievementColors = <Color>[
      AppColors.background,
      Color(0xFFE1F5EE),
      Color(0xFFFAECE7),
      Color(0xFFFBEAF0),
      AppColors.lockedBg,
    ];

    final result = <Achievement>[];

    for (var i = 0; i < achievements.length; i++) {
      final row = _asMap(achievements[i]);
      if (row == null) continue;

      final id = _asInt(row['id']);
      final target = _asInt(row['condition_value']);
      final languageId = _nullableInt(row['language']);
      final topicId = _nullableInt(row['topic']);
      final condition = row['condition_type']?.toString() ?? '';

      var current = _achievementCurrentValue(
        condition: condition,
        languageId: languageId,
        topicId: topicId,
        progressRows: progressRows,
        gameRows: gameRows,
        contentProgressRows: contentProgressRows,
        contentById: contentById,
        conceptTopicById: conceptTopicById,
        conceptsByTopic: conceptsByTopic,
        topicRows: topicRows,
        totalXp: _asInt(levelInfo['total_xp']),
      );

      if (earnedIds.contains(id)) {
        current = max(current, target);
      }

      final icon = ApiConfig.absoluteMediaUrl(row['icon']?.toString());

      result.add(
        Achievement(
          id: id.toString(),
          title: row['title']?.toString() ?? 'Достижение',
          description: row['description']?.toString() ?? '',
          emoji: _achievementEmoji(condition),
          iconUrl: icon.isEmpty ? null : icon,
          iconBg: achievementColors[i % achievementColors.length],
          current: current,
          target: target,
          xpReward: _asInt(row['xp_reward']),
        ),
      );
    }

    return result;
  }

  int _achievementCurrentValue({
    required String condition,
    required int? languageId,
    required int? topicId,
    required List<dynamic> progressRows,
    required List<dynamic> gameRows,
    required List<dynamic> contentProgressRows,
    required Map<int, Map<String, dynamic>> contentById,
    required Map<int, int> conceptTopicById,
    required Map<int, List<int>> conceptsByTopic,
    required List<dynamic> topicRows,
    required int totalXp,
  }) {
    bool progressMatches(Map<String, dynamic> row) {
      if (languageId != null && _asInt(row['language']) != languageId) {
        return false;
      }
      if (topicId != null) {
        final conceptId = _asInt(row['concept']);
        if (conceptTopicById[conceptId] != topicId) return false;
      }
      return true;
    }

    bool gameMatches(Map<String, dynamic> row) {
      if (row['finished_at'] == null) return false;
      if (languageId != null && _asInt(row['language']) != languageId) {
        return false;
      }
      if (topicId != null && _asInt(row['topic']) != topicId) {
        return false;
      }
      return true;
    }

    switch (condition) {
      case 'words_learned':
        return progressRows
            .map(_asMap)
            .whereType<Map<String, dynamic>>()
            .where(progressMatches)
            .where((row) => _asInt(row['mastery']) >= 5)
            .length;

      case 'games_completed':
        return gameRows
            .map(_asMap)
            .whereType<Map<String, dynamic>>()
            .where(gameMatches)
            .length;

      case 'correct_answers':
        return gameRows
            .map(_asMap)
            .whereType<Map<String, dynamic>>()
            .where(gameMatches)
            .fold<int>(
              0,
              (sum, row) => sum + _asInt(row['correct_count']),
            );

      case 'perfect_games':
        return gameRows
            .map(_asMap)
            .whereType<Map<String, dynamic>>()
            .where(gameMatches)
            .where(
              (row) =>
                  _asInt(row['wrong_count']) == 0 &&
                  _asInt(row['correct_count']) > 0,
            )
            .length;

      case 'poems_listened':
        return contentProgressRows
            .map(_asMap)
            .whereType<Map<String, dynamic>>()
            .where((progress) {
          if (_asInt(progress['listen_count']) <= 0) return false;
          final content = contentById[_asInt(progress['content'])];
          if (content == null || content['content_type'] != 'poem') {
            return false;
          }
          if (languageId != null &&
              _asInt(content['language']) != languageId) {
            return false;
          }
          return true;
        }).length;

      case 'proverbs_learned':
        return contentProgressRows
            .map(_asMap)
            .whereType<Map<String, dynamic>>()
            .where((progress) {
          if (progress['is_completed'] != true) return false;
          final content = contentById[_asInt(progress['content'])];
          if (content == null || content['content_type'] != 'proverb') {
            return false;
          }
          if (languageId != null &&
              _asInt(content['language']) != languageId) {
            return false;
          }
          return true;
        }).length;

      case 'topics_completed':
        if (languageId == null) return 0;

        final activeTopicIds = topicRows
            .map(_asMap)
            .whereType<Map<String, dynamic>>()
            .where((row) => row['is_active'] != false)
            .map((row) => _asInt(row['id']))
            .where((id) => id > 0)
            .where((id) => topicId == null || id == topicId)
            .toList();

        var completed = 0;

        for (final id in activeTopicIds) {
          final conceptIds = conceptsByTopic[id] ?? const [];
          if (conceptIds.isEmpty) continue;

          final learnedIds = progressRows
              .map(_asMap)
              .whereType<Map<String, dynamic>>()
              .where(
                (row) =>
                    _asInt(row['language']) == languageId &&
                    _asInt(row['mastery']) >= 5 &&
                    conceptIds.contains(_asInt(row['concept'])),
              )
              .map((row) => _asInt(row['concept']))
              .toSet();

          if (learnedIds.length == conceptIds.length) {
            completed++;
          }
        }

        return completed;

      case 'xp_earned':
        return totalXp;

      default:
        return 0;
    }
  }

  String _achievementEmoji(String condition) {
    switch (condition) {
      case 'words_learned':
        return '';
      case 'games_completed':
        return '';
      case 'correct_answers':
        return '';
      case 'perfect_games':
        return '';
      case 'poems_listened':
        return '';
      case 'proverbs_learned':
        return '';
      case 'topics_completed':
        return '';
      case 'xp_earned':
        return '';
      default:
        return '';
    }
  }

  Future<int> _selectedChildId() async {
    final childId = await client.childSessionStorage.readSelectedChildId();
    if (childId == null || childId <= 0) {
      throw const AppApiException('Сначала выберите профиль ребёнка.');
    }
    return childId;
  }

  Future<List<dynamic>> _getList(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await client.dio.get<dynamic>(
        path,
        queryParameters: queryParameters,
      );
      final data = response.data;

      if (data is List) return data;

      // На случай, если позже в DRF включат pagination.
      if (data is Map && data['results'] is List) {
        return data['results'] as List;
      }

      throw const AppApiException('Сервер вернул неожиданный формат списка');
    } on DioException catch (e) {
      throw AppApiException(_dioMessage(e));
    }
  }

  Future<Map<String, dynamic>> _getMap(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await client.dio.get<dynamic>(
        path,
        queryParameters: queryParameters,
      );
      final map = _asMap(response.data);
      if (map == null) {
        throw const AppApiException('Сервер вернул неожиданный формат данных');
      }
      return map;
    } on DioException catch (e) {
      throw AppApiException(_dioMessage(e));
    }
  }

  String _dioMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      if (data['detail'] != null) return data['detail'].toString();
      if (data['error'] != null) return data['error'].toString();
    }

    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'Нет соединения с Django. Проверь IP компьютера, Wi-Fi и firewall.';
    }

    return 'Ошибка API: ${e.response?.statusCode ?? e.type.name}';
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, dynamic item) => MapEntry(key.toString(), item),
      );
    }
    return null;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _nullableInt(dynamic value) {
    if (value == null) return null;
    final parsed = int.tryParse(value.toString());
    return parsed;
  }
}

class AppApiException implements Exception {
  final String message;

  const AppApiException(this.message);

  @override
  String toString() => message;
}
