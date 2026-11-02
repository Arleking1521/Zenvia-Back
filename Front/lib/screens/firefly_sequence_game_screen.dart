import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/magic_ui.dart';

class FireflySequenceGameScreen extends StatefulWidget {
  const FireflySequenceGameScreen({super.key});

  @override
  State<FireflySequenceGameScreen> createState() =>
      _FireflySequenceGameScreenState();
}

class _FireflySequenceGameScreenState
    extends State<FireflySequenceGameScreen> {
  static const int _maxRounds = 6;
  static const String _fireflyAsset = 'assets/images/games/firefly/firefly.webp';

  final math.Random _random = math.Random();

  _FireflyDifficulty? _difficulty;
  final List<int> _sequence = <int>[];

  int _round = 1;
  int _playerStep = 0;
  int? _activeFirefly;
  int? _pressedFirefly;
  bool _showingSequence = false;
  bool _waitingForPlayer = false;
  bool _started = false;
  String _message = 'Запомни, как загораются светлячки';
  int _sessionToken = 0;

  int get _fireflyCount => _difficulty?.fireflyCount ?? 0;

  void _selectDifficulty(_FireflyDifficulty difficulty) {
    setState(() {
      _difficulty = difficulty;
      _resetGameState();
    });
  }

  void _resetGameState() {
    _sessionToken += 1;

    _sequence
      ..clear()
      ..addAll(
        List<int>.generate(
          3,
          (_) => _random.nextInt(_fireflyCount),
        ),
      );

    _round = 1;
    _playerStep = 0;
    _activeFirefly = null;
    _pressedFirefly = null;
    _showingSequence = false;
    _waitingForPlayer = false;
    _started = false;
    _message = 'Запомни, как загораются светлячки';
  }

  void _restartGame() {
    if (_difficulty == null) return;
    setState(_resetGameState);
  }

  void _showDifficultySelection() {
    setState(() {
      _sessionToken += 1;
      _difficulty = null;
      _sequence.clear();
      _round = 1;
      _playerStep = 0;
      _activeFirefly = null;
      _pressedFirefly = null;
      _showingSequence = false;
      _waitingForPlayer = false;
      _started = false;
      _message = 'Запомни, как загораются светлячки';
    });
  }

  Future<void> _startGame() async {
    if (_showingSequence || _difficulty == null) return;

    setState(() {
      _started = true;
    });

    await _playSequence();
  }

  Future<void> _playSequence() async {
    if (!mounted || _difficulty == null) return;

    final token = ++_sessionToken;

    setState(() {
      _showingSequence = true;
      _waitingForPlayer = false;
      _playerStep = 0;
      _pressedFirefly = null;
      _message = 'Смотри внимательно...';
    });

    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted || token != _sessionToken) return;

    for (final fireflyIndex in _sequence) {
      setState(() {
        _activeFirefly = fireflyIndex;
      });

      await Future<void>.delayed(const Duration(milliseconds: 560));
      if (!mounted || token != _sessionToken) return;

      setState(() {
        _activeFirefly = null;
      });

      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted || token != _sessionToken) return;
    }

    setState(() {
      _showingSequence = false;
      _waitingForPlayer = true;
      _message = 'Теперь повтори!';
    });
  }

  Future<void> _onFireflyTap(int index) async {
    if (!_waitingForPlayer || _showingSequence || _difficulty == null) {
      return;
    }

    final token = _sessionToken;

    setState(() {
      _pressedFirefly = index;
    });

    await Future<void>.delayed(const Duration(milliseconds: 190));
    if (!mounted || token != _sessionToken) return;

    setState(() {
      _pressedFirefly = null;
    });

    if (index != _sequence[_playerStep]) {
      setState(() {
        _waitingForPlayer = false;
        _playerStep = 0;
        _message = 'Почти! Посмотри ещё раз';
      });

      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (!mounted || token != _sessionToken) return;

      await _playSequence();
      return;
    }

    _playerStep += 1;

    if (_playerStep < _sequence.length) {
      setState(() {
        _message = 'Отлично, продолжай!';
      });
      return;
    }

    setState(() {
      _waitingForPlayer = false;
      _message = 'Правильно!';
    });

    if (_round >= _maxRounds) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted || token != _sessionToken) return;

      await _showFinishedDialog();
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 850));
    if (!mounted || token != _sessionToken) return;

    setState(() {
      _round += 1;
      _sequence.add(_random.nextInt(_fireflyCount));
      _playerStep = 0;
      _message = 'Раунд $_round';
    });

    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted || token != _sessionToken) return;

    await _playSequence();
  }

  Future<void> _showFinishedDialog() async {
    final difficulty = _difficulty;
    if (difficulty == null) return;

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
                _fireflyAsset,
                width: 92,
                height: 92,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 6),
              const Text(
                'Ты повторил всё!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF124C89),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${difficulty.title} • ${difficulty.fireflyCount} светлячков',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF5C6F88),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _restartGame();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5AAE63),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text(
                    'Сыграть ещё',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _showDifficultySelection();
                  },
                  child: const Text(
                    'Выбрать сложность',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'В пещеру',
                    style: TextStyle(
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
    final difficulty = _difficulty;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Image(
            image: AssetImage('assets/images/adventure_bg.webp'),
            fit: BoxFit.cover,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB8123455),
                  Color(0x99112D4A),
                  Color(0xC9082440),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
              child: Column(
                children: [
                  _TopBar(
                    hasDifficulty: difficulty != null,
                    onBack: () => Navigator.of(context).pop(),
                    onChangeDifficulty: _showDifficultySelection,
                    onRestart: _restartGame,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: difficulty == null
                        ? _DifficultyPicker(
                            onSelected: _selectDifficulty,
                          )
                        : _buildGame(difficulty),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGame(_FireflyDifficulty difficulty) {
    final sequenceLength = _sequence.length;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .90),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Раунд $_round/$_maxRounds',
                      style: const TextStyle(
                        color: Color(0xFF274B73),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '$sequenceLength ${_signalWord(sequenceLength)}',
                    style: const TextStyle(
                      color: Color(0xFF5C6F88),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    difficulty.title,
                    style: TextStyle(
                      color: difficulty.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${difficulty.fireflyCount} светлячков',
                    style: const TextStyle(
                      color: Color(0xFF6D7E92),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: Center(
                  child: Text(
                    _message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF174F86),
                      fontSize: 17,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boardSize = math.min(
                constraints.maxWidth,
                constraints.maxHeight,
              );

              final fireflySize = _fireflySizeFor(
                boardSize,
                difficulty.fireflyCount,
              );

              final alignments =
                  _alignmentsFor(difficulty.fireflyCount);

              return Center(
                child: SizedBox(
                  width: boardSize,
                  height: boardSize,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF082B43)
                                .withValues(alpha: .34),
                            borderRadius: BorderRadius.circular(42),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .13),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      ...List<Widget>.generate(
                        difficulty.fireflyCount,
                        (index) {
                          final glowing = _activeFirefly == index ||
                              _pressedFirefly == index;

                          return Align(
                            alignment: alignments[index],
                            child: _FireflyButton(
                              assetPath: _fireflyAsset,
                              size: fireflySize,
                              glowing: glowing,
                              enabled: _waitingForPlayer,
                              onTap: () => _onFireflyTap(index),
                            ),
                          );
                        },
                      ),
                      if (!_started)
                        Center(
                          child: FilledButton.icon(
                            onPressed: _startGame,
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF5AAE63),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(24),
                              ),
                            ),
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 28,
                            ),
                            label: const Text(
                              'Начать',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _showingSequence
              ? 'Сейчас только смотри'
              : _waitingForPlayer
                  ? 'Нажимай на светлячков по порядку'
                  : 'Готов? Светлячки покажут последовательность',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .92),
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
    );
  }

  double _fireflySizeFor(double boardSize, int count) {
    switch (count) {
      case 4:
        return (boardSize * .27).clamp(82.0, 122.0).toDouble();
      case 6:
        return (boardSize * .225).clamp(68.0, 108.0).toDouble();
      case 8:
        return (boardSize * .19).clamp(58.0, 92.0).toDouble();
      case 10:
        return (boardSize * .165).clamp(50.0, 80.0).toDouble();
      default:
        return (boardSize * .20).clamp(58.0, 96.0).toDouble();
    }
  }

  List<Alignment> _alignmentsFor(int count) {
    switch (count) {
      case 4:
        return const [
          Alignment(-.55, -.50),
          Alignment(.55, -.50),
          Alignment(-.55, .50),
          Alignment(.55, .50),
        ];
      case 6:
        return const [
          Alignment(-.62, -.58),
          Alignment(.02, -.76),
          Alignment(.64, -.48),
          Alignment(-.66, .32),
          Alignment(.02, .62),
          Alignment(.66, .26),
        ];
      case 8:
        return const [
          Alignment(-.62, -.67),
          Alignment(.00, -.79),
          Alignment(.62, -.67),
          Alignment(-.76, -.08),
          Alignment(.76, -.08),
          Alignment(-.60, .61),
          Alignment(.00, .78),
          Alignment(.60, .61),
        ];
      case 10:
        return const [
          Alignment(-.68, -.73),
          Alignment(.00, -.82),
          Alignment(.68, -.73),
          Alignment(-.80, -.27),
          Alignment(.80, -.27),
          Alignment(-.80, .28),
          Alignment(.80, .28),
          Alignment(-.62, .70),
          Alignment(.00, .82),
          Alignment(.62, .70),
        ];
      default:
        return const [];
    }
  }

  String _signalWord(int count) {
    if (count == 3 || count == 4) return 'сигнала';
    return 'сигналов';
  }
}

class _TopBar extends StatelessWidget {
  final bool hasDifficulty;
  final VoidCallback onBack;
  final VoidCallback onChangeDifficulty;
  final VoidCallback onRestart;

  const _TopBar({
    required this.hasDifficulty,
    required this.onBack,
    required this.onChangeDifficulty,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CircleHeaderButton(
          tooltip: 'Назад',
          icon: Icons.arrow_back_rounded,
          onPressed: onBack,
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Повтори за светлячками',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
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
        if (hasDifficulty) ...[
          _CircleHeaderButton(
            tooltip: 'Выбрать сложность',
            icon: Icons.grid_view_rounded,
            onPressed: onChangeDifficulty,
          ),
          const SizedBox(width: 8),
          _CircleHeaderButton(
            tooltip: 'Начать заново',
            icon: Icons.refresh_rounded,
            onPressed: onRestart,
          ),
        ],
      ],
    );
  }
}

class _DifficultyPicker extends StatelessWidget {
  final ValueChanged<_FireflyDifficulty> onSelected;

  const _DifficultyPicker({
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .92),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Column(
            children: [
              Text(
                'Выбери сложность',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF174F86),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Чем больше светлячков, тем сложнее запомнить порядок',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF5C6F88),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
            physics: const BouncingScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: .92,
            ),
            itemCount: _FireflyDifficulty.values.length,
            itemBuilder: (context, index) {
              final difficulty = _FireflyDifficulty.values[index];

              return _DifficultyTile(
                difficulty: difficulty,
                onTap: () => onSelected(difficulty),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DifficultyTile extends StatefulWidget {
  final _FireflyDifficulty difficulty;
  final VoidCallback onTap;

  const _DifficultyTile({
    required this.difficulty,
    required this.onTap,
  });

  @override
  State<_DifficultyTile> createState() => _DifficultyTileState();
}

class _DifficultyTileState extends State<_DifficultyTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final difficulty = widget.difficulty;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 110),
        scale: _pressed ? .96 : 1,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .95),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: difficulty.accent.withValues(alpha: .55),
              width: 3,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x25000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: _FireflyDifficultyPreview(
                  difficulty: difficulty,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  difficulty.title,
                  maxLines: 1,
                  style: TextStyle(
                    color: difficulty.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${difficulty.fireflyCount} светлячков',
                style: const TextStyle(
                  color: Color(0xFF5C6F88),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FireflyDifficultyPreview extends StatelessWidget {
  final _FireflyDifficulty difficulty;

  const _FireflyDifficultyPreview({
    required this.difficulty,
  });

  @override
  Widget build(BuildContext context) {
    final count = difficulty.fireflyCount;
    final size = count <= 4
        ? 34.0
        : count <= 6
            ? 29.0
            : count <= 8
                ? 25.0
                : 22.0;

    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        spacing: 3,
        runSpacing: 3,
        children: List<Widget>.generate(
          count,
          (index) => SizedBox(
            width: size,
            height: size,
            child: Image.asset(
              'assets/images/games/firefly/firefly.webp',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

class _FireflyButton extends StatelessWidget {
  final String assetPath;
  final double size;
  final bool glowing;
  final bool enabled;
  final VoidCallback onTap;

  const _FireflyButton({
    required this.assetPath,
    required this.size,
    required this.glowing,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Светлячок',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          scale: glowing ? 1.12 : 1,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: glowing ? size * 1.08 : size * .72,
                  height: glowing ? size * 1.08 : size * .72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: glowing
                        ? const Color(0x55FFF68A)
                        : const Color(0x16D8FF9B),
                    boxShadow: glowing
                        ? const [
                            BoxShadow(
                              color: Color(0xCCFFF36A),
                              blurRadius: 32,
                              spreadRadius: 10,
                            ),
                          ]
                        : const [
                            BoxShadow(
                              color: Color(0x55B8F072),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: enabled ? 1 : .95,
                  child: Image.asset(
                    assetPath,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
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

class _CircleHeaderButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _CircleHeaderButton({
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
        onPressed: () => DebouncedTapGuard.run('firefly-header:$tooltip', onPressed),
        icon: Icon(
          icon,
          color: Colors.white,
        ),
      ),
    );
  }
}

enum _FireflyDifficulty {
  easy(
    title: 'Лёгкий',
    fireflyCount: 4,
    accent: Color(0xFF4EAE66),
  ),
  medium(
    title: 'Средний',
    fireflyCount: 6,
    accent: Color(0xFF2E8ED5),
  ),
  hard(
    title: 'Сложный',
    fireflyCount: 8,
    accent: Color(0xFFE48B34),
  ),
  superHard(
    title: 'Суперсложный',
    fireflyCount: 10,
    accent: Color(0xFF9B58C8),
  );

  final String title;
  final int fireflyCount;
  final Color accent;

  const _FireflyDifficulty({
    required this.title,
    required this.fireflyCount,
    required this.accent,
  });
}
