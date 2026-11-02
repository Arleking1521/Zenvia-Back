import 'package:flutter/material.dart';

import '../models/achievement.dart';
import '../theme/app_colors.dart';

class AchievementCard extends StatelessWidget {
  final Achievement achievement;
  const AchievementCard({super.key, required this.achievement});

  static const _grayscaleMatrix = <double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ];

  bool get _isLocked => !achievement.isCompleted && achievement.current <= 0;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      height: 132,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(34),
              child: Image.asset(
                'assets/images/achievement_cloud_card.webp',
                fit: BoxFit.fill,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: _isLocked
                      ? [
                          const Color(0xFFEEF2FF).withValues(alpha: .88),
                          const Color(0xFFDCE3FF).withValues(alpha: .92),
                        ]
                      : [
                          Colors.white.withValues(alpha: .10),
                          Colors.white.withValues(alpha: .03),
                        ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(
              children: [
                _AchievementIllustration(
                  achievement: achievement,
                  locked: _isLocked,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        achievement.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _isLocked
                              ? const Color(0xFF53658F)
                              : AppColors.deepBlue,
                          fontSize: 16.5,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        achievement.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.7,
                          height: 1.18,
                          color: _isLocked
                              ? const Color(0xFF6D7A98)
                              : const Color(0xFF4D5C82),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _AchievementStatusBadge(
                  achievement: achievement,
                  locked: _isLocked,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (_isLocked) {
      return Opacity(
        opacity: .94,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(_grayscaleMatrix),
          child: content,
        ),
      );
    }
    return content;
  }
}

class _AchievementIllustration extends StatelessWidget {
  final Achievement achievement;
  final bool locked;

  const _AchievementIllustration({
    required this.achievement,
    required this.locked,
  });

  @override
  Widget build(BuildContext context) {
    final picture = ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: achievement.iconUrl != null && achievement.iconUrl!.isNotEmpty
          ? Image.network(
              achievement.iconUrl!,
              width: 112,
              height: 92,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );

    return SizedBox(
      width: 112,
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: picture),
          if (locked)
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: const Color(0xFF7F8FB7).withValues(alpha: .82),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: .72), width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.lock_rounded,
                size: 32,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: 112,
      height: 92,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: achievement.iconBg.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Image.asset(
        'assets/images/reward_star_clean.webp',
        width: 58,
        height: 58,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _AchievementStatusBadge extends StatelessWidget {
  final Achievement achievement;
  final bool locked;

  const _AchievementStatusBadge({
    required this.achievement,
    required this.locked,
  });

  @override
  Widget build(BuildContext context) {
    if (achievement.isCompleted) {
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF92EB73), Color(0xFF40C755)],
          ),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF58D267).withValues(alpha: .38),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 34),
      );
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 72),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: locked
            ? const Color(0xFFDDE2F7).withValues(alpha: .92)
            : const Color(0xFFE7E6FF).withValues(alpha: .96),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: .9), width: 2),
      ),
      child: Text(
        '${achievement.current}/${achievement.target}',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: locked ? const Color(0xFF6677A8) : const Color(0xFF5364BF),
          fontWeight: FontWeight.w900,
          fontSize: 18,
          height: 1,
        ),
      ),
    );
  }
}
