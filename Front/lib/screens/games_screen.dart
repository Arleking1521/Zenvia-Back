import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../data/game_repository.dart';
import '../models/game.dart';
import '../models/language.dart';
import '../models/topic.dart';
import '../l10n/app_strings.dart';
import '../services/background_music_service.dart';
import '../theme/app_colors.dart';
import '../services/daily_lesson_service.dart';
import '../widgets/magic_ui.dart';
import 'game_play_screen.dart';
import 'daily_words_lesson_screen.dart';

class GamesScreen extends StatefulWidget {
  final AppRepository appRepository;
  final GameRepository gameRepository;

  const GamesScreen({
    super.key,
    required this.appRepository,
    required this.gameRepository,
  });

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  final Object _musicSilenceToken = Object();
  late Future<_GamesData> _future;
  bool _starting = false;

  static const _colors = <GameType, List<Color>>{
    GameType.imageChoice: [Color(0xFFFFD85A), Color(0xFFFFA94D)],
    GameType.wordChoice: [Color(0xFF6CC8FF), Color(0xFF4A8EF5)],
    GameType.audioChoice: [Color(0xFFFF9B9B), Color(0xFFFF6C87)],
    GameType.matching: [Color(0xFF53E0C6), Color(0xFF25BFA9)],
  };

  @override
  void initState() {
    super.initState();
    BackgroundMusicService.instance.silence(_musicSilenceToken);
    _future = _load();
  }

  @override
  void dispose() {
    BackgroundMusicService.instance.unsilence(_musicSilenceToken);
    super.dispose();
  }

  Future<_GamesData> _load() async {
    final values = await Future.wait([
      widget.appRepository.getTopics(),
      widget.appRepository.getSelectedLanguage(),
    ]);
    final data = _GamesData(
      topics: values[0] as List<Topic>,
      language: values[1] as AppLanguage,
    );
    if (mounted) {
      await precacheBackendImages(
        context,
        data.topics.map((topic) => topic.iconUrl),
      );
    }
    return data;
  }

