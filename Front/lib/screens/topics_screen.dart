import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../data/game_repository.dart';
import '../models/daily_lesson.dart';
import '../l10n/app_strings.dart';
import '../models/language.dart';
import '../models/topic.dart';
import '../theme/app_colors.dart';
import 'daily_words_lesson_screen.dart';
import 'topic_detail_screen.dart';
import '../services/daily_lesson_service.dart';
import '../widgets/magic_ui.dart';

class TopicsScreen extends StatefulWidget {
  final AppRepository repository;
  final GameRepository gameRepository;
  final VoidCallback? onBack;

  const TopicsScreen({
    super.key,
    required this.repository,
    required this.gameRepository,
    this.onBack,
  });

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  late Future<List<Topic>> _future;
  AppLanguage _language = AppLanguage.english;
  bool _openingTopic = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant TopicsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _reload();
    }
  }

  void _reload() {
    _future = _loadTopics();
    widget.repository.getSelectedLanguage().then((language) {
      if (!mounted) return;
      setState(() => _language = language);
    });
  }

  Future<List<Topic>> _loadTopics() async {
    final topics = await widget.repository.getTopics();
    if (mounted) {
      await precacheBackendImages(
        context,
        topics.map((topic) => topic.iconUrl),
      );
    }
    return topics;
  }

  bool _isTopicUnlocked(int index, List<Topic> topics) {
    if (index == 0) return true;

    // Если ребёнок уже начал эту тему, она не должна внезапно закрыться.
    if (topics[index].learnedCount > 0 || topics[index].isCompleted) {
      return true;
    }

    // Следующая тема открывается после полного прохождения предыдущей.
    return topics[index - 1].isCompleted;
  }

  Future<void> _openTopic(Topic topic) async {
    if (_openingTopic) return;
    _openingTopic = true;
    final lessonService = DailyLessonService(widget.repository);
    DailyLessonPlan plan;
    try {
      plan = await lessonService.loadPlan(
        topic: topic,
        language: _language,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      _openingTopic = false;
      return;
    }

    if (!mounted) {
      _openingTopic = false;
      return;
    }

    if (!plan.isComplete && plan.requiredCount > 0) {
      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DailyWordsLessonScreen(
            topic: topic,
            language: _language,
            repository: widget.repository,
          ),
        ),
      );

      if (!mounted || completed != true) {
        _openingTopic = false;
        return;
      }
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TopicDetailScreen(
          topic: topic,
          language: _language,
          appRepository: widget.repository,
          gameRepository: widget.gameRepository,
        ),
      ),
    );

    _openingTopic = false;
    if (!mounted) return;
    setState(_reload);
  }

  void _showLockedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('previousTopicFirst')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Topic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: ZenviaLoadingScreen());
        }

        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: const Color(0xFF35BDF3),
            body: _ErrorState(
              onRetry: () => setState(_reload),
            ),
          );
        }

        final topics = snapshot.data ?? const <Topic>[];
        return Scaffold(
          backgroundColor: const Color(0xFF35BDF3),
          body: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/world_map_sky.webp',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF008BCB).withValues(alpha: .12),
                        Colors.transparent,
                        Colors.white.withValues(alpha: .08),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _MapHeader(
                      onBack: widget.onBack,
                      onRefresh: () => setState(_reload),
                    ),
                    Expanded(
                      child: topics.isEmpty
                          ? Center(
                              child: _GlassMessage(
                                icon: Icons.cloud_outlined,
                                text: context.tr('noTopics'),
                              ),
                            )
                          : _WorldMap(
                              topics: topics,
                              isUnlocked: (index) => _isTopicUnlocked(index, topics),
                              onTopicTap: _openTopic,
                              onLockedTap: _showLockedMessage,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}

class _MapHeader extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback onRefresh;

  const _MapHeader({
    required this.onBack,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF005C91).withValues(alpha: .96),
              const Color(0xFF067CAC).withValues(alpha: .94),
            ],
          ),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: Colors.white.withValues(alpha: .18)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF003B67).withValues(alpha: .22),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onBack,
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Text(
                context.tr('worldMap'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .2,
                  shadows: [
                    Shadow(color: Colors.black26, blurRadius: 8),
                  ],
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onRefresh,
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorldMap extends StatelessWidget {
  final List<Topic> topics;
  final bool Function(int index) isUnlocked;
  final ValueChanged<Topic> onTopicTap;
  final VoidCallback onLockedTap;

  const _WorldMap({
    required this.topics,
    required this.isUnlocked,
    required this.onTopicTap,
    required this.onLockedTap,
  });

  static const double _rowHeight = 260;
  static const double _islandWidth = 238;
  static const double _islandHeight = 242;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final contentHeight = 42 + (topics.length * _rowHeight) + 120;

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.only(bottom: 118),
          child: SizedBox(
            width: width,
            height: contentHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _AdventurePathPainter(
                      count: topics.length,
                      rowHeight: _rowHeight,
                    ),
                  ),
                ),
                for (var i = 0; i < topics.length; i++)
                  Positioned(
                    top: 18 + (i * _rowHeight),
                    left: i.isEven ? 8 : null,
                    right: i.isEven ? null : 8,
                    width: math.min(_islandWidth, width * .64),
                    height: _islandHeight,
                    child: _IslandNode(
                      topic: topics[i],
                      number: i + 1,
                      unlocked: isUnlocked(i),
                      onTap: isUnlocked(i)
                          ? () => onTopicTap(topics[i])
                          : onLockedTap,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IslandNode extends StatefulWidget {
  final Topic topic;
  final int number;
  final bool unlocked;
  final VoidCallback onTap;

  const _IslandNode({
    required this.topic,
    required this.number,
    required this.unlocked,
    required this.onTap,
  });

  @override
  State<_IslandNode> createState() => _IslandNodeState();
}

class _IslandNodeState extends State<_IslandNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatController;

  double get _floatAmplitude {
    switch (widget.number % 3) {
      case 0:
        return 4.5;
      case 1:
        return 5.5;
      default:
        return 6.0;
    }
  }

  double get _floatPhase => widget.number * 1.65;

  Duration get _floatDuration => Duration(
        milliseconds: 3700 + ((widget.number % 4) * 280),
      );

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: _floatDuration,
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _IslandNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.number != widget.number) {
      _floatController.duration = _floatDuration;
      if (!_floatController.isAnimating) {
        _floatController.repeat();
      }
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final completed = widget.topic.isCompleted;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedBuilder(
      animation: _floatController,
      builder: (context, child) {
        final offsetY = reduceMotion
            ? 0.0
            : math.sin(
                  _floatController.value * math.pi * 2 + _floatPhase,
                ) *
                _floatAmplitude;

        return Transform.translate(
          offset: Offset(0, offsetY),
          child: child,
        );
      },
      child: Semantics(
        button: true,
        enabled: widget.unlocked,
        label: widget.unlocked
            ? context.tr('topicNumber', {'number': widget.number, 'title': widget.topic.title})
            : context.tr('lockedTopicNumber', {'number': widget.number, 'title': widget.topic.title}),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 188,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: widget.unlocked ? 1 : .96,
                  child: _TopicIslandImage(
                    topic: widget.topic,
                    unlocked: widget.unlocked,
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 8,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 76),
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  decoration: BoxDecoration(
                    color: widget.unlocked
                        ? Colors.white.withValues(alpha: .97)
                        : const Color(0xFF536B83).withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: widget.unlocked
                          ? Colors.white
                          : Colors.white.withValues(alpha: .22),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .14),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.unlocked ? widget.topic.title : context.tr('soon'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: widget.unlocked
                              ? AppColors.deepBlue
                              : Colors.white,
                          fontSize: 18,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (widget.unlocked && widget.topic.totalCount > 0) ...[
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: widget.topic.progress,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFE5EEF6),
                            valueColor: AlwaysStoppedAnimation(
                              completed ? AppColors.gold : AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 69,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: widget.unlocked
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: completed
                                ? const [Color(0xFFFFE16D), Color(0xFFFFB82F)]
                                : const [Color(0xFF8BF2C0), Color(0xFF3ED78F)],
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF7A91A8), Color(0xFF50677F)],
                          ),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .16),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: widget.unlocked
                      ? Text(
                          '${widget.number}',
                          style: const TextStyle(
                            color: AppColors.deepBlue,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : const Icon(
                          Icons.lock_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
              ),
              if (completed)
                const Positioned(
                  top: 18,
                  right: 22,
                  child: _CompletedStar(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicIslandImage extends StatelessWidget {
  final Topic topic;
  final bool unlocked;

  const _TopicIslandImage({
    required this.topic,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    if (!unlocked) {
      return Image.asset(
        'assets/images/world_island_locked.webp',
        fit: BoxFit.contain,
      );
    }

    final url = topic.iconUrl?.trim();
    if (url == null || url.isEmpty) {
      return _MissingIslandIcon(topicTitle: topic.title);
    }

    return Image.network(
      url,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
          child: SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.white,
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => _MissingIslandIcon(topicTitle: topic.title),
    );
  }
}

class _MissingIslandIcon extends StatelessWidget {
  final String topicTitle;

  const _MissingIslandIcon({required this.topicTitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 156,
        height: 138,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .90),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .10),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.landscape_rounded,
              color: AppColors.primary,
              size: 50,
            ),
            const SizedBox(height: 8),
            Text(
              topicTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.deepBlue,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedStar extends StatelessWidget {
  const _CompletedStar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .12),
            blurRadius: 8,
          ),
        ],
      ),
      child: const Icon(
        Icons.star_rounded,
        color: AppColors.goldDark,
        size: 25,
      ),
    );
  }
}

class _AdventurePathPainter extends CustomPainter {
  final int count;
  final double rowHeight;

  const _AdventurePathPainter({
    required this.count,
    required this.rowHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (count < 2) return;

    final points = <Offset>[];
    for (var i = 0; i < count; i++) {
      points.add(
        Offset(
          i.isEven ? size.width * .30 : size.width * .70,
          132 + (i * rowHeight),
        ),
      );
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);

    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final middleY = (current.dy + next.dy) / 2;
      path.cubicTo(
        current.dx,
        middleY,
        next.dx,
        middleY,
        next.dx,
        next.dy,
      );
    }

    final glowPaint = Paint()
      ..color = const Color(0xFFFFD548).withValues(alpha: .32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, glowPaint);

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      var distance = 0.0;
      const dash = 7.0;
      const gap = 10.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), dotPaint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AdventurePathPainter oldDelegate) {
    return oldDelegate.count != count || oldDelegate.rowHeight != rowHeight;
  }
}

class _GlassMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  const _GlassMessage({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .90),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: AppColors.deepBlue),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.deepBlue,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 46,
              color: AppColors.deepBlue,
            ),
            const SizedBox(height: 10),
            Text(
              context.tr('worldMapLoadFailed'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.deepBlue,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.tr('retry')),
            ),
          ],
        ),
      ),
    );
  }
}
