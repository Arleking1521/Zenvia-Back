import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/magic_ui.dart';

import '../l10n/app_strings.dart';

class MemoryMatchGameScreen extends StatefulWidget {
  const MemoryMatchGameScreen({super.key});

  @override
  State<MemoryMatchGameScreen> createState() => _MemoryMatchGameScreenState();
}

class _MemoryMatchGameScreenState extends State<MemoryMatchGameScreen> {
  static const String _memoryAssetsPrefix =
      'assets/images/games/find_pair/';

  static const Set<String> _supportedImageExtensions = <String>{
    '.png',
    '.webp',
    '.jpg',
    '.jpeg',
  };

  static const List<Color> _cardBackgrounds = <Color>[
    Color(0xFFFFE8A3),
    Color(0xFFBFE7FF),
    Color(0xFFFFD2EA),
    Color(0xFFCFF2B4),
    Color(0xFFE1C9FF),
    Color(0xFFFFC6A9),
    Color(0xFFFFD19B),
    Color(0xFFD9E0EA),
    Color(0xFFC8D7FF),
    Color(0xFFC9EDC6),
  ];

  final math.Random _random = math.Random();

  List<String> _memoryAssets = <String>[];
  bool _loadingMemoryAssets = true;
  String? _memoryAssetsError;

  _MemoryDifficulty? _difficulty;
  List<_MemoryCardData> _cards = <_MemoryCardData>[];
  int? _firstIndex;
  bool _inputLocked = false;
  int _matchedPairs = 0;
  int _roundToken = 0;

  int get _pairCount => _difficulty?.pairCount ?? 0;

  @override
  void initState() {
    super.initState();
    _loadMemoryAssets();
  }

  Future<void> _loadMemoryAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest
          .listAssets()
          .where((asset) => asset.startsWith(_memoryAssetsPrefix))
          .where((asset) {
            final lower = asset.toLowerCase();
            return _supportedImageExtensions.any(lower.endsWith);
          })
          .toList()
        ..sort();

