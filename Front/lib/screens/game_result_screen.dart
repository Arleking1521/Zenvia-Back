import 'package:flutter/material.dart';

import '../models/game.dart';
import '../l10n/app_strings.dart';
import '../services/background_music_service.dart';
import '../theme/app_colors.dart';
import '../widgets/magic_ui.dart';

class GameResultScreen extends StatelessWidget {
  final GameFinishResult result;
  final String topicTitle;

  const GameResultScreen({
    super.key,
    required this.result,
    required this.topicTitle,
  });

  @override
  Widget build(BuildContext context) {
    final session = result.session;
    final totalAnswers = session.correctCount + session.wrongCount;
    final accuracy = totalAnswers == 0
        ? 0
        : ((session.correctCount / totalAnswers) * 100).round();

    return BackgroundMusicSilence(
      child: Scaffold(
        body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/reward_star_clean.webp',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x16000000),
                  Color(0x00000000),
                  Color(0x22042F54),
                  Color(0x70042F54),
                ],
                stops: [0, .36, .70, 1],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 40,
                    ),
                    child: Column(
                      children: [
                        Text(
                          context.tr('greatWork'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.deepBlue,
                            fontSize: 34,
                            height: 1.02,
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(
                                color: Colors.white,
                                blurRadius: 16,
                              ),
                              Shadow(
                                color: Colors.white70,
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.tr('dragonStronger'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.deepBlue.withValues(alpha: .96),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            shadows: const [
                              Shadow(color: Colors.white, blurRadius: 10),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          topicTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(color: Color(0xAA083C70), blurRadius: 8),
                            ],
                          ),
                        ),

                        // Оставляем центральную часть изображения свободной,
                        // чтобы дракончик оставался главным визуальным акцентом.
                        SizedBox(height: constraints.maxHeight * .43),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .92),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .95),
                              width: 1.5,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x29083C70),
                                blurRadius: 24,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _ResultMetric(
                                    asset: 'assets/images/ui/success.webp',
                                    value: '${session.correctCount}',
                                    label: context.tr('correct'),
                                  ),
                                  _ResultMetric(
                                    asset: 'assets/images/ui/gamepad.webp',
                                    value: '$accuracy%',
                                    label: context.tr('accuracy'),
                                  ),
                                  _ResultMetric(
                                    asset: 'assets/images/reward_star_clean.webp',
                                    value: '+${session.xpEarned}',
                                    label: 'XP',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Container(
                                height: 1,
                                color: AppColors.deepBlue.withValues(alpha: .10),
                              ),
                              const SizedBox(height: 13),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    context.tr('totalXp'),
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '${result.totalXp}',
                                    style: const TextStyle(
                                      color: AppColors.deepBlue,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 22,
                                    ),
                                  ),
                                ],
                              ),
                              if (result.dailyXpLimit > 0) ...[
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      context.tr('xpToday'),
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      '${result.dailyXp}/${result.dailyXpLimit}',
                                      style: const TextStyle(
                                        color: AppColors.deepBlue,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: result.dailyProgress,
                                    minHeight: 10,
                                    backgroundColor: AppColors.deepBlue.withValues(alpha: .10),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      result.dailyLimitReached
                                          ? const Color(0xFFFFB52E)
                                          : const Color(0xFF28C76F),
                                    ),
                                  ),
                                ),
                                if (result.xpRequested > result.xpGranted) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3D9),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      result.dailyLimitReached
                                          ? context.tr('dailyXpDone')
                                          : context.tr('xpRewardReduced', {'requested': result.xpRequested, 'granted': result.xpGranted}),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFF8C5A00),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                ] else if (result.dailyLimitReached) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    context.tr('dailyGoalDoneStar'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFF8C5A00),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: MagicPrimaryButton(
                            label: context.tr('home'),
                            icon: Icons.home_rounded,
                            onPressed: () => Navigator.of(context).pop(true),
                          ),
                        ),
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
    );
  }
}

class _ResultMetric extends StatelessWidget {
  final String asset;
  final String value;
  final String label;

  const _ResultMetric({
    required this.asset,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Image.asset(asset, width: 30, height: 30, fit: BoxFit.contain),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.deepBlue,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
