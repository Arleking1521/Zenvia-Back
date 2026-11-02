import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/achievement.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../widgets/achievement_card.dart';
import '../widgets/magic_ui.dart';

class AchievementsScreen extends StatefulWidget {
  final AppRepository repository;
  const AchievementsScreen({super.key, required this.repository});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late Future<List<Achievement>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadAchievements();
  }

  Future<List<Achievement>> _loadAchievements() async {
    final items = await widget.repository.getAchievements();
    if (mounted) {
      await precacheBackendImages(
        context,
        items.map((item) => item.iconUrl),
      );
    }
    return items;
  }

  @override
  void didUpdateWidget(covariant AchievementsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _future = _loadAchievements();
    }
  }

  void _reload() => setState(() {
        _future = _loadAchievements();
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Achievement>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: ZenviaLoadingScreen());
        }

        final items = snapshot.data ?? const <Achievement>[];
        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
                  child: Transform.scale(
                    scale: 1.02,
                    child: Image.asset(
                      'assets/images/achievements_screen_bg.webp',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: .02),
                        Colors.white.withValues(alpha: .05),
                        const Color(0xFFF3F6FF).withValues(alpha: .15),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          _topCircleButton(
                            icon: Icons.arrow_back_rounded,
                            onTap: () => Navigator.of(context).pop(),
                          ),
                          const Spacer(),
                          Text(
                            context.tr('achievements'),
                            style: TextStyle(
                              fontSize: 31,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: .22),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(width: 42, height: 42),
                        ],
                      ),
                    ),
                    Expanded(
                      child: snapshot.hasError
                          ? Center(
                              child: MagicPrimaryButton(
                                label: context.tr('retry'),
                                onPressed: _reload,
                              ),
                            )
                          : items.isEmpty
                              ? Center(
                                  child: Text(
                                    context.tr('noAchievements'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  color: AppColors.goldDark,
                                  onRefresh: () async {
                                    _reload();
                                    await _future;
                                  },
                                  child: ListView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 26),
                                    children: [
                                      _SummaryCloud(achievements: items),
                                      const SizedBox(height: 16),
                                      for (final item in items) ...[
                                        AchievementCard(achievement: item),
                                        const SizedBox(height: 14),
                                      ],
                                    ],
                                  ),
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

  Widget _topCircleButton({required IconData icon, required VoidCallback? onTap}) {
    return Material(
      color: Colors.white.withValues(alpha: .18),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}

class _SummaryCloud extends StatelessWidget {
  final List<Achievement> achievements;

  const _SummaryCloud({required this.achievements});

  @override
  Widget build(BuildContext context) {
    final completed = achievements.where((a) => a.isCompleted).length;
    final total = achievements.length;
    final progress = total == 0 ? 0.0 : completed / total;

    return SizedBox(
      height: 148,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/achievement_cloud_card.webp',
              fit: BoxFit.fill,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 40, 30, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  context.tr('achievementsCount', {'completed': completed, 'total': total}),
                  style: const TextStyle(
                    color: AppColors.deepBlue,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 26,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9DAF4).withValues(alpha: .95),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .9),
                      width: 2,
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth * progress;
                      return Stack(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOut,
                            width: width.clamp(0, constraints.maxWidth).toDouble(),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFFFFD85B), Color(0xFFF6A500)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFC232).withValues(alpha: .35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                          if (width > 24)
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Wrap(
                                    spacing: 10,
                                    children: List.generate(
                                      ((constraints.maxWidth / 48).floor().clamp(3, 8)).toInt(),
                                      (index) => Container(
                                        width: 4,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: .75),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
