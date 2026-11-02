import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/dragon_evolution.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../widgets/magic_ui.dart';

class DragonEvolutionScreen extends StatefulWidget {
  final AppRepository repository;

  const DragonEvolutionScreen({
    super.key,
    required this.repository,
  });

  @override
  State<DragonEvolutionScreen> createState() => _DragonEvolutionScreenState();
}

class _DragonEvolutionScreenState extends State<DragonEvolutionScreen> {
  late Future<DragonEvolutionData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<DragonEvolutionData> _loadData() async {
    final data = await widget.repository.getDragonEvolution();
    if (mounted) {
      await precacheBackendImages(
        context,
        data.levels.map((level) => level.iconUrl),
      );
    }
    return data;
  }

  Future<void> _reload() async {
    setState(() => _future = _loadData());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5DBFEF),
      body: FutureBuilder<DragonEvolutionData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ZenviaLoadingScreen();
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return _Background(
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .94),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🐉', style: TextStyle(fontSize: 58)),
                          const SizedBox(height: 12),
                          Text(
                            context.tr('dragonEvolutionLoadFailed'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.deepBlue,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _reload,
                            child: Text(context.tr('retry')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return _EvolutionBody(
            data: snapshot.data!,
            onRefresh: _reload,
          );
        },
      ),
    );
  }
}

class _EvolutionBody extends StatelessWidget {
  final DragonEvolutionData data;
  final Future<void> Function() onRefresh;

  const _EvolutionBody({
    required this.data,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final current = data.currentLevel;
    final currentNumber = current?.number ?? 0;

    return _Background(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: onRefresh,
          color: AppColors.primary,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final horizontal = (width * .055).clamp(16.0, 26.0);
              final dragonSize = (width * .66).clamp(235.0, 330.0);

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 30),
                child: Column(
                  children: [
                    _TopBar(onBack: () => Navigator.of(context).pop()),
                    const SizedBox(height: 10),
                    Text(
                      context.tr('dragonGrowsWithYou'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(
                            color: Color(0x660B4A83),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _EvolutionStrip(
                      levels: data.levels,
                      currentLevelNumber: currentNumber,
                    ),
                    const SizedBox(height: 14),
                    _LevelProgress(data: data),
                    const SizedBox(height: 14),
                    Text(
                      current == null ? context.tr('journeyBegins') : context.tr('levelNumber', {'number': current.number}),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                        shadows: [
                          Shadow(
                            color: Color(0x770B4A83),
                            blurRadius: 7,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    _LevelTitle(
                      title: current == null || current.title.trim().isEmpty
                          ? context.tr('youngDragon')
                          : current.title.trim(),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: dragonSize + 50,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Positioned(
                            top: 0,
                            right: -16,
                            child: _SpeechBubble(
                              text: data.isMaxLevel
                                  ? context.tr('maxLevelReached')
                                  : context.tr('makingProgress'),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Center(
                              child: _CurrentDragon(
                                imageUrl: current?.iconUrl,
                                size: dragonSize,
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
      ),
    );
  }
}


class _LevelTitle extends StatelessWidget {
  final String title;

  const _LevelTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: 190,
        maxWidth: 310,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: .68),
            const Color(0xFFDDF5FF).withValues(alpha: .48),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: .82),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlue.withValues(alpha: .18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: .24),
            blurRadius: 7,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.deepBlue,
          fontSize: 28,
          height: 1.02,
          fontWeight: FontWeight.w900,
          letterSpacing: .2,
          shadows: [
            Shadow(
              color: Color(0x99FFFFFF),
              blurRadius: 5,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onBack;

  const _TopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: Colors.white.withValues(alpha: .20),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onBack,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
        const Spacer(),
      ],
    );
  }
}

class _EvolutionStrip extends StatelessWidget {
  final List<DragonLevel> levels;
  final int currentLevelNumber;

  const _EvolutionStrip({
    required this.levels,
    required this.currentLevelNumber,
  });

  @override
  Widget build(BuildContext context) {
    if (levels.isEmpty) {
      return const SizedBox(height: 110);
    }

    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: levels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final level = levels[index];
          final unlocked = level.number <= currentLevelNumber;
          final current = level.number == currentLevelNumber;
          return _EvolutionItem(
            level: level,
            unlocked: unlocked,
            current: current,
          );
        },
      ),
    );
  }
}

class _EvolutionItem extends StatelessWidget {
  final DragonLevel level;
  final bool unlocked;
  final bool current;

  const _EvolutionItem({
    required this.level,
    required this.unlocked,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: Column(
        children: [
          SizedBox(
            width: 72,
            height: 82,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(2),
                  child: _EvolutionDragonImage(
                    imageUrl: level.iconUrl,
                    unlocked: unlocked,
                  ),
                ),
                if (!unlocked)
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: Icon(
                      Icons.lock_rounded,
                      color: Colors.white,
                      size: 21,
                      shadows: [
                        Shadow(
                          color: Color(0x99000000),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(minWidth: 31),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: unlocked
                  ? const Color(0xFFFFC83D)
                  : const Color(0xFF75838D).withValues(alpha: .92),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white, width: 1.2),
            ),
            child: Text(
              '${level.number}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvolutionDragonImage extends StatelessWidget {
  final String? imageUrl;
  final bool unlocked;

  const _EvolutionDragonImage({
    required this.imageUrl,
    required this.unlocked,
  });

  static const _greyMatrix = <double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    Widget image;
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      image = const Center(
        child: Text('🐉', style: TextStyle(fontSize: 38)),
      );
    } else {
      image = Image.network(
        url,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const Center(
          child: Text('🐉', style: TextStyle(fontSize: 38)),
        ),
      );
    }

    if (unlocked) return image;

    return Opacity(
      opacity: .72,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(_greyMatrix),
        child: image,
      ),
    );
  }
}

class _LevelProgress extends StatelessWidget {
  final DragonEvolutionData data;

  const _LevelProgress({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF2C77A6).withValues(alpha: .88),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0E3B7D).withValues(alpha: .25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Stack(
          children: [
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: data.levelProgress,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF25E968),
                        Color(0xFF0FCB68),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (data.levelProgress > .05)
              Positioned(
                left: 12,
                top: 4,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.white, blurRadius: 6),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CurrentDragon extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const _CurrentDragon({
    required this.imageUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return SizedBox(
      width: size,
      height: size,
      child: url == null || url.isEmpty
          ? Center(
              child: Text(
                '🐉',
                style: TextStyle(fontSize: size * .45),
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  '🐉',
                  style: TextStyle(fontSize: size * .45),
                ),
              ),
            ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  final String text;

  const _SpeechBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 164,
      height: 93,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/dragon_speech_bubble.webp',
            fit: BoxFit.fill,
            filterQuality: FilterQuality.high,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(21, 16, 18, 26),
            child: Center(
              child: Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.deepBlue,
                  fontSize: 14,
                  height: 1.05,
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

class _Background extends StatelessWidget {
  final Widget child;

  const _Background({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Image(
          image: AssetImage('assets/images/dragon_evolution_bg.webp'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF006DAE).withValues(alpha: .40),
                const Color(0xFF59C6F2).withValues(alpha: .10),
                Colors.transparent,
              ],
              stops: const [0, .36, 1],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
