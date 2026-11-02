import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../data/game_repository.dart';
import '../models/game.dart';
import '../l10n/app_strings.dart';
import '../models/daily_lesson.dart';
import '../models/language.dart';
import '../models/topic.dart';
import '../theme/app_colors.dart';
import '../widgets/magic_ui.dart';
import '../services/daily_lesson_service.dart';
import 'daily_words_lesson_screen.dart';
import 'dictionary_screen.dart';
import 'game_play_screen.dart';

class TopicDetailScreen extends StatefulWidget {
  final Topic topic;
  final AppLanguage language;
  final AppRepository appRepository;
  final GameRepository gameRepository;

  const TopicDetailScreen({
    super.key,
    required this.topic,
    required this.language,
    required this.appRepository,
    required this.gameRepository,
  });

  @override
  State<TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<TopicDetailScreen> {
  late Topic _topic;
  late Future<void> _imagesFuture;
  bool _startingGame = false;
  bool _routeBusy = false;
  bool _refreshing = false;
  DailyLessonPlan? _dailyLessonPlan;
  bool _loadingDailyLesson = false;

  @override
  void initState() {
    super.initState();
    _topic = widget.topic;
    _imagesFuture = _preloadImages();
    _loadDailyLesson();
  }

  Future<void> _preloadImages() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await precacheBackendImages(context, <String?>[_topic.iconUrl]);
  }

  Future<void> _loadDailyLesson() async {
    if (_loadingDailyLesson) return;
    _loadingDailyLesson = true;
    try {
      final plan = await DailyLessonService(widget.appRepository).loadPlan(
        topic: _topic,
        language: widget.language,
      );
      if (mounted) setState(() => _dailyLessonPlan = plan);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      _loadingDailyLesson = false;
    }
  }

