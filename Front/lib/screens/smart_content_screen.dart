import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/language.dart';
import '../models/literary_content.dart';
import '../l10n/app_strings.dart';
import '../services/audio_settings_service.dart';
import '../theme/app_colors.dart';
import '../widgets/magic_ui.dart';

class SmartContentScreen extends StatefulWidget {
  final AppRepository repository;
  final AppLanguage language;

  const SmartContentScreen({
    super.key,
    required this.repository,
    required this.language,
  });

  @override
  State<SmartContentScreen> createState() => _SmartContentScreenState();
}

class _SmartContentScreenState extends State<SmartContentScreen> {
  static const int _pageSize = 20;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final Dio _dio = Dio();
  final Map<String, Uint8List> _cache = <String, Uint8List>{};
  final ScrollController _scrollController = ScrollController();
  final List<LiteraryContentItem> _items = <LiteraryContentItem>[];

  LiteraryContentType? _filter;
  Set<LiteraryContentType> _availableTypes = <LiteraryContentType>{};
  int? _playingId;
  bool _audioBusy = false;
  StreamSubscription<void>? _completeSubscription;

  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _nextPage = 1;
  int _loadGeneration = 0;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playingId = null;
        _audioBusy = false;
      });
    });
    _scrollController.addListener(_onScroll);
    _resetAndLoad();
  }

  @override
  void dispose() {
    _completeSubscription?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _initialLoading || _loadingMore || !_hasMore) {
      return;
    }
    if (_scrollController.position.extentAfter < 700) {
      _loadNextPage();
    }
  }

  Future<void> _resetAndLoad() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _initialLoading = true;
        _loadingMore = false;
        _hasMore = true;
        _nextPage = 1;
        _loadError = null;
        _items.clear();
      });
    }

    try {
      final page = await widget.repository.getLiteraryContentPage(
        widget.language,
        type: _filter,
        page: 1,
        pageSize: _pageSize,
      );
      if (!mounted || generation != _loadGeneration) return;

      await precacheBackendImages(
        context,
        page.items.map((item) => item.imageUrl),
      );
      if (!mounted || generation != _loadGeneration) return;

      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _availableTypes = page.availableTypes;
        if (_filter != null && !_availableTypes.contains(_filter)) {
          _filter = null;
        }
        _hasMore = page.hasNext;
        _nextPage = 2;
        _initialLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = error;
        _initialLoading = false;
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (_initialLoading || _loadingMore || !_hasMore) return;
    final generation = _loadGeneration;
    final pageNumber = _nextPage;
    setState(() => _loadingMore = true);

    try {
      final page = await widget.repository.getLiteraryContentPage(
        widget.language,
        type: _filter,
        page: pageNumber,
        pageSize: _pageSize,
      );
      if (!mounted || generation != _loadGeneration) return;

      await precacheBackendImages(
        context,
        page.items.map((item) => item.imageUrl),
      );
      if (!mounted || generation != _loadGeneration) return;

      final knownIds = _items.map((item) => item.id).toSet();
      setState(() {
        _items.addAll(page.items.where((item) => !knownIds.contains(item.id)));
        if (page.availableTypes.isNotEmpty) {
          _availableTypes = page.availableTypes;
        }
        _hasMore = page.hasNext;
        _nextPage = pageNumber + 1;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('smartLoadFailed'))),
      );
    }
  }

  Future<void> _refresh() async {
    await _resetAndLoad();
  }

  void _changeFilter(LiteraryContentType? filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _resetAndLoad();
  }

  Future<void> _play(LiteraryContentItem item) async {
    final url = item.audioUrl?.trim();
    if (url == null || url.isEmpty || _audioBusy) return;

    if (_playingId == item.id) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingId = null);
      return;
    }

    if (mounted) {
      setState(() {
        _playingId = item.id;
        _audioBusy = true;
      });
    }
    try {
      var bytes = _cache[url];
      if (bytes == null) {
        final response = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        bytes = Uint8List.fromList(response.data ?? const <int>[]);
        if (bytes.isNotEmpty) _cache[url] = bytes;
      }
      if (bytes.isEmpty) throw Exception('Пустой аудиофайл');
      await _audioPlayer.stop();
      await AudioSettingsService.instance.load();
      await _audioPlayer.play(
        BytesSource(bytes),
        volume: AudioSettingsService.instance.voiceVolume,
      );
      if (mounted) setState(() => _audioBusy = false);
      try {
        await widget.repository.markLiteraryContentListened(item.id);
      } catch (_) {
        // Прослушивание не должно ломаться из-за статистики.
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _playingId = null;
          _audioBusy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('smartAudioPlayFailed'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CloudWorldBackground(
        child: SafeArea(
          child: _initialLoading
              ? const ZenviaLoadingScreen()
              : _loadError != null && _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: MagicCard(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AppArtIcon(
                                asset: 'assets/images/ui/lightbulb.webp',
                                size: 58,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                context.tr('smartLoadFailed'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.deepBlue,
                                ),
                              ),
                              const SizedBox(height: 14),
                              MagicPrimaryButton(
                                label: context.tr('retry'),
                                onPressed: _refresh,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                        children: [
                          Row(
                            children: [
                              _BackButton(onTap: () => Navigator.of(context).pop()),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.tr('knowledgeCave'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.deepBlue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48),
                            ],
                          ),
                          const SizedBox(height: 12),
                          MagicCard(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF9B5DE5), Color(0xFF6A4BC6)],
                            ),
                            child: Column(
                              children: [
                                const AppArtIcon(
                                  asset: 'assets/images/ui/lightbulb.webp',
                                  size: 62,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  context.tr('wantBeSmart'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 23,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${widget.language.flagEmoji} ${widget.language.label}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _FilterChip(
                                  label: context.tr('allFilter'),
                                  selected: _filter == null,
                                  onTap: () => _changeFilter(null),
                                ),
                                ...LiteraryContentType.values
                                    .where((type) =>
                                        type != LiteraryContentType.other &&
                                        _availableTypes.contains(type))
                                    .map(
                                      (type) => Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: _FilterChip(
                                          label: _literaryTypeTitle(context, type),
                                          asset: _literaryTypeAsset(type),
                                          selected: _filter == type,
                                          onTap: () => _changeFilter(type),
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_items.isEmpty)
                            MagicCard(
                              child: Column(
                                children: [
                                  const AppArtIcon(
                                    asset: 'assets/images/ui/book.webp',
                                    size: 58,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _filter == null
                                        ? context.tr('noSmartContent')
                                        : context.tr('emptyCategory'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            ..._items.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _ContentCard(
                                  item: item,
                                  loadingAudio: _audioBusy && _playingId == item.id,
                                  playingAudio: !_audioBusy && _playingId == item.id,
                                  onPlay: item.audioUrl == null ? null : () => _play(item),
                                ),
                              ),
                            ),
                          if (_loadingMore)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          if (!_hasMore && _items.isNotEmpty)
                            const SizedBox(height: 8),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}

String _literaryTypeTitle(BuildContext context, LiteraryContentType type) {
  switch (type) {
    case LiteraryContentType.poem:
      return context.tr('smartTypePoem');
    case LiteraryContentType.proverb:
      return context.tr('smartTypeProverb');
    case LiteraryContentType.riddle:
      return context.tr('smartTypeRiddle');
    case LiteraryContentType.tongueTwister:
      return context.tr('smartTypeTongueTwister');
    case LiteraryContentType.other:
      return context.tr('smartTypeOther');
  }
}

String _literaryTypeAsset(LiteraryContentType type) {
  switch (type) {
    case LiteraryContentType.poem:
      return 'assets/images/ui/book.webp';
    case LiteraryContentType.proverb:
      return 'assets/images/ui/proverbs.webp';
    case LiteraryContentType.riddle:
      return 'assets/images/ui/puzzle.webp';
    case LiteraryContentType.tongueTwister:
      return 'assets/images/ui/speaker.webp';
    case LiteraryContentType.other:
      return 'assets/images/reward_star_clean.webp';
  }
}

class _ContentCard extends StatelessWidget {
  final LiteraryContentItem item;
  final bool loadingAudio;
  final bool playingAudio;
  final VoidCallback? onPlay;

  const _ContentCard({
    required this.item,
    required this.loadingAudio,
    required this.playingAudio,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return MagicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2E9FF),
                  borderRadius: BorderRadius.circular(15),
                ),
                alignment: Alignment.center,
                child: Image.asset(_literaryTypeAsset(item.type), width: 32, height: 32, fit: BoxFit.contain),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: AppColors.deepBlue,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      item.author == null
                          ? _literaryTypeTitle(context, item.type)
                          : '${_literaryTypeTitle(context, item.type)} · ${item.author}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (onPlay != null)
                IconButton.filledTonal(
                  onPressed: loadingAudio ? null : onPlay,
                  icon: loadingAudio
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(playingAudio ? Icons.stop_rounded : Icons.volume_up_rounded),
                ),
            ],
          ),
          if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                item.imageUrl!,
                width: double.infinity,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            item.text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String? asset;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.asset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF8F65D8) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? const Color(0xFF8F65D8) : AppColors.trackGrey,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (asset != null) ...[
                Image.asset(asset!, width: 22, height: 22, fit: BoxFit.contain),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.deepBlue,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .92),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.arrow_back_rounded, color: AppColors.deepBlue),
        ),
      ),
    );
  }
}
