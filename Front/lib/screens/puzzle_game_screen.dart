import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/magic_ui.dart';

class PuzzleGameScreen extends StatefulWidget {
  const PuzzleGameScreen({super.key});

  @override
  State<PuzzleGameScreen> createState() => _PuzzleGameScreenState();
}

class _PuzzleGameScreenState extends State<PuzzleGameScreen> {
  static const String _puzzleAssetsPrefix =
      'assets/images/games/puzzle/';

  static const Set<String> _supportedImageExtensions = <String>{
    '.png',
    '.webp',
    '.jpg',
    '.jpeg',
  };

  final math.Random _random = math.Random();

  _PuzzleDifficulty? _difficulty;
  List<String> _puzzleImages = <String>[];
  String? _imageAsset;
  bool _loadingPuzzleImages = true;
  String? _puzzleImagesError;
  List<int> _pieces = <int>[];
  int? _draggingSlot;

  @override
  void initState() {
    super.initState();
    _loadPuzzleImages();
  }

  Future<void> _loadPuzzleImages() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest
          .listAssets()
          .where((asset) => asset.startsWith(_puzzleAssetsPrefix))
          .where((asset) {
            final lower = asset.toLowerCase();
            return _supportedImageExtensions.any(lower.endsWith);
          })
          .toList()
        ..sort();

      if (!mounted) return;