  Future<void> _openDailyLesson() async {
    if (_routeBusy) return;
    _routeBusy = true;
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DailyWordsLessonScreen(
            topic: _topic,
            language: widget.language,
            repository: widget.appRepository,
          ),
        ),
      );
      if (!mounted) return;
      await _loadDailyLesson();
      await _refreshTopic();
    } finally {
      _routeBusy = false;
    }
  }

  Future<bool> _ensureDailyLessonComplete() async {
    var plan = _dailyLessonPlan;
    plan ??= await DailyLessonService(widget.appRepository).loadPlan(
      topic: _topic,
      language: widget.language,
    );
    if (mounted) setState(() => _dailyLessonPlan = plan);
    if (plan.isComplete) return true;

    await _openDailyLesson();
    if (!mounted) return false;
    final latest = await DailyLessonService(widget.appRepository).loadPlan(
      topic: _topic,
      language: widget.language,
    );
    if (mounted) setState(() => _dailyLessonPlan = latest);
    return latest.isComplete;
  }

  Future<void> _refreshTopic() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final topics = await widget.appRepository.getTopics();
      for (final topic in topics) {
        if (topic.id == _topic.id) {
          if (mounted) setState(() => _topic = topic);
          break;
        }
      }
    } catch (_) {
      // Не ломаем экран из-за фонового обновления прогресса.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _openDictionary() async {
    if (_routeBusy) return;
    _routeBusy = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DictionaryScreen(
            topic: _topic,
            language: widget.language,
          ),
        ),
      );
      if (mounted) await _refreshTopic();
    } finally {
      _routeBusy = false;
    }
  }

  Future<void> _startGame(GameType gameType) async {
    if (_startingGame) return;
    if (!await _ensureDailyLessonComplete()) return;

    final topicId = int.tryParse(_topic.id);
    if (topicId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('noQuestion'))),
      );
      return;
    }

    setState(() => _startingGame = true);
    try {
      final session = await widget.gameRepository.startGame(
        GameStartRequest(
          topicId: topicId,
          language: widget.language,
          gameType: gameType,
          questionCount: gameType == GameType.matching ? 3 : 10,
        ),
      );

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GamePlayScreen(
            repository: widget.gameRepository,
            session: session,
            topicTitle: _topic.title,
          ),
        ),
      );

      if (mounted) await _refreshTopic();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _startingGame = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _imagesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: ZenviaLoadingScreen());
        }
        return _buildReady(context);
      },
    );
  }

  Widget _buildReady(BuildContext context) {
    final total = _topic.totalCount;
    final learned = _topic.learnedCount;
    final progress = _topic.progress.clamp(0.0, 1.0);
    final gamesUnlocked = _dailyLessonPlan?.isComplete == true;

    return Scaffold(
      body: CloudWorldBackground(
        child: SafeArea(
          child: Stack(
            children: [
              RefreshIndicator(
                onRefresh: _refreshTopic,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
                  children: [
                    Row(
                      children: [
                        _RoundButton(
                          icon: Icons.arrow_back_rounded,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _topic.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.deepBlue,
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .94),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.auto_awesome_rounded, size: 17, color: AppColors.goldDark),
                              const SizedBox(width: 4),
                              Text(
                                '$learned/$total',
                                style: const TextStyle(
                                  color: AppColors.deepBlue,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _TopicHero(topic: _topic),
                    const SizedBox(height: 16),
                    MagicCard(
                      radius: 28,
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  context.tr('topicProgress'),
                                  style: const TextStyle(
                                    color: AppColors.deepBlue,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Text(
                                '${(progress * 100).round()}%',
                                style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 11),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 13,
                              backgroundColor: AppColors.trackGrey,
                              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            total == 0
                                ? context.tr('noWordsTopic')
                                : context.tr('learnedWordsCount', {'learned': learned, 'total': total}),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _DailyLessonCard(
                      plan: _dailyLessonPlan,
                      loading: _loadingDailyLesson,
                      onTap: _openDailyLesson,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      context.tr('topicDictionary'),
                      style: const TextStyle(
                        color: AppColors.deepBlue,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DictionaryCard(topic: _topic, onTap: _openDictionary),
                    const SizedBox(height: 22),
                    Text(
                      context.tr('practiceInGames'),
                      style: const TextStyle(
                        color: AppColors.deepBlue,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      gamesUnlocked
                          ? context.tr('gamesUnlocked')
                          : context.tr('learnWordsFirstGames'),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: .93,
                      children: [
                        _GameCard(
                          type: GameType.imageChoice,
                          colors: const [Color(0xFFFFC94B), Color(0xFFFF9749)],
                          locked: !gamesUnlocked,
                          onTap: gamesUnlocked
                              ? () => _startGame(GameType.imageChoice)
                              : _openDailyLesson,
                        ),
                        _GameCard(
                          type: GameType.wordChoice,
                          colors: const [Color(0xFF6CC8FF), Color(0xFF4A8EF5)],
                          locked: !gamesUnlocked,
                          onTap: gamesUnlocked
                              ? () => _startGame(GameType.wordChoice)
                              : _openDailyLesson,
                        ),
                        _GameCard(
                          type: GameType.audioChoice,
                          colors: const [Color(0xFFFF9B9B), Color(0xFFFF6C87)],
                          locked: !gamesUnlocked,
                          onTap: gamesUnlocked
                              ? () => _startGame(GameType.audioChoice)
                              : _openDailyLesson,
                        ),
                        _GameCard(
                          type: GameType.matching,
                          colors: const [Color(0xFF53E0C6), Color(0xFF25BFA9)],
                          locked: !gamesUnlocked,
                          onTap: gamesUnlocked
                              ? () => _startGame(GameType.matching)
                              : _openDailyLesson,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_startingGame)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0x550E3B7D),
                    child: Center(
                      child: MagicCard(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: AppColors.primary),
                            const SizedBox(width: 14),
                            Text(context.tr('preparingGame'), style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicHero extends StatelessWidget {
  final Topic topic;
  const _TopicHero({required this.topic});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 205,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            topic.color.withValues(alpha: .95),
            topic.color.withValues(alpha: .68),
          ],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: topic.color.withValues(alpha: .24),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 18,
            top: 20,
            right: 165,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('topicIsland'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  topic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  topic.description.isEmpty
                      ? context.tr('learnAndPractice')
                      : topic.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 4,
            bottom: 0,
            width: 170,
            height: 190,
            child: _TopicImage(topic: topic),
          ),
        ],
      ),
    );
  }
}

class _DailyLessonCard extends StatelessWidget {
  final DailyLessonPlan? plan;
  final bool loading;
  final VoidCallback onTap;

  const _DailyLessonCard({
    required this.plan,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final complete = plan?.isComplete == true;
    final total = plan?.requiredCount ?? DailyLessonService.wordsPerDay;
    final studied = plan?.studiedCount ?? 0;
    final progress = total == 0 ? 1.0 : (studied / total).clamp(0.0, 1.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: complete
                  ? const [Color(0xFF43DA83), Color(0xFF16B967)]
                  : const [Color(0xFFFFD95E), Color(0xFFFFA83D)],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: (complete ? const Color(0xFF16B967) : const Color(0xFFFFA83D))
                    .withValues(alpha: .22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  complete ? Icons.star_rounded : Icons.auto_stories_rounded,
                  color: complete ? AppColors.primary : AppColors.goldDark,
                  size: 38,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      complete ? context.tr('newWordsLearned') : context.tr('fiveNewWordsToday'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      complete
                          ? context.tr('topicGamesAvailable')
                          : loading
                              ? context.tr('loadingSet')
                              : context.tr('learnToUnlock', {'studied': studied, 'total': total}),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: .28),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _DictionaryCard extends StatelessWidget {
  final Topic topic;
  final VoidCallback onTap;

  const _DictionaryCard({required this.topic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7ACBFF), Color(0xFF4D8DF4)],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4D8DF4).withValues(alpha: .22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.menu_book_rounded, color: Color(0xFF4A8EF5), size: 38),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('dictionary'),
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('wordsPicturesPronunciation', {'count': topic.learnedCount}),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: topic.progress,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: .28),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const CircleAvatar(
                radius: 19,
                backgroundColor: Colors.white,
                child: Icon(Icons.arrow_forward_rounded, color: Color(0xFF4A8EF5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final GameType type;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool locked;

  const _GameCard({
    required this.type,
    required this.colors,
    required this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: colors.last.withValues(alpha: .22),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Все элементы привязаны к одной и той же сетке.
              // Длина текста больше не может сдвинуть соседние элементы.
              final h = constraints.maxHeight;
              final iconTop = h * .16;
              final titleTop = h * .57;
              final subtitleTop = h * .77;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: locked ? .52 : 1,
                      child: Stack(
                        children: [
                          Positioned(
                            top: iconTop,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                width: 64,
                                height: 64,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .93),
                                  shape: BoxShape.circle,
                                ),
                                child: SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: Center(
                                    child: Image.asset(
                                      type.assetPath,
                                      width: 42,
                                      height: 42,
                                      fit: BoxFit.contain,
                                      alignment: Alignment.center,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: titleTop,
                            left: 10,
                            right: 10,
                            height: 38,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Text(
                                type.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: subtitleTop,
                            left: 10,
                            right: 10,
                            height: 30,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Text(
                                _description(context, type),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .92),
                                  fontSize: 10.5,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (locked)
                    const Positioned(
                      right: 6,
                      top: 6,
                      child: SizedBox(
                        width: 34,
                        height: 34,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.lock_rounded,
                            color: AppColors.deepBlue,
                            size: 19,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _description(BuildContext context, GameType type) {
    switch (type) {
      case GameType.imageChoice:
        return context.tr('readFindPicture');
      case GameType.wordChoice:
        return context.tr('lookChooseWord');
      case GameType.audioChoice:
        return context.tr('listenChoose');
      case GameType.matching:
        return context.tr('matchPairs');
    }
  }
}

class _TopicImage extends StatelessWidget {
  final Topic topic;
  const _TopicImage({required this.topic});

  @override
  Widget build(BuildContext context) {
    final url = topic.iconUrl;
    if (url == null || url.isEmpty) {
      return Center(child: Image.asset('assets/images/ui/picture.webp', width: 112, height: 112, fit: BoxFit.contain));
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Center(child: Image.asset('assets/images/ui/picture.webp', width: 112, height: 112, fit: BoxFit.contain)),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .95),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(width: 46, height: 46, child: Icon(icon, color: AppColors.deepBlue)),
      ),
    );
  }
}
