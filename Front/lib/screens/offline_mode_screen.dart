import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

class OfflineModeScreen extends StatefulWidget {
  final VoidCallback onPlay;
  final Future<void> Function() onRetry;

  const OfflineModeScreen({
    super.key,
    required this.onPlay,
    required this.onRetry,
  });

  @override
  State<OfflineModeScreen> createState() => _OfflineModeScreenState();
}

class _OfflineModeScreenState extends State<OfflineModeScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Image(
            image: AssetImage('assets/images/subscription_blocked_bg.webp'),
            fit: BoxFit.cover,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0A63B4).withValues(alpha: .08),
                  Colors.transparent,
                  const Color(0xFF0E355E).withValues(alpha: .10),
                ],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final h = constraints.maxHeight;
                final dragonHeight = math.min(
                  270.0,
                  math.max(185.0, h * .30),
                );

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: SizedBox.expand(
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: math.max(42.0, h * .075),
                              child: _OfflineCard(
                                retrying: _retrying,
                                onPlay: widget.onPlay,
                                onRetry: _retrying ? null : _retry,
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: math.max(30.0, h * .045),
                              child: IgnorePointer(
                                child: Center(
                                  child: Image.asset(
                                    'assets/images/subscription_blocked_sleep_dragon.webp',
                                    height: dragonHeight,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineCard extends StatelessWidget {
  final bool retrying;
  final VoidCallback onPlay;
  final VoidCallback? onRetry;

  const _OfflineCard({
    required this.retrying,
    required this.onPlay,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: Color(0xFF3E8ED0),
            size: 38,
          ),
          const SizedBox(height: 10),
          Text(
            context.tr('offlineModeTitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF174E93),
              fontSize: 27,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('offlineModeMessage'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF536783),
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Material(
            color: const Color(0xFF49A8FF),
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              onTap: onPlay,
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.sports_esports_rounded,
                      color: Colors.white,
                      size: 25,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        context.tr('offlinePlayButton'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: retrying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(
              retrying
                  ? context.tr('checking')
                  : context.tr('offlineCheckConnection'),
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF36BF70),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            context.tr('offlineLearningNotice'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF738298),
              fontSize: 12.5,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