  Future<void> _chooseTopic(GameType gameType) async {
    if (_starting) return;

    _GamesData data;
    try {
      data = await _load();
      if (mounted) setState(() { _future = Future.value(data); });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      return;
    }

    if (data.topics.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('noGameTopics'))));
      }
      return;
    }

    final topic = await showModalBottomSheet<Topic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        decoration: const BoxDecoration(
          color: Color(0xFFF3FBFF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(color: AppColors.trackGrey, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 16),
              Text(context.tr('chooseIsland'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.deepBlue)),
              const SizedBox(height: 4),
              Text(context.tr('whichTopicPractice'), style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 430),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: data.topics.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final item = data.topics[index];
                    return MagicCard(
                      padding: const EdgeInsets.all(12),
                      border: Border.all(color: item.color.withValues(alpha: .25)),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(item),
                        borderRadius: BorderRadius.circular(20),
                        child: Row(
                          children: [
                            _TopicIcon(topic: item),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.deepBlue)),
                                  Text(context.tr('studiedWordsAvailableCount', {'count': item.learnedCount}), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.accentBlue),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (topic == null || !mounted) return;
    await _startGame(gameType, topic, data.language);
  }

  Future<void> _startGame(GameType gameType, Topic topic, AppLanguage language) async {
    setState(() => _starting = true);
    try {
      final lessonService = DailyLessonService(widget.appRepository);
      var plan = await lessonService.loadPlan(topic: topic, language: language);

      if (!plan.isComplete && plan.requiredCount > 0) {
        if (!mounted) return;
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => DailyWordsLessonScreen(
              topic: topic,
              language: language,
              repository: widget.appRepository,
            ),
          ),
        );
        if (!mounted) return;
        plan = await lessonService.loadPlan(topic: topic, language: language);
        if (!plan.isComplete) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr('studyNewWords', {'studied': plan.studiedCount, 'required': plan.requiredCount}),
              ),
            ),
          );
          return;
        }
      }

      final session = await widget.gameRepository.startGame(
        GameStartRequest(
          topicId: int.parse(topic.id),
          language: language,
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
            topicTitle: topic.title,
          ),
        ),
      );
      if (mounted) setState(() { _future = _load(); });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FantasyBackground(
      child: SafeArea(
        child: FutureBuilder<_GamesData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const ZenviaLoadingScreen();
            }
            if (snapshot.hasError) {
              return Center(child: MagicPrimaryButton(label: context.tr('retry'), onPressed: () => setState(() { _future = _load(); })));
            }
            final data = snapshot.data!;
            return Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                  children: [
                    MagicCard(
                      padding: EdgeInsets.zero,
                      gradient: AppColors.magicGradient,
                      child: SizedBox(
                        height: 145,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: Image.asset('assets/images/dragon_wave.webp', fit: BoxFit.cover),
                              ),
                            ),
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  gradient: LinearGradient(colors: [AppColors.deepBlue.withValues(alpha: .86), Colors.transparent]),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 18,
                              top: 20,
                              width: 210,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(context.tr('gameMeadow'), style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 6),
                                  Text(
                                    context.tr('languagePracticeXp', {'language': '${data.language.flagEmoji} ${data.language.label}'}),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, height: 1.3),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    MagicSectionTitle(title: context.tr('chooseGame')),
                    const SizedBox(height: 10),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: .80,
                      ),
                      itemCount: GameType.values.length,
                      itemBuilder: (_, index) {
                        final type = GameType.values[index];
                        final colors = _colors[type]!;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _chooseTopic(type),
                            borderRadius: BorderRadius.circular(28),
                            child: Ink(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [BoxShadow(color: colors.last.withValues(alpha: .25), blurRadius: 16, offset: const Offset(0, 6))],
                              ),
                              padding: EdgeInsets.zero,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final cardHeight = constraints.maxHeight;
                                  return Stack(
                                    alignment: Alignment.topCenter,
                                    children: [
                                      Positioned(
                                        top: cardHeight * .14,
                                        left: 0,
                                        right: 0,
                                        child: Center(
                                          child: Container(
                                            width: 62,
                                            height: 62,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: .92),
                                              shape: BoxShape.circle,
                                            ),
                                            alignment: Alignment.center,
                                            child: Image.asset(
                                              type.assetPath,
                                              width: 40,
                                              height: 40,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: cardHeight * .55,
                                        left: 12,
                                        right: 12,
                                        height: 40,
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          child: Text(
                                            _gameTitle(context, type),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
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
                                        top: cardHeight * .74,
                                        left: 10,
                                        right: 10,
                                        height: 34,
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          child: Text(
                                            _description(context, type),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                              height: 1.2,
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
                      },
                    ),
                  ],
                ),
                if (_starting)
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
                              Text(context.tr('preparingGameEllipsis'), style: const TextStyle(fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _gameTitle(BuildContext context, GameType type) {
    switch (type) {
      case GameType.imageChoice:
        return context.tr('gameFindPicture');
      case GameType.wordChoice:
        return context.tr('gameChooseWord');
      case GameType.audioChoice:
        return context.tr('gameListen');
      case GameType.matching:
        return context.tr('gameFindPair');
    }
  }

  String _description(BuildContext context, GameType type) {
    switch (type) {
      case GameType.imageChoice:
        return context.tr('readWordFindPicture');
      case GameType.wordChoice:
        return context.tr('lookPictureChooseWord');
      case GameType.audioChoice:
        return context.tr('listenWordFindPicture');
      case GameType.matching:
        return context.tr('connectPicturesWords');
    }
  }
}

class _GamesData {
  final List<Topic> topics;
  final AppLanguage language;
  const _GamesData({required this.topics, required this.language});
}

class _TopicIcon extends StatelessWidget {
  final Topic topic;
  const _TopicIcon({required this.topic});
  @override
  Widget build(BuildContext context) {
    final url = topic.iconUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 52,
        height: 52,
        color: topic.color.withValues(alpha: .15),
        alignment: Alignment.center,
        child: url != null && url.isNotEmpty
            ? Image.network(url, fit: BoxFit.cover, width: 52, height: 52, errorBuilder: (_, __, ___) => Image.asset('assets/images/ui/picture.webp', width: 34, height: 34, fit: BoxFit.contain))
            : Image.asset('assets/images/ui/picture.webp', width: 34, height: 34, fit: BoxFit.contain),
      ),
    );
  }
}
