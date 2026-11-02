import 'package:flutter/material.dart';

import '../widgets/magic_ui.dart';

import 'catch_stars_game_screen.dart';
import 'count_objects_game_screen.dart';
import 'connect_dots_game_screen.dart';
import 'firefly_sequence_game_screen.dart';
import 'memory_match_game_screen.dart';
import 'puzzle_game_screen.dart';

class PlayCaveScreen extends StatelessWidget {
  const PlayCaveScreen({super.key});

  static const String _fireflyAsset = 'assets/images/games/firefly/firefly.webp';
  static const String _starAsset = 'assets/images/games/catch_stars/star.webp';
  static const String _cloudAsset = 'assets/images/games/catch_stars/cloud.webp';
  static const String _eggAsset = 'assets/images/games/catch_stars/dragon_egg.webp';

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
                  const Color(0xFF063B7A).withValues(alpha: .10),
                  Colors.transparent,
                  const Color(0xFF052F63).withValues(alpha: .20),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      Material(
                        color: Colors.white.withValues(alpha: .24),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Назад',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Хочу играть',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(
                        color: Color(0x66000000),
                        blurRadius: 7,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Выбирай игру и просто веселись!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 390),
                        child: Column(
                          children: [
                            _GameTile(
                              title: 'Найди пару',
                              subtitle:
                                  'Переворачивай карточки и находи одинаковые картинки',
                              preview: const _MiniMemoryPreview(),
                              buttonColor: const Color(0xFF2F9BFF),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const MemoryMatchGameScreen(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            _GameTile(
                              title: 'Повтори за светлячками',
                              subtitle:
                                  'Запоминай, кто загорелся, и повторяй последовательность',
                              preview: const _MiniFireflyPreview(
                                assetPath: _fireflyAsset,
                              ),
                              buttonColor: const Color(0xFF5AAE63),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const FireflySequenceGameScreen(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            _GameTile(
                              title: 'Лови звёздочки',
                              subtitle:
                                  'Лови падающие звёздочки и не трогай облачка и яйца',
                              preview: const _MiniCatchStarsPreview(
                                starAsset: _starAsset,
                                cloudAsset: _cloudAsset,
                                eggAsset: _eggAsset,
                              ),
                              buttonColor: const Color(0xFFF4A62A),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const CatchStarsGameScreen(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            _GameTile(
                              title: 'Собери пазл',
                              subtitle:
                                  'Перетаскивай детали и собери целую картинку',
                              preview: const _MiniPuzzlePreview(),
                              buttonColor: const Color(0xFF8C63D7),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const PuzzleGameScreen(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            _GameTile(
                              title: 'Сколько предметов?',
                              subtitle:
                                  'Посчитай начинку и перетащи правильное число к пицце',
                              preview: const _MiniCountObjectsPreview(),
                              buttonColor: const Color(0xFFE76F51),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const CountObjectsGameScreen(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            _GameTile(
                              title: 'Соедини точки',
                              subtitle:
                                  'Нажимай точки по порядку и открой спрятанную картинку',
                              preview: const _MiniConnectDotsPreview(),
                              buttonColor: const Color(0xFF4E7DDE),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const ConnectDotsGameScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GameTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final Widget preview;
  final Color buttonColor;
  final VoidCallback onTap;

  const _GameTile({
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.buttonColor,
    required this.onTap,
  });

  @override
  State<_GameTile> createState() => _GameTileState();
}

class _GameTileState extends State<_GameTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        DebouncedTapGuard.run('play-cave-${widget.title}', widget.onTap);
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 110),
        scale: _pressed ? .97 : 1,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .94),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 18,
                offset: Offset(0, 9),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.preview,
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.title,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Color(0xFF104C91),
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF4F6280),
                  fontSize: 14,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: widget.buttonColor,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Text(
                  'Играть',
                  style: TextStyle(
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
    );
  }
}

class _MiniMemoryPreview extends StatelessWidget {
  const _MiniMemoryPreview();

  @override
  Widget build(BuildContext context) {
    Widget card(String value, Color color) {
      return Container(
        width: 72,
        height: 84,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 7,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.asset(value, fit: BoxFit.contain),
        ),
      );
    }

    return SizedBox(
      height: 102,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -.12,
            child: Transform.translate(
              offset: const Offset(-42, 4),
              child: card('assets/images/correct_star.webp', const Color(0xFFFFE9A8)),
            ),
          ),
          Transform.rotate(
            angle: .12,
            child: Transform.translate(
              offset: const Offset(42, 4),
              child: card('assets/images/correct_star.webp', const Color(0xFFFFE9A8)),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -8),
            child: Container(
              width: 58,
              height: 68,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF79C9FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(
                Icons.question_mark_rounded,
                size: 36,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniFireflyPreview extends StatelessWidget {
  final String assetPath;

  const _MiniFireflyPreview({required this.assetPath});

  @override
  Widget build(BuildContext context) {
    Widget fly(double size, Alignment alignment, bool glow) {
      return Align(
        alignment: alignment,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (glow)
                Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xAAFFF36A),
                        blurRadius: 22,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                ),
              Image.asset(assetPath, fit: BoxFit.contain),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 112,
      width: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF123B50),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          fly(42, const Alignment(-.92, -.65), false),
          fly(56, const Alignment(.02, -.82), true),
          fly(44, const Alignment(.92, -.50), false),
          fly(40, const Alignment(-.68, .78), false),
          fly(43, const Alignment(.70, .72), false),
        ],
      ),
    );
  }
}

class _MiniCatchStarsPreview extends StatelessWidget {
  final String starAsset;
  final String cloudAsset;
  final String eggAsset;

  const _MiniCatchStarsPreview({
    required this.starAsset,
    required this.cloudAsset,
    required this.eggAsset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 118,
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF203B74), Color(0xFF253668)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(-.55, -.35),
            child: Image.asset(
              starAsset,
              width: 48,
              height: 48,
              fit: BoxFit.contain,
            ),
          ),
          Align(
            alignment: const Alignment(.05, .38),
            child: Image.asset(
              starAsset,
              width: 58,
              height: 58,
              fit: BoxFit.contain,
            ),
          ),
          Align(
            alignment: const Alignment(.72, -.35),
            child: Image.asset(
              cloudAsset,
              width: 44,
              height: 44,
              fit: BoxFit.contain,
            ),
          ),
          Align(
            alignment: const Alignment(.73, .62),
            child: Image.asset(
              eggAsset,
              width: 35,
              height: 35,
              fit: BoxFit.contain,
            ),
          ),
          const Align(
            alignment: Alignment(-.82, .70),
            child: Text(
              '+1',
              style: TextStyle(
                color: Color(0xFFFFE89A),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPuzzlePreview extends StatelessWidget {
  const _MiniPuzzlePreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 118,
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF553C8B),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: SizedBox(
          width: 146,
          height: 92,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/images/world_island_1.webp',
                  width: 146,
                  height: 92,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _PuzzleGridPainter(),
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Transform.rotate(
                  angle: .12,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB596F1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x44000000),
                          blurRadius: 7,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(
                        'assets/images/ui/puzzle.webp',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PuzzleGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .85)
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


class _MiniCountObjectsPreview extends StatelessWidget {
  const _MiniCountObjectsPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 118,
      width: 220,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFE7C2),
            Color(0xFFFFCFA8),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/images/games/pizza/pizza_base.webp',
                        fit: BoxFit.contain,
                      ),
                    ),
                    Positioned(left: 18, top: 18, width: 22, height: 22, child: Image.asset('assets/images/games/pizza/pepperoni.webp')),
                    Positioned(right: 18, top: 29, width: 22, height: 22, child: Image.asset('assets/images/games/pizza/pepperoni.webp')),
                    Positioned(left: 34, bottom: 17, width: 22, height: 22, child: Image.asset('assets/images/games/pizza/pepperoni.webp')),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Сколько?',
                style: TextStyle(
                  color: Color(0xFF8A4F2A),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 7),
              Row(
                children: [
                  const _MiniNumberChip(value: '3'),
                  SizedBox(width: 5),
                  const _MiniNumberChip(value: '5', highlighted: true),
                  SizedBox(width: 5),
                  const _MiniNumberChip(value: '7'),
                ],
              ),
              SizedBox(height: 5),
              Icon(
                Icons.touch_app_rounded,
                color: Color(0xFFE76F51),
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniNumberChip extends StatelessWidget {
  final String value;
  final bool highlighted;

  const _MiniNumberChip({
    required this.value,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 27,
      height: 31,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFE76F51) : Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: highlighted
              ? const Color(0xFFE76F51)
              : const Color(0xFFF0B58F),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        value,
        style: TextStyle(
          color: highlighted ? Colors.white : const Color(0xFF9A5A34),
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MiniConnectDotsPreview extends StatelessWidget {
  const _MiniConnectDotsPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      height: 112,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFEFF5FF),
            Color(0xFFDCE9FF),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const CustomPaint(
        painter: _MiniConnectDotsPainter(),
      ),
    );
  }
}

class _MiniConnectDotsPainter extends CustomPainter {
  const _MiniConnectDotsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final points = <Offset>[
      Offset(size.width * .18, size.height * .70),
      Offset(size.width * .34, size.height * .28),
      Offset(size.width * .50, size.height * .70),
      Offset(size.width * .66, size.height * .28),
      Offset(size.width * .82, size.height * .70),
    ];

    final linePaint = Paint()
      ..color = const Color(0xFF6D91E7)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 3; i++) {
      canvas.drawLine(points[i], points[i + 1], linePaint);
    }

    for (var i = 0; i < points.length; i++) {
      final active = i < 4;
      canvas.drawCircle(
        points[i],
        11,
        Paint()..color = active ? const Color(0xFF4E7DDE) : Colors.white,
      );
      canvas.drawCircle(
        points[i],
        11,
        Paint()
          ..color = const Color(0xFF4E7DDE)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF315EA8),
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        points[i] - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
