import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/subscription.dart';
import '../l10n/app_strings.dart';

class SubscriptionBlockedScreen extends StatefulWidget {
  final SubscriptionAccessStatus access;
  final VoidCallback onPlay;
  final Future<void> Function() onParent;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSettings;

  const SubscriptionBlockedScreen({
    super.key,
    required this.access,
    required this.onPlay,
    required this.onParent,
    required this.onRetry,
    required this.onSettings,
  });

  @override
  State<SubscriptionBlockedScreen> createState() =>
      _SubscriptionBlockedScreenState();
}

class _SubscriptionBlockedScreenState extends State<SubscriptionBlockedScreen> {
  bool _retrying = false;
  bool _openingParent = false;
  bool _openingSettings = false;

  String _title(BuildContext context) {
    switch (widget.access.reason) {
      case 'expired':
        return context.tr('subscriptionPausedTitle');
      case 'pending':
        return context.tr('almostReady');
      case 'connection_error':
        return context.tr('accessCheckFailed');
      case 'cancelled':
        return context.tr('adventureResting');
      default:
        return context.tr('newAdventures');
    }
  }

  String _message(BuildContext context) {
    switch (widget.access.reason) {
      case 'expired':
        return context.tr('subscriptionExpiredMessage');
      case 'pending':
        return context.tr('subscriptionPendingMessage');
      case 'connection_error':
        return context.tr('connectionErrorMessage');
      case 'cancelled':
        return context.tr('subscriptionCancelledMessage');
      default:
        return context.tr('subscriptionNeededMessage');
    }
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _parent() async {
    if (_openingParent) return;
    setState(() => _openingParent = true);
    try {
      await widget.onParent();
    } finally {
      if (mounted) setState(() => _openingParent = false);
    }
  }

  Future<void> _settings() async {
    if (_openingSettings) return;
    setState(() => _openingSettings = true);
    try {
      await widget.onSettings();
    } finally {
      if (mounted) setState(() => _openingSettings = false);
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
                  const Color(0xFF0A63B4).withValues(alpha: .10),
                  Colors.transparent,
                  const Color(0xFF0E355E).withValues(alpha: .08),
                ],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final screenHeight = constraints.maxHeight;
                final dragonHeight = math.min(
                  275.0,
                  math.max(190.0, screenHeight * 0.30),
                );
                final cardTop = math.min(
                  78.0,
                  math.max(44.0, screenHeight * 0.085),
                );
                final dragonBottom = math.min(
                  68.0,
                  math.max(42.0, screenHeight * 0.065),
                );

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: SizedBox.expand(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: cardTop,
                              child: _buildPauseCard(context),
                            ),
                            Positioned(
                              top: 8,
                              right: 0,
                              child: _SettingsButton(
                                loading: _openingSettings,
                                tooltip: context.tr('settings'),
                                onTap: _openingSettings ? null : _settings,
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: dragonBottom,
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

  Widget _buildPauseCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .93),
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
        children: [
          Text(
            _title(context),
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
            _message(context),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF536783),
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 22),
          _ActionButton(
            icon: Icons.sports_esports_rounded,
            label: context.tr('freePlay'),
            color: const Color(0xFF49A8FF),
            onTap: widget.onPlay,
          ),
          const SizedBox(height: 12),
          _ActionButton(
            icon: Icons.lock_rounded,
            label: _openingParent
                ? context.tr('opening')
                : context.tr('callAdult'),
            color: const Color(0xFF36BF70),
            onTap: _openingParent ? null : _parent,
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _retrying ? null : _retry,
            icon: _retrying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(
              _retrying ? context.tr('checking') : context.tr('checkAgain'),
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF36BF70),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _SettingsButton extends StatelessWidget {
  final bool loading;
  final String tooltip;
  final VoidCallback? onTap;

  const _SettingsButton({
    required this.loading,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .92),
      shape: const CircleBorder(),
      elevation: 5,
      shadowColor: const Color(0x33000000),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF174E93),
                      ),
                    )
                  : const Icon(
                      Icons.settings_rounded,
                      color: Color(0xFF174E93),
                      size: 27,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });


  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 9),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