      setState(() {
        _puzzleImages = assets;
        _imageAsset = assets.isEmpty ? null : assets.first;
        _loadingPuzzleImages = false;
        _puzzleImagesError = assets.isEmpty
            ? 'В папке пазлов пока нет изображений.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingPuzzleImages = false;
        _puzzleImagesError = 'Не удалось загрузить картинки пазлов.';
      });
    }
  }

  String _pickPuzzleImage() {
    if (_puzzleImages.isEmpty) {
      throw StateError('Puzzle image assets are not available.');
    }

    if (_puzzleImages.length == 1) {
      return _puzzleImages.first;
    }

    final previous = _imageAsset;
    var next = _puzzleImages[_random.nextInt(_puzzleImages.length)];
    while (next == previous) {
      next = _puzzleImages[_random.nextInt(_puzzleImages.length)];
    }
    return next;
  }

  void _selectDifficulty(_PuzzleDifficulty difficulty) {
    setState(() {
      _difficulty = difficulty;
      _startNewPuzzle();
    });
  }

  void _startNewPuzzle() {
    final difficulty = _difficulty;
    if (difficulty == null) return;

    _imageAsset = _pickPuzzleImage();
    _pieces = List<int>.generate(difficulty.pieceCount, (index) => index);

    do {
      _pieces.shuffle(_random);
    } while (_isSolved());

    _draggingSlot = null;
  }

  void _restartPuzzle() {
    if (_difficulty == null) return;
    setState(_startNewPuzzle);
  }

  void _showDifficultySelection() {
    setState(() {
      _difficulty = null;
      _pieces = <int>[];
      _draggingSlot = null;
    });
  }

  bool _isSolved() {
    if (_pieces.isEmpty) return false;

    for (var index = 0; index < _pieces.length; index++) {
      if (_pieces[index] != index) return false;
    }
    return true;
  }

  void _swapPieces(int sourceSlot, int targetSlot) {
    if (sourceSlot == targetSlot) return;

    setState(() {
      final sourcePiece = _pieces[sourceSlot];
      _pieces[sourceSlot] = _pieces[targetSlot];
      _pieces[targetSlot] = sourcePiece;
      _draggingSlot = null;
    });

    if (_isSolved()) {
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        if (!mounted) return;
        _showFinishedDialog();
      });
    }
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
          contentPadding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: difficulty.columns / difficulty.rows,
                  child: Image.asset(
                    _imageAsset!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Пазл собран!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF124C89),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${difficulty.title} • ${difficulty.pieceCount} деталей',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF5C6F88),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _restartPuzzle();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8C63D7),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text(
                    'Новый пазл',
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
    if (_loadingPuzzleImages) {
      return const Scaffold(body: ZenviaLoadingScreen());
    }

    if (_puzzleImagesError != null || _puzzleImages.isEmpty) {
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
                  child: MagicCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.image_not_supported_rounded,
                          size: 52,
                          color: Color(0xFF8C63D7),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _puzzleImagesError ??
                              'В папке пазлов пока нет изображений.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF124C89),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _loadingPuzzleImages = true;
                              _puzzleImagesError = null;
                            });
                            _loadPuzzleImages();
                          },
                          child: const Text('Повторить'),
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
                  const Color(0xFF5A3B9B).withValues(alpha: .25),
                  const Color(0xFF143B68).withValues(alpha: .18),
                  const Color(0xFF10264E).withValues(alpha: .42),
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
                    hasPuzzle: difficulty != null,
                    onBack: () => Navigator.of(context).pop(),
                    onChangeDifficulty: _showDifficultySelection,
                    onRestart: _restartPuzzle,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: difficulty == null
                        ? _DifficultyPicker(onSelected: _selectDifficulty)
                        : _buildPuzzle(difficulty),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPuzzle(_PuzzleDifficulty difficulty) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .92),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 72,
                  height: 58,
                  child: Image.asset(
                    _imageAsset!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${difficulty.title} • ${difficulty.pieceCount} деталей',
                      style: const TextStyle(
                        color: Color(0xFF274B73),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Перетащи детали на нужные места',
                      style: TextStyle(
                        color: Color(0xFF61748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = math.min(constraints.maxWidth, 430.0);
                final maxHeight = constraints.maxHeight;
                final ratio = difficulty.columns / difficulty.rows;

                double boardWidth = maxWidth;
                double boardHeight = boardWidth / ratio;

                if (boardHeight > maxHeight) {
                  boardHeight = maxHeight;
                  boardWidth = boardHeight * ratio;
                }

                final tileWidth = boardWidth / difficulty.columns;
                final tileHeight = boardHeight / difficulty.rows;

                return SizedBox(
                  width: boardWidth,
                  height: boardHeight,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .82),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: GridView.builder(
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: difficulty.columns,
                        mainAxisSpacing: 3,
                        crossAxisSpacing: 3,
                        childAspectRatio: tileWidth / tileHeight,
                      ),
                      itemCount: _pieces.length,
                      itemBuilder: (context, slotIndex) {
                        final pieceIndex = _pieces[slotIndex];
                        final isDragging = _draggingSlot == slotIndex;

                        return DragTarget<int>(
                          onWillAcceptWithDetails: (details) =>
                              details.data != slotIndex,
                          onAcceptWithDetails: (details) =>
                              _swapPieces(details.data, slotIndex),
                          builder: (context, candidateData, rejectedData) {
                            final highlighted = candidateData.isNotEmpty;

                            final piece = _PuzzlePiece(
                              imageAsset: _imageAsset!,
                              pieceIndex: pieceIndex,
                              rows: difficulty.rows,
                              columns: difficulty.columns,
                              borderColor: highlighted
                                  ? const Color(0xFFFFC94B)
                                  : Colors.white.withValues(alpha: .72),
                            );

                            return Draggable<int>(
                              data: slotIndex,
                              onDragStarted: () {
                                setState(() => _draggingSlot = slotIndex);
                              },
                              onDragEnd: (_) {
                                if (!mounted) return;
                                setState(() => _draggingSlot = null);
                              },
                              feedback: Material(
                                color: Colors.transparent,
                                child: SizedBox(
                                  width: tileWidth - 3,
                                  height: tileHeight - 3,
                                  child: Transform.scale(
                                    scale: 1.06,
                                    child: piece,
                                  ),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: .22,
                                child: piece,
                              ),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 120),
                                opacity: isDragging ? .55 : 1,
                                child: piece,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Зажми деталь и перетащи её на другую',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .94),
            fontSize: 14,
            fontWeight: FontWeight.w800,
            shadows: const [
              Shadow(color: Color(0x99000000), blurRadius: 4),
            ],
          ),
        ),
      ],
    );
  }
}

class _PuzzlePiece extends StatelessWidget {
  final String imageAsset;
  final int pieceIndex;
  final int rows;
  final int columns;
  final Color borderColor;

  const _PuzzlePiece({
    required this.imageAsset,
    required this.pieceIndex,
    required this.rows,
    required this.columns,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final row = pieceIndex ~/ columns;
    final column = pieceIndex % columns;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth;
        final tileHeight = constraints.maxHeight;
        final fullWidth = tileWidth * columns;
        final fullHeight = tileHeight * rows;

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 2),
            ),
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: fullWidth,
                maxWidth: fullWidth,
                minHeight: fullHeight,
                maxHeight: fullHeight,
                child: Transform.translate(
                  offset: Offset(
                    -column * tileWidth,
                    -row * tileHeight,
                  ),
                  child: SizedBox(
                    width: fullWidth,
                    height: fullHeight,
                    child: Image.asset(
                      imageAsset,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool hasPuzzle;
  final VoidCallback onBack;
  final VoidCallback onChangeDifficulty;
  final VoidCallback onRestart;

  const _TopBar({
    required this.hasPuzzle,
    required this.onBack,
    required this.onChangeDifficulty,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CircleButton(
          tooltip: 'Назад',
          icon: Icons.arrow_back_rounded,
          onPressed: onBack,
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Собери пазл',
            style: TextStyle(
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
        if (hasPuzzle) ...[
          _CircleButton(
            tooltip: 'Выбрать сложность',
            icon: Icons.grid_view_rounded,
            onPressed: onChangeDifficulty,
          ),
          const SizedBox(width: 8),
          _CircleButton(
            tooltip: 'Новый пазл',
            icon: Icons.refresh_rounded,
            onPressed: onRestart,
          ),
        ],
      ],
    );
  }
}

class _DifficultyPicker extends StatelessWidget {
  final ValueChanged<_PuzzleDifficulty> onSelected;

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
                'Чем больше деталей, тем интереснее пазл',
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: .91,
            ),
            itemCount: _PuzzleDifficulty.values.length,
            itemBuilder: (context, index) {
              final difficulty = _PuzzleDifficulty.values[index];
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
  final _PuzzleDifficulty difficulty;
  final VoidCallback onTap;

  const _DifficultyTile({
    required this.difficulty,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .95),
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: difficulty.accent.withValues(alpha: .55),
              width: 3,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: _MiniPuzzleGrid(difficulty: difficulty),
                ),
              ),
              const SizedBox(height: 7),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  difficulty.title,
                  style: TextStyle(
                    color: difficulty.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${difficulty.pieceCount} деталей',
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

class _MiniPuzzleGrid extends StatelessWidget {
  final _PuzzleDifficulty difficulty;

  const _MiniPuzzleGrid({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    const gap = 3.0;
    final cell = difficulty.columns >= 4 ? 20.0 : 27.0;
    final width = difficulty.columns * cell + (difficulty.columns - 1) * gap;

    return SizedBox(
      width: width,
      child: Wrap(
        spacing: gap,
        runSpacing: gap,
        children: List<Widget>.generate(
          difficulty.pieceCount,
          (index) => Container(
            width: cell,
            height: cell,
            decoration: BoxDecoration(
              color: index.isEven
                  ? difficulty.accent.withValues(alpha: .72)
                  : difficulty.accent.withValues(alpha: .40),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
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
        onPressed: () => DebouncedTapGuard.run('puzzle-header:$tooltip', onPressed),
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

enum _PuzzleDifficulty {
  easy(
    title: 'Лёгкий',
    rows: 2,
    columns: 2,
    accent: Color(0xFF4EAE66),
  ),
  medium(
    title: 'Средний',
    rows: 3,
    columns: 3,
    accent: Color(0xFF2E8ED5),
  ),
  hard(
    title: 'Сложный',
    rows: 3,
    columns: 4,
    accent: Color(0xFFE48B34),
  ),
  veryHard(
    title: 'Очень сложный',
    rows: 4,
    columns: 4,
    accent: Color(0xFF9B58C8),
  );

  final String title;
  final int rows;
  final int columns;
  final Color accent;

  const _PuzzleDifficulty({
    required this.title,
    required this.rows,
    required this.columns,
    required this.accent,
  });

  int get pieceCount => rows * columns;
}
