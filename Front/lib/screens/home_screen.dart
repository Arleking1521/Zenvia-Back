import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/language.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../widgets/magic_ui.dart';
import 'dragon_evolution_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppRepository repository;
  final VoidCallback onOpenSettings;
  final VoidCallback onSeeAllTopics;
  final VoidCallback onOpenAchievements;
  final VoidCallback? onLanguageChanged;

  const HomeScreen({
    super.key,
    required this.repository,
    required this.onOpenSettings,
    required this.onSeeAllTopics,
    required this.onOpenAchievements,
    this.onLanguageChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<LanguageOption>> _languagesFuture;
  AppLanguage _selectedLanguage = AppLanguage.english;
  bool _languageSelectionInProgress = false;
  String? _levelDragonUrl;

  @override
  void initState() {
    super.initState();
    _languagesFuture = _load();
  }

  Future<List<LanguageOption>> _load() async {
    final selected = await widget.repository.getSelectedLanguage();
    final languages = await widget.repository.getAvailableLanguages();

    String? dragonUrl;
    try {
      dragonUrl = await widget.repository.getLevelDragonUrl();
    } catch (_) {
      // Если картинку уровня временно не удалось получить,
      // ниже останется локальный fallback-дракончик.
    }

    // Не показываем готовую страницу, пока изображения, пришедшие с backend,
    // не окажутся в Flutter image cache. Иначе локальный фон появляется сразу,
    // а иконки языков/дракон заметно дорисовываются уже после открытия экрана.
    await precacheBackendImages(
      context,
      <String?>[
        dragonUrl,
        ...languages.map((language) => language.iconUrl),
      ],
    );

    if (mounted) {
      setState(() {
        _selectedLanguage = selected;
        _levelDragonUrl = dragonUrl;
      });
    } else {
      _selectedLanguage = selected;
      _levelDragonUrl = dragonUrl;
    }
    return languages;
  }

  Future<void> _openDragonEvolution() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DragonEvolutionScreen(repository: widget.repository),
      ),
    );

    // После возврата обновляем изображение: уровень мог измениться.
    try {
      final url = await widget.repository.getLevelDragonUrl();
      if (!mounted) return;
      await precacheBackendImages(context, <String?>[url]);
      if (!mounted) return;
      setState(() => _levelDragonUrl = url);
    } catch (_) {
      // Сохраняем уже показанное изображение при временной ошибке сети.
    }
  }

  Future<void> _selectLanguage(LanguageOption option) async {
    if (_languageSelectionInProgress) return;
    _languageSelectionInProgress = true;
    final language = option.appLanguage;
    if (language == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('languageUnsupported', {'language': option.title}),
          ),
        ),
      );
      _languageSelectionInProgress = false;
      return;
    }

    // Даже если этот язык уже сохранён, повторное нажатие должно
    // снова открыть экран выбора приключения.
    final previousLanguage = _selectedLanguage;
    if (language != _selectedLanguage) {
      setState(() => _selectedLanguage = language);
    }

    try {
      await widget.repository.setSelectedLanguage(language);
      if (!mounted) return;

      // Обновляем скрытые экраны и открываем пещеры.
      // Callback вызывается и при повторном выборе того же языка.
      widget.onLanguageChanged?.call();
    } catch (_) {
      if (mounted && language != previousLanguage) {
        setState(() => _selectedLanguage = previousLanguage);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('languageChangeFailed'))),
        );
      }
    } finally {
      _languageSelectionInProgress = false;
    }
  }

  void _retry() {
    setState(() => _languagesFuture = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LanguageOption>>(
      future: _languagesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ZenviaLoadingScreen();
        }

        if (snapshot.hasError) {
          return _ApiErrorState(
            message: snapshot.error.toString(),
            onRetry: _retry,
          );
        }

        final languages = snapshot.data ?? const <LanguageOption>[];

        return ColoredBox(
          color: const Color(0xFF7ED8F4),
          child: Stack(
            children: [
              const Positioned.fill(
                child: Image(
                  image: AssetImage('assets/images/home_language_bg.webp'),
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.blue.withValues(alpha: .06),
                        Colors.transparent,
                        Colors.white.withValues(alpha: .04),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final height = constraints.maxHeight;
                    final width = constraints.maxWidth;
                    final dragonSize = math.min(
                      width * .66,
                      height * .30,
                    ).clamp(190.0, 270.0).toDouble();

                    // Облачные карточки чуть выше прежних кнопок.
                    // Рассчитываем размер от доступной высоты, чтобы они
                    // не наезжали на дракончика на небольших экранах.
                    final languageCount = math.max(1, languages.length);
                    const languageGap = 4.0;
                    final availableForLanguages = math.max(
                      260.0,
                      height - dragonSize - 150.0,
                    );
                    final languageCardHeight = (
                      (availableForLanguages -
                              (languageCount - 1) * languageGap) /
                          languageCount
                    ).clamp(68.0, 88.0).toDouble();
                    final languageCardWidth = math.min(
                      width - 30.0,
                      languageCardHeight * 3.45,
                    ).clamp(238.0, 304.0).toDouble();

                    return RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: () async {
                        setState(() => _languagesFuture = _load());
                        await _languagesFuture;
                      },
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                              child: Stack(
                                fit: StackFit.expand,
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: _TopBar(
                                      onSettings: widget.onOpenSettings,
                                      onAchievements: widget.onOpenAchievements,
                                    ),
                                  ),
                                  Positioned(
                                    top: 58,
                                    left: 0,
                                    right: 0,
                                    child: Text(
                                      context.tr('chooseLanguage'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 25,
                                        fontWeight: FontWeight.w900,
                                        shadows: [
                                          Shadow(
                                            color: Color(0x990E3B7D),
                                            blurRadius: 7,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Кнопки языков находятся ровно в средней
                                  // части экрана по высоте.
                                  Align(
                                    alignment: const Alignment(0, -0.10),
                                    child: Transform.translate(
                                      offset: const Offset(0, -60),
                                      child: languages.isEmpty
                                          ? const _EmptyLanguages()
                                          : Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                for (var i = 0; i < languages.length; i++) ...[
                                                  _LanguageChoiceCard(
                                                    language: languages[i],
                                                    width: languageCardWidth,
                                                    height: languageCardHeight,
                                                    floatIndex: i,
                                                    onTap: () => _selectLanguage(languages[i]),
                                                  ),
                                                  if (i != languages.length - 1)
                                                    const SizedBox(height: languageGap),
                                                ],
                                              ],
                                            ),
                                    ),
                                  ),

                                  // Дракон текущего уровня. Положение оставляем
                                  // прежним, но теперь картинка приходит с backend.
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 24,
                                    child: Center(
                                      child: GestureDetector(
                                        onTap: _openDragonEvolution,
                                        behavior: HitTestBehavior.opaque,
                                        child: SizedBox(
                                          width: dragonSize,
                                          height: dragonSize,
                                          child: _LevelDragonImage(
                                            url: _levelDragonUrl,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
      },
    );
  }
}

class _LevelDragonImage extends StatelessWidget {
  final String? url;

  const _LevelDragonImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final value = url?.trim();

    if (value == null || value.isEmpty) {
      return Image.asset(
        'assets/images/home_language_dragon.webp',
        fit: BoxFit.contain,
        alignment: Alignment.bottomCenter,
      );
    }

    return Image.network(
      value,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Image.asset(
        'assets/images/home_language_dragon.webp',
        fit: BoxFit.contain,
        alignment: Alignment.bottomCenter,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onSettings;
  final VoidCallback onAchievements;

  const _TopBar({
    required this.onSettings,
    required this.onAchievements,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: const Color(0x332A85B7),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onSettings,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                Icons.settings_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
        const Spacer(),
        Material(
          color: const Color(0x332A85B7),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onAchievements,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 25,
                shadows: [
                  Shadow(color: Color(0x660E3B7D), blurRadius: 7),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LanguageChoiceCard extends StatefulWidget {
  final LanguageOption language;
  final double width;
  final double height;
  final int floatIndex;
  final VoidCallback onTap;

  const _LanguageChoiceCard({
    required this.language,
    required this.width,
    required this.height,
    required this.floatIndex,
    required this.onTap,
  });

  @override
  State<_LanguageChoiceCard> createState() => _LanguageChoiceCardState();
}

class _LanguageChoiceCardState extends State<_LanguageChoiceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatController;
  late final Animation<double> _floatAnimation;
  bool _pressed = false;

  static const _floatAmplitudes = <double>[4.5, 5.5, 4.0, 5.0];
  static const _floatPhases = <double>[0.08, 0.42, 0.72, 0.24];

  @override
  void initState() {
    super.initState();

    final index = widget.floatIndex % _floatAmplitudes.length;
    _floatController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 3400 + index * 260),
      value: _floatPhases[index],
    )..repeat(reverse: true);

    _floatAnimation = CurvedAnimation(
      parent: _floatController,
      curve: Curves.easeInOutSine,
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final amplitude = _floatAmplitudes[
      widget.floatIndex % _floatAmplitudes.length
    ];

    return AnimatedBuilder(
      animation: _floatAnimation,
      builder: (context, child) {
        final offsetY = disableAnimations
            ? 0.0
            : (_floatAnimation.value * 2 - 1) * amplitude;

        return Transform.translate(
          offset: Offset(0, offsetY),
          child: child,
        );
      },
      child: Center(
        child: Semantics(
          button: true,
          label: context.tr('chooseLanguageA11y', {'language': widget.language.title}),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTapDown: (_) => _setPressed(true),
            onTapCancel: () => _setPressed(false),
            onTapUp: (_) => _setPressed(false),
            child: AnimatedScale(
              scale: _pressed ? .965 : 1,
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              child: SizedBox(
                width: widget.width,
                height: widget.height,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                  // Прозрачное облако с золотой окантовкой из assets.
                  // BoxFit.fill позволяет сохранить одинаковую высоту карточек
                  // на разных экранах без изменения логики страницы.
                  const Positioned.fill(
                    child: Image(
                      image: AssetImage(
                        'assets/images/language_cloud_card.webp',
                      ),
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      // Увеличенный внутренний отступ слева: иконка/флаг и
                      // название языка дополнительно сдвинуты вправо,
                      // глубже внутрь светлой части облака.
                      widget.height * .57,
                      widget.height * .10,
                      widget.height * .25,
                      widget.height * .09,
                    ),
                    child: Row(
                      children: [
                        _LanguageIcon(
                          language: widget.language,
                          size: (widget.height * .58).clamp(40.0, 49.0),
                        ),
                        SizedBox(width: widget.height * .13),
                        Expanded(
                          child: Text(
                            widget.language.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF40558C),
                              fontSize: (widget.height * .205).clamp(15.0, 18.0),
                              fontWeight: FontWeight.w900,
                              letterSpacing: .1,
                              shadows: const [
                                Shadow(
                                  color: Color(0xCCFFFFFF),
                                  blurRadius: 3,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: const Color(0xFFD8A91E).withValues(alpha: .78),
                          size: (widget.height * .31).clamp(21.0, 27.0),
                        ),
                      ],
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageIcon extends StatelessWidget {
  final LanguageOption language;
  final double size;

  const _LanguageIcon({
    required this.language,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final url = language.iconUrl;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFFFD84D).withValues(alpha: .95),
          width: 2.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF5B91A).withValues(alpha: .20),
            blurRadius: 7,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null || url.isEmpty
          ? Center(
              child: Text(
                language.appLanguage?.flagEmoji ?? '•',
                style: TextStyle(fontSize: size * .58),
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  language.appLanguage?.flagEmoji ?? '•',
                  style: TextStyle(fontSize: size * .58),
                ),
              ),
            ),
    );
  }
}

class _EmptyLanguages extends StatelessWidget {
  const _EmptyLanguages();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .90),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Text(
          context.tr('noLanguages'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.deepBlue,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ApiErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ApiErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: Image(
            image: AssetImage('assets/images/home_language_bg.webp'),
            fit: BoxFit.cover,
          ),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: MagicCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/cloud_cute.webp', width: 60, height: 60, fit: BoxFit.contain),
                    const SizedBox(height: 10),
                    Text(
                      context.tr('loadLanguagesFailed'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    MagicPrimaryButton(
                      label: context.tr('retry'),
                      onPressed: onRetry,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
