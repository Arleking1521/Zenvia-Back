import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/magic_ui.dart';

class CountObjectsGameScreen extends StatefulWidget {
  const CountObjectsGameScreen({super.key});

  @override
  State<CountObjectsGameScreen> createState() =>
      _CountObjectsGameScreenState();
}

class _CountObjectsGameScreenState extends State<CountObjectsGameScreen> {
  static const int _maxRounds = 6;

  final math.Random _random = math.Random();

  _CountDifficulty? _difficulty;
  _PizzaTopping _topping = _PizzaTopping.pepperoni;
  int _answer = 1;
  List<int> _choices = const [];
  int _round = 1;
  int _pizzaSeed = 0;
  int _sessionToken = 0;
  bool _dropHover = false;
  bool _wrongDrop = false;
  bool _locked = false;
  String _message = 'Посчитай начинку на пицце';

  void _selectDifficulty(_CountDifficulty difficulty) {
    setState(() {
      _difficulty = difficulty;
      _round = 1;
      _sessionToken += 1;
      _createRound();
    });
  }

  void _showDifficultySelection() {
    setState(() {
      _sessionToken += 1;
      _difficulty = null;
      _round = 1;
      _locked = false;
      _dropHover = false;
      _wrongDrop = false;
      _message = 'Посчитай начинку на пицце';
    });
  }

  void _restartLevel() {
    if (_difficulty == null) return;

    setState(() {
      _sessionToken += 1;
      _round = 1;
      _locked = false;
      _createRound();
    });
  }

  void _createRound() {
    final difficulty = _difficulty;
    if (difficulty == null) return;

    _answer = difficulty.min +
        _random.nextInt(difficulty.max - difficulty.min + 1);
    _topping = _PizzaTopping.values[
        _random.nextInt(_PizzaTopping.values.length)];
    _pizzaSeed = _random.nextInt(10000);
    _choices = _buildChoices(_answer, difficulty);
    _dropHover = false;
    _wrongDrop = false;
    _locked = false;
    _message = 'Сколько ${_topping.questionWord}?';
  }

  List<int> _buildChoices(
    int correct,
    _CountDifficulty difficulty,
  ) {
    final values = <int>{correct};
    final available = <int>[
      for (var value = difficulty.min; value <= difficulty.max; value++)
        if (value != correct) value,
    ]..shuffle(_random);

    for (final value in available) {
      values.add(value);
      if (values.length == 3) break;
    }

    final result = values.toList()..shuffle(_random);
    return result;
  }