      if (!mounted) return;
      setState(() {
        _memoryAssets = assets;
        _loadingMemoryAssets = false;
        _memoryAssetsError = assets.isEmpty
            ? 'Добавьте картинки в assets/images/games/find_pair/.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMemoryAssets = false;
        _memoryAssetsError = 'Не удалось загрузить картинки игры.';
      });
    }
  }

  void _selectDifficulty(_MemoryDifficulty difficulty) {
    if (_memoryAssets.length < difficulty.pairCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Для уровня ${difficulty.fieldLabel} нужно минимум '
            '${difficulty.pairCount} разных картинок. Сейчас: ${_memoryAssets.length}.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _difficulty = difficulty;
      _createRound();
    });
  }

  void _createRound() {
    final difficulty = _difficulty;
    if (difficulty == null) return;

    _roundToken += 1;

    final assets = List<String>.from(_memoryAssets)..shuffle(_random);
    final selectedAssets = assets.take(difficulty.pairCount).toList();
    final backgrounds = List<Color>.from(_cardBackgrounds)..shuffle(_random);
    final selected = <_MemorySymbol>[
      for (var index = 0; index < selectedAssets.length; index++)
        _MemorySymbol(
          selectedAssets[index],
          backgrounds[index % backgrounds.length],
        ),
    ];

    final cards = <_MemoryCardData>[];
    var id = 0;

    for (var pairId = 0; pairId < selected.length; pairId++) {
      final symbol = selected[pairId];
      cards
        ..add(
          _MemoryCardData(
            id: id++,
            pairId: pairId,
            symbol: symbol,
          ),
        )
        ..add(
          _MemoryCardData(
            id: id++,
            pairId: pairId,
            symbol: symbol,
          ),
        );
    }

    cards.shuffle(_random);

    _cards = cards;
    _firstIndex = null;
    _inputLocked = false;
    _matchedPairs = 0;
  }

  void _restartRound() {
    if (_difficulty == null) return;
    setState(_createRound);
  }

  void _showDifficultySelection() {
    setState(() {
      _roundToken += 1;
      _difficulty = null;
      _cards = <_MemoryCardData>[];
      _firstIndex = null;
      _inputLocked = false;
      _matchedPairs = 0;
    });
  }

  Future<void> _onCardTap(int index) async {
    if (_inputLocked || _difficulty == null) return;

    final card = _cards[index];
    if (card.isMatched || card.isFaceUp) return;

    final roundToken = _roundToken;

    setState(() {
      card.isFaceUp = true;
    });

    if (_firstIndex == null) {
      _firstIndex = index;
      return;
    }

    final firstIndex = _firstIndex!;
    final firstCard = _cards[firstIndex];
    _firstIndex = null;
    _inputLocked = true;

    if (firstCard.pairId == card.pairId) {
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted || roundToken != _roundToken) return;

      setState(() {
        firstCard.isMatched = true;
        card.isMatched = true;
        _matchedPairs += 1;
        _inputLocked = false;
      });

      if (_matchedPairs == _pairCount) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (!mounted || roundToken != _roundToken) return;
        await _showFinishedDialog();
      }
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 850));
    if (!mounted || roundToken != _roundToken) return;

    setState(() {
      firstCard.isFaceUp = false;
      card.isFaceUp = false;
      _inputLocked = false;
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
                'assets/images/ui/celebration.webp',
                width: 78,
                height: 78,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('allPairsFound'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF124C89),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${context.tr(difficulty.titleKey)} • ${difficulty.fieldLabel}',
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
                    _restartRound();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2F9BFF),
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
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _showDifficultySelection();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2169A8),
                    side: const BorderSide(
                      color: Color(0xFFB8D9F5),
                      width: 2,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    context.tr('chooseLevel'),
                    style: const TextStyle(
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
    if (_loadingMemoryAssets) {
      return const Scaffold(body: ZenviaLoadingScreen());
    }

    if (_memoryAssetsError != null) {
      return Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Image(
              image: AssetImage('assets/images/adventure_bg.webp'),
              fit: BoxFit.cover,
            ),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .94),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.image_not_supported_rounded,
                          size: 48,
                          color: Color(0xFF2169A8),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _memoryAssetsError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF274B73),
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            setState(() {
                              _loadingMemoryAssets = true;
                              _memoryAssetsError = null;
                            });
                            _loadMemoryAssets();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

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
                  const Color(0xFF0474C5).withValues(alpha: .08),
                  Colors.transparent,
                  const Color(0xFF083869).withValues(alpha: .16),
                ],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                  child: Column(
                    children: [
                      _TopBar(
                        hasActiveGame: difficulty != null,
                        onBack: () => Navigator.of(context).pop(),
                        onChangeDifficulty: _showDifficultySelection,
                        onRestart: _inputLocked ? null : _restartRound,
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGame(_MemoryDifficulty difficulty) {
    final progress = _pairCount == 0 ? 0.0 : _matchedPairs / _pairCount;
    final spacing = difficulty.columns >= 4
        ? 8.0
        : difficulty.columns == 3
            ? 10.0
            : 14.0;

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
                      '${context.tr(difficulty.titleKey)} • ${difficulty.fieldLabel}',
                      style: const TextStyle(
                        color: Color(0xFF274B73),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    context.tr('pairsProgress', {'matched': _matchedPairs, 'total': _pairCount}),
                    style: const TextStyle(
                      color: Color(0xFF274B73),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: progress,
                  backgroundColor: const Color(0xFFDCEBFA),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF58BE70),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                context.tr('memoryInstruction'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF4F6280),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                physics: const BouncingScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: difficulty.columns,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                  childAspectRatio: difficulty.columns == 3 ? 1.05 : 1.0,
                ),
                itemCount: _cards.length,
                itemBuilder: (context, index) {
                  final card = _cards[index];
                  return _FlipMemoryCard(
                    key: ValueKey('${_roundToken}_${card.id}'),
                    isFaceUp: card.isFaceUp || card.isMatched,
                    isMatched: card.isMatched,
                    symbol: card.symbol,
                    compact: difficulty.columns >= 4,
                    onTap: () => _onCardTap(index),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool hasActiveGame;
  final VoidCallback onBack;
  final VoidCallback onChangeDifficulty;
  final VoidCallback? onRestart;

  const _TopBar({
    required this.hasActiveGame,
    required this.onBack,
    required this.onChangeDifficulty,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundHeaderButton(
          tooltip: context.tr('back'),
          icon: Icons.arrow_back_rounded,
          onPressed: onBack,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            context.tr('findPair'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(
                  color: Color(0x55000000),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
        if (hasActiveGame) ...[
          _RoundHeaderButton(
            tooltip: context.tr('chooseLevel'),
            icon: Icons.grid_view_rounded,
            onPressed: onChangeDifficulty,
          ),
          const SizedBox(width: 8),
          _RoundHeaderButton(
            tooltip: context.tr('shuffle'),
            icon: Icons.refresh_rounded,
            onPressed: onRestart,
          ),
        ],
      ],
    );
  }
}

class _RoundHeaderButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _RoundHeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .24),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed == null ? null : () => DebouncedTapGuard.run('memory-header:$tooltip', onPressed!),
        icon: Icon(
          icon,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _DifficultyPicker extends StatelessWidget {
  final ValueChanged<_MemoryDifficulty> onSelected;

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
          child: Column(
            children: [
              Text(
                context.tr('chooseBoardSize'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF174F86),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                context.tr('biggerBoard'),
                textAlign: TextAlign.center,
                style: const TextStyle(
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: .93,
            ),
            itemCount: _MemoryDifficulty.values.length,
            itemBuilder: (context, index) {
              final difficulty = _MemoryDifficulty.values[index];
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
  final _MemoryDifficulty difficulty;
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
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
                child: Center(
                  child: _MiniFieldPreview(
                    difficulty: difficulty,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  context.tr(difficulty.titleKey),
                  maxLines: 1,
                  style: TextStyle(
                    color: difficulty.accent,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${difficulty.fieldLabel} • ${difficulty.pairCount} ${context.tr(difficulty.pairCount >= 2 && difficulty.pairCount <= 4 ? 'pairPlural2' : 'pairs')}',
                textAlign: TextAlign.center,
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

class _MiniFieldPreview extends StatelessWidget {
  final _MemoryDifficulty difficulty;

  const _MiniFieldPreview({
    required this.difficulty,
  });

  @override
  Widget build(BuildContext context) {
    final columns = difficulty.columns;
    final total = difficulty.cardCount;
    final gap = columns >= 4 ? 3.0 : 4.0;
    final side = columns >= 4
        ? 17.0
        : columns == 3
            ? 22.0
            : 30.0;

    return SizedBox(
      width: columns * side + (columns - 1) * gap,
      child: Wrap(
        spacing: gap,
        runSpacing: gap,
        children: List.generate(
          total,
          (index) => Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              color: index.isEven
                  ? difficulty.previewLight
                  : difficulty.previewDark,
              borderRadius: BorderRadius.circular(side * .25),
              border: Border.all(
                color: Colors.white,
                width: columns >= 4 ? 1.5 : 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlipMemoryCard extends StatefulWidget {
  final bool isFaceUp;
  final bool isMatched;
  final _MemorySymbol symbol;
  final bool compact;
  final VoidCallback onTap;

  const _FlipMemoryCard({
    super.key,
    required this.isFaceUp,
    required this.isMatched,
    required this.symbol,
    required this.compact,
    required this.onTap,
  });

  @override
  State<_FlipMemoryCard> createState() => _FlipMemoryCardState();
}

class _FlipMemoryCardState extends State<_FlipMemoryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: widget.isFaceUp ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant _FlipMemoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isFaceUp != widget.isFaceUp) {
      if (widget.isFaceUp) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        scale: widget.isMatched ? 1.025 : 1,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final value = _controller.value;
            final angle = value * math.pi;
            final showFront = value >= .5;

            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0015)
                ..rotateY(angle),
              child: showFront
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationY(math.pi),
                      child: _front(),
                    )
                  : _back(),
            );
          },
        ),
      ),
    );
  }

  Widget _front() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minSide = math.min(constraints.maxWidth, constraints.maxHeight);
        final radius = (minSide * .14).clamp(16.0, 26.0).toDouble();
        final imagePadding = (minSide * .075).clamp(6.0, 14.0).toDouble();
        final starSize = (minSide * .15).clamp(14.0, 26.0).toDouble();
        final starInset = (minSide * .045).clamp(4.0, 10.0).toDouble();

        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.symbol.background,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: widget.isMatched
                  ? const Color(0xFF58BE70)
                  : Colors.white,
              width: widget.isMatched ? 4 : 3,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2A000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(imagePadding),
                  child: Image.asset(
                    widget.symbol.asset,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              if (widget.isMatched)
                Positioned(
                  right: starInset,
                  top: starInset,
                  child: Image.asset(
                    'assets/images/correct_star.webp',
                    width: starSize,
                    height: starSize,
                    fit: BoxFit.contain,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _back() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minSide = math.min(constraints.maxWidth, constraints.maxHeight);
        final radius = (minSide * .14).clamp(16.0, 26.0).toDouble();
        final circleSize = (minSide * .36).clamp(38.0, 64.0).toDouble();
        final iconSize = (circleSize * .64).clamp(24.0, 42.0).toDouble();

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF68BDF8),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white,
              width: minSide < 110 ? 2.5 : 3,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2A000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: circleSize,
              height: circleSize,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .22),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.question_mark_rounded,
                size: iconSize,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

}

enum _MemoryDifficulty {
  easy(
    titleKey: 'easy',
    columns: 2,
    rows: 2,
    accent: Color(0xFF3FAE67),
    previewLight: Color(0xFFCFF2B4),
    previewDark: Color(0xFF8DD59B),
  ),
  medium(
    titleKey: 'medium',
    columns: 3,
    rows: 2,
    accent: Color(0xFF2586D8),
    previewLight: Color(0xFFBFE7FF),
    previewDark: Color(0xFF86C8F4),
  ),
  hard(
    titleKey: 'hard',
    columns: 3,
    rows: 4,
    accent: Color(0xFFE38932),
    previewLight: Color(0xFFFFD5A7),
    previewDark: Color(0xFFF1A75E),
  ),
  superHard(
    titleKey: 'superHard',
    columns: 4,
    rows: 4,
    accent: Color(0xFF9A58C7),
    previewLight: Color(0xFFE1C9FF),
    previewDark: Color(0xFFBE91E2),
  );

  final String titleKey;
  final int columns;
  final int rows;
  final Color accent;
  final Color previewLight;
  final Color previewDark;

  const _MemoryDifficulty({
    required this.titleKey,
    required this.columns,
    required this.rows,
    required this.accent,
    required this.previewLight,
    required this.previewDark,
  });

  int get cardCount => columns * rows;

  int get pairCount => cardCount ~/ 2;

  String get fieldLabel => '$columns × $rows';
}

class _MemoryCardData {
  final int id;
  final int pairId;
  final _MemorySymbol symbol;

  bool isFaceUp = false;
  bool isMatched = false;

  _MemoryCardData({
    required this.id,
    required this.pairId,
    required this.symbol,
  });
}

class _MemorySymbol {
  final String asset;
  final Color background;

  const _MemorySymbol(this.asset, this.background);
}
