import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/magic_ui.dart';

import '../l10n/app_strings.dart';

class CatchStarsGameScreen extends StatefulWidget {
  const CatchStarsGameScreen({super.key});

  @override
  State<CatchStarsGameScreen> createState() => _CatchStarsGameScreenState();
}

class _CatchStarsGameScreenState extends State<CatchStarsGameScreen> {
  static const int _gameSeconds = 30;
  static const String _starAsset = 'assets/images/games/catch_stars/star.webp';
  static const String _cloudAsset = 'assets/images/games/catch_stars/cloud.webp';
  static const String _eggAsset = 'assets/images/games/catch_stars/dragon_egg.webp';

  final math.Random _random = math.Random();

  Timer? _countdownTimer;
  Timer? _spawnTimer;
  Timer? _fallTimer;

  bool _started = false;
  bool _finished = false;
  int _secondsLeft = _gameSeconds;
  int _score = 0;
  int _nextId = 0;
  String _message = '';

  double _boardWidth = 0;
  double _boardHeight = 0;

  final List<_FallingObject> _objects = <_FallingObject>[];

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    _countdownTimer?.cancel();
    _spawnTimer?.cancel();
    _fallTimer?.cancel();
    _countdownTimer = null;
    _spawnTimer = null;
    _fallTimer = null;
  }

  void _resetGame() {
    _cancelTimers();

    setState(() {
      _started = false;
      _finished = false;
      _secondsLeft = _gameSeconds;
      _score = 0;
      _nextId = 0;
      _objects.clear();
      _message = context.tr('catchOnlyStars');
    });
  }

  void _startGame() {
    if (_started && !_finished) return;

    _cancelTimers();

    setState(() {
      _started = true;
      _finished = false;
      _secondsLeft = _gameSeconds;
      _score = 0;
      _nextId = 0;
      _objects.clear();
      _message = context.tr('catchStarsShort');
    });

    _spawnObject();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      if (_secondsLeft <= 1) {
        _finishGame();
        return;
      }

      setState(() {
        _secondsLeft -= 1;
      });
    });

    _spawnTimer = Timer.periodic(const Duration(milliseconds: 720), (_) {
      if (!mounted || !_started || _finished) return;
      _spawnObject();
    });

    _fallTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted || !_started || _finished) return;
      _updateObjects();
    });
  }

  void _spawnObject() {
    if (_boardWidth <= 0 || _boardHeight <= 0) return;

    final roll = _random.nextDouble();
    final type = roll < .62
        ? _CatchObjectType.star
        : roll < .82
            ? _CatchObjectType.cloud
            : _CatchObjectType.egg;

    final sizeFactor = type == _CatchObjectType.star
        ? (.17 + _random.nextDouble() * .03)
        : (.18 + _random.nextDouble() * .04);

    final baseSize = (_boardWidth * sizeFactor).clamp(54.0, 104.0);
    final x = _random.nextDouble() * math.max(1, _boardWidth - baseSize);
    final speed = _boardHeight * (0.0048 + _random.nextDouble() * 0.0017);
    final swayAmplitude = 5 + _random.nextDouble() * 8;
    final swaySpeed = 0.06 + _random.nextDouble() * 0.05;
    final rotation = (_random.nextDouble() - .5) * 0.22;

    setState(() {
      _objects.add(
        _FallingObject(
          id: _nextId++,
          type: type,
          x: x,
          y: -baseSize * (0.7 + _random.nextDouble() * 0.5),
          size: baseSize,
          speed: speed,
          swayAmplitude: swayAmplitude,
          swaySpeed: swaySpeed,
          phase: _random.nextDouble() * math.pi * 2,
          rotation: rotation,
        ),
      );
    });
  }

  void _updateObjects() {
    setState(() {
      for (final object in _objects) {
        object.y += object.speed;
        object.phase += object.swaySpeed;
      }

      _objects.removeWhere((object) => object.y > _boardHeight + object.size);
    });
  }

  void _onObjectTap(_FallingObject object) {
    if (!_started || _finished) return;

    setState(() {
      _objects.removeWhere((element) => element.id == object.id);

      switch (object.type) {
        case _CatchObjectType.star:
          _score += 1;
          _message = context.tr('caughtStar');
          break;
        case _CatchObjectType.cloud:
          _message = context.tr('thisCloud');
          break;
        case _CatchObjectType.egg:
          _message = context.tr('thisDragonEgg');
          break;
      }
    });
  }

  void _finishGame() {
    if (_finished) return;

    _cancelTimers();

    setState(() {
      _secondsLeft = 0;
      _started = false;
      _finished = true;
      _objects.clear();
      _message = context.tr('roundFinished');
    });

    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _showFinishedDialog();
    });
  }

  Future<void> _showFinishedDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                _starAsset,
                width: 88,
                height: 88,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 10),
              Text(
                context.tr('greatGameShort'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF124C89),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('caughtStarsScore', {'score': _score}),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF5C6F88),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _startGame();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF4A62A),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: Text(
                    context.tr('playAgain'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    context.tr('toCave'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Image(
            image: AssetImage('assets/images/adventure_bg.webp'),
            fit: BoxFit.cover,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF163774).withValues(alpha: .42),
                  const Color(0xFF173A73).withValues(alpha: .28),
                  const Color(0xFF10294F).withValues(alpha: .48),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      _CircleButton(
                        tooltip: context.tr('back'),
                        icon: Icons.arrow_back_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.tr('catchStars'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(
                                color: Color(0x88000000),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _CircleButton(
                        tooltip: context.tr('restart'),
                        icon: Icons.refresh_rounded,
                        onPressed: _resetGame,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoPanel(
                    secondsLeft: _secondsLeft,
                    score: _score,
                    message: _message.isEmpty ? context.tr('catchOnlyStars') : _message,
                    starAsset: _starAsset,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _boardWidth = constraints.maxWidth;
                        _boardHeight = constraints.maxHeight;

                        return Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF122E58).withValues(alpha: .38),
                            borderRadius: BorderRadius.circular(38),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .15),
                              width: 2,
                            ),
                          ),
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              ..._objects.map((object) {
                                final swayX = math.sin(object.phase) * object.swayAmplitude;

                                return Positioned(
                                  key: ValueKey(object.id),
                                  left: (object.x + swayX)
                                      .clamp(0.0, math.max(0.0, _boardWidth - object.size)),
                                  top: object.y,
                                  child: _FallingObjectWidget(
                                    object: object,
                                    onTap: () => _onObjectTap(object),
                                    starAsset: _starAsset,
                                    cloudAsset: _cloudAsset,
                                    eggAsset: _eggAsset,
                                  ),
                                );
                              }),
                              if (!_started && !_finished)
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Image.asset(
                                        _starAsset,
                                        width: 96,
                                        height: 96,
                                        fit: BoxFit.contain,
                                      ),
                                      const SizedBox(height: 10),
                                      Container(
                                        constraints: const BoxConstraints(maxWidth: 290),
                                        padding: const EdgeInsets.symmetric(horizontal: 18),
                                        child: Text(
                                          context.tr('catchStarsInstruction'),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                            height: 1.3,
                                            fontWeight: FontWeight.w900,
                                            shadows: [
                                              Shadow(
                                                color: Color(0x99000000),
                                                blurRadius: 5,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 22),
                                      FilledButton.icon(
                                        onPressed: _startGame,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(0xFFF4A62A),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 30,
                                            vertical: 15,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(24),
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 28,
                                        ),
                                        label: Text(
                                          context.tr('start'),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
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
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _started
                        ? context.tr('catchLegend')
                        : context.tr('readyCatchStars'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .94),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      shadows: const [
                        Shadow(
                          color: Color(0x99000000),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final int secondsLeft;
  final int score;
  final String message;
  final String starAsset;

  const _InfoPanel({
    required this.secondsLeft,
    required this.score,
    required this.message,
    required this.starAsset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .91),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.timer_rounded,
                      color: Color(0xFF2F79BA),
                      size: 21,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.tr('secondsLeft', {'seconds': secondsLeft}),
                      style: const TextStyle(
                        color: Color(0xFF274B73),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Image.asset(
                    starAsset,
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$score',
                    style: const TextStyle(
                      color: Color(0xFF274B73),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 40,
            child: Center(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF174F86),
                  fontSize: 16,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FallingObjectWidget extends StatelessWidget {
  final _FallingObject object;
  final VoidCallback onTap;
  final String starAsset;
  final String cloudAsset;
  final String eggAsset;

  const _FallingObjectWidget({
    required this.object,
    required this.onTap,
    required this.starAsset,
    required this.cloudAsset,
    required this.eggAsset,
  });

  @override
  Widget build(BuildContext context) {
    final asset = switch (object.type) {
      _CatchObjectType.star => starAsset,
      _CatchObjectType.cloud => cloudAsset,
      _CatchObjectType.egg => eggAsset,
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Transform.rotate(
        angle: object.rotation,
        child: SizedBox(
          width: object.size,
          height: object.size,
          child: Image.asset(
            asset,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _CircleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .20),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: () => DebouncedTapGuard.run('catch-header:$tooltip', onPressed),
        icon: Icon(
          icon,
          color: Colors.white,
        ),
      ),
    );
  }
}

enum _CatchObjectType {
  star,
  cloud,
  egg,
}

class _FallingObject {
  final int id;
  final _CatchObjectType type;
  final double x;
  double y;
  final double size;
  final double speed;
  final double swayAmplitude;
  final double swaySpeed;
  double phase;
  final double rotation;

  _FallingObject({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.swayAmplitude,
    required this.swaySpeed,
    required this.phase,
    required this.rotation,
  });
}
