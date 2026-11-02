import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';

class TopicCard extends StatelessWidget {
  final Topic topic;
  final VoidCallback onTap;
  final bool compact;

  const TopicCard({
    super.key,
    required this.topic,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleSize = compact ? 15.0 : 18.0;
    final subtitleSize = compact ? 11.0 : 12.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                topic.color.withValues(alpha: .92),
                topic.color.withValues(alpha: .72),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: topic.color.withValues(alpha: .24),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .26),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          topic.isCompleted ? context.tr('completed') : context.tr('wordsCount', {'learned': topic.learnedCount, 'total': topic.totalCount}),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .92),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        topic.isCompleted ? Icons.star_rounded : Icons.arrow_forward_rounded,
                        color: topic.isCompleted ? AppColors.goldDark : AppColors.deepBlue,
                        size: topic.isCompleted ? 20 : 18,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 16),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: compact ? 86 : 96,
                    height: compact ? 86 : 96,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .92),
                      shape: BoxShape.circle,
                    ),
                    child: _TopicIcon(topic: topic),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  topic.number > 0 ? '${topic.number}. ${topic.title}' : topic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: titleSize,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  topic.description.isNotEmpty ? topic.description : context.tr('learnNewWithDragon'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .92),
                    fontSize: subtitleSize,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: topic.progress,
                          minHeight: 9,
                          backgroundColor: Colors.white.withValues(alpha: .35),
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              topic.isCompleted ? context.tr('excellentWork') : context.tr('learningProgress'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .96),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(topic.progress * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicIcon extends StatelessWidget {
  final Topic topic;
  const _TopicIcon({required this.topic});

  @override
  Widget build(BuildContext context) {
    final url = topic.iconUrl;
    if (url == null || url.isEmpty) {
      return FittedBox(child: Image.asset('assets/images/ui/picture.webp', width: 48, height: 48, fit: BoxFit.contain));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => FittedBox(child: Image.asset('assets/images/ui/picture.webp', width: 48, height: 48, fit: BoxFit.contain)),
      ),
    );
  }
}