  Future<void> _handleDrop(int value) async {
    if (_locked) return;

    final token = _sessionToken;

    if (value != _answer) {
      setState(() {
        _dropHover = false;
        _wrongDrop = true;
        _message = 'Почти! Посчитай ещё раз';
      });

      await Future<void>.delayed(const Duration(milliseconds: 520));
      if (!mounted || token != _sessionToken) return;

      setState(() {
        _wrongDrop = false;
        _message = 'Сколько ${_topping.questionWord}?';
      });
      return;
    }

    setState(() {
      _locked = true;
      _dropHover = false;
      _wrongDrop = false;
      _message = 'Правильно!';
    });

    await Future<void>.delayed(const Duration(milliseconds: 720));
    if (!mounted || token != _sessionToken) return;

    if (_round >= _maxRounds) {
      await _showFinishedDialog();
      return;
    }

    setState(() {
      _round += 1;
      _createRound();
    });
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
                'assets/images/games/pizza/pizza_base.webp',
                width: 84,
                height: 84,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 6),
              const Text(
                'Все пиццы посчитаны!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF124C89),
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${difficulty.title} • числа ${difficulty.min}–${difficulty.max}',
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
                    _restartLevel();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE76F51),
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
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'В пещеру',
                  style: TextStyle(fontWeight: FontWeight.w800),
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
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF70411F).withValues(alpha: .18),
                  const Color(0xFF244A67).withValues(alpha: .20),
                  const Color(0xFF17324A).withValues(alpha: .38),
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
                    hasLevel: difficulty != null,
                    onBack: () => Navigator.of(context).pop(),
                    onChangeLevel: _showDifficultySelection,
                    onRestart: _restartLevel,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: difficulty == null
                        ? _DifficultyPicker(onSelected: _selectDifficulty)
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

  Widget _buildGame(_CountDifficulty difficulty) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .92),
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
                    '${difficulty.title} • ${difficulty.min}–${difficulty.max}',
                    style: TextStyle(
                      color: difficulty.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              SizedBox(
                height: 48,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      _message,
                      key: ValueKey(_message),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _wrongDrop
                            ? const Color(0xFFD14D49)
                            : const Color(0xFF174F86),
                        fontSize: 18,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
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
              final pizzaSize = math.min(
                constraints.maxWidth * .78,
                constraints.maxHeight * .67,
              ).clamp(180.0, 310.0).toDouble();

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DragTarget<int>(
                        onWillAccept: (value) {
                          if (_locked) return false;
                          setState(() => _dropHover = true);
                          return value != null;
                        },
                        onLeave: (_) {
                          if (mounted) {
                            setState(() => _dropHover = false);
                          }
                        },
                        onAcceptWithDetails: (details) {
                          _handleDrop(details.data);
                        },
                        builder: (context, candidateData, rejectedData) {
                          return AnimatedScale(
                            duration: const Duration(milliseconds: 150),
                            scale: _dropHover ? 1.045 : 1,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _dropHover
                                    ? Colors.white.withValues(alpha: .18)
                                    : Colors.transparent,
                                boxShadow: _dropHover
                                    ? const [
                                        BoxShadow(
                                          color: Color(0x66FFE08A),
                                          blurRadius: 28,
                                          spreadRadius: 6,
                                        ),
                                      ]
                                    : const [],
                              ),
                              child: SizedBox(
                                width: pizzaSize,
                                height: pizzaSize,
                                child: _PizzaBoard(
                                  count: _answer,
                                  topping: _topping,
                                  seed: _pizzaSeed,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Перетащи правильное число на пиццу',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .95),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          shadows: const [
                            Shadow(
                              color: Color(0x88000000),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 14,
                        runSpacing: 12,
                        children: _choices.map((value) {
                          return Draggable<int>(
                            data: value,
                            maxSimultaneousDrags: _locked ? 0 : 1,
                            feedback: Material(
                              color: Colors.transparent,
                              child: _NumberCard(
                                value: value,
                                lifted: true,
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: .28,
                              child: _NumberCard(value: value),
                            ),
                            child: _NumberCard(value: value),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool hasLevel;
  final VoidCallback onBack;
  final VoidCallback onChangeLevel;
  final VoidCallback onRestart;

  const _TopBar({
    required this.hasLevel,
    required this.onBack,
    required this.onChangeLevel,
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
            'Сколько предметов?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
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
        if (hasLevel) ...[
          _CircleHeaderButton(
            tooltip: 'Выбрать сложность',
            icon: Icons.grid_view_rounded,
            onPressed: onChangeLevel,
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
  final ValueChanged<_CountDifficulty> onSelected;

  const _DifficultyPicker({required this.onSelected});

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
                'Посчитай начинку и перетащи число на пиццу',
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
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
            itemCount: _CountDifficulty.values.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final difficulty = _CountDifficulty.values[index];
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

class _DifficultyTile extends StatelessWidget {
  final _CountDifficulty difficulty;
  final VoidCallback onTap;

  const _DifficultyTile({
    required this.difficulty,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
          child: Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: difficulty.accent.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${difficulty.min}–${difficulty.max}',
                    style: TextStyle(
                      color: difficulty.accent,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      difficulty.title,
                      style: TextStyle(
                        color: difficulty.accent,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      difficulty.description,
                      style: const TextStyle(
                        color: Color(0xFF5C6F88),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.play_circle_fill_rounded,
                color: difficulty.accent,
                size: 36,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberCard extends StatelessWidget {
  final int value;
  final bool lifted;

  const _NumberCard({
    required this.value,
    this.lifted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 68,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7EB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE76F51),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0x55000000),
            blurRadius: lifted ? 18 : 8,
            offset: Offset(0, lifted ? 9 : 4),
          ),
        ],
      ),
      child: Text(
        '$value',
        style: const TextStyle(
          color: Color(0xFFB94F39),
          fontSize: 30,
          fontWeight: FontWeight.w900,
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
        onPressed: () => DebouncedTapGuard.run('count-header:$tooltip', onPressed),
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _PizzaBoard extends StatelessWidget {
  final int count;
  final _PizzaTopping topping;
  final int seed;

  const _PizzaBoard({
    required this.count,
    required this.topping,
    required this.seed,
  });

  static const List<Offset> _positions = <Offset>[
    Offset(.50, .18), Offset(.31, .23), Offset(.69, .24), Offset(.20, .36),
    Offset(.43, .34), Offset(.61, .36), Offset(.80, .37), Offset(.29, .48),
    Offset(.52, .48), Offset(.72, .50), Offset(.18, .59), Offset(.40, .60),
    Offset(.61, .62), Offset(.81, .60), Offset(.28, .72), Offset(.49, .73),
    Offset(.70, .72), Offset(.39, .82), Offset(.61, .82), Offset(.50, .57),
  ];

  String get _toppingAsset => switch (topping) {
        _PizzaTopping.pepperoni => 'assets/images/games/pizza/pepperoni.webp',
        _PizzaTopping.mushroom => 'assets/images/games/pizza/mushroom.webp',
        _PizzaTopping.olive => 'assets/images/games/pizza/olive.webp',
      };

  @override
  Widget build(BuildContext context) {
    final start = seed % _positions.length;
    const step = 7;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        final toppingSize = count <= 5
            ? size * .145
            : count <= 10
                ? size * .112
                : size * .084;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/games/pizza/pizza_base.webp',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            for (var i = 0; i < count; i++)
              Positioned(
                left: size * _positions[(start + i * step) % _positions.length].dx - toppingSize / 2,
                top: size * _positions[(start + i * step) % _positions.length].dy - toppingSize / 2,
                width: toppingSize,
                height: toppingSize,
                child: Image.asset(
                  _toppingAsset,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
          ],
        );
      },
    );
  }
}

enum _PizzaTopping {
  pepperoni('кусочков пепперони'),
  mushroom('грибочков'),
  olive('оливок');

  final String questionWord;

  const _PizzaTopping(this.questionWord);
}

enum _CountDifficulty {
  easy(
    title: 'Легко',
    min: 1,
    max: 5,
    description: 'От 1 до 5 предметов',
    accent: Color(0xFF4EAE66),
  ),
  medium(
    title: 'Средний',
    min: 5,
    max: 10,
    description: 'От 5 до 10 предметов',
    accent: Color(0xFF2E8ED5),
  ),
  hard(
    title: 'Сложный',
    min: 10,
    max: 20,
    description: 'От 10 до 20 предметов',
    accent: Color(0xFFE76F51),
  );

  final String title;
  final int min;
  final int max;
  final String description;
  final Color accent;

  const _CountDifficulty({
    required this.title,
    required this.min,
    required this.max,
    required this.description,
    required this.accent,
  });
}
