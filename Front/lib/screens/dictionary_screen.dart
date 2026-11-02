import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/language.dart';
import '../l10n/app_strings.dart';
import '../models/topic.dart';
import '../services/audio_settings_service.dart';
import '../services/background_music_service.dart';
import '../theme/app_colors.dart';
import '../widgets/magic_ui.dart';

class DictionaryScreen extends StatefulWidget {
  final Topic topic;
  final AppLanguage language;

  const DictionaryScreen({
    super.key,
    required this.topic,
    required this.language,
  });

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final Object _backgroundMusicToken = Object();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 10),
    ),
  );
  final Map<String, Uint8List> _audioCache = <String, Uint8List>{};
  final Map<String, int> _listenCounts = <String, int>{};
  String? _currentAudioUrl;
  late Future<void> _imagesFuture;
  int _wordIndex = 0;
  bool _isPlayingAudio = false;
  bool _isLoadingAudio = false;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<void>? _playerCompleteSubscription;

  @override
  void initState() {
    super.initState();
    BackgroundMusicService.instance.silence(_backgroundMusicToken);
    _imagesFuture = _preloadImages();
    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlayingAudio = state == PlayerState.playing);
    });
    _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlayingAudio = false;
        _isLoadingAudio = false;
        _currentAudioUrl = null;
      });
    });
  }

  Future<void> _preloadImages() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await precacheBackendImages(
      context,
      widget.topic.words.map((word) => word.imageUrl),
    );
  }

  @override
  void dispose() {
    BackgroundMusicService.instance.unsilence(_backgroundMusicToken);
    _playerStateSubscription?.cancel();
    _playerCompleteSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<Uint8List> _loadAudioBytes(String url) async {
    final cached = _audioCache[url];
    if (cached != null && cached.isNotEmpty) return cached;
    final response = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        headers: const {'Accept': 'audio/mpeg,audio/*;q=0.9,*/*;q=0.8'},
      ),
    );
    final raw = response.data;
    if (raw == null || raw.isEmpty) throw StateError('Empty audio');
    final bytes = Uint8List.fromList(raw);
    _audioCache[url] = bytes;
    return bytes;
  }

  Future<void> _playAudio(String? audioUrl) async {
    final url = audioUrl?.trim();
    if (url == null || url.isEmpty || _isLoadingAudio) return;
    try {
      if (_isPlayingAudio && _currentAudioUrl == url) {
        await _audioPlayer.stop();
        if (mounted) {
          setState(() {
            _isPlayingAudio = false;
            _currentAudioUrl = null;
          });
        }
        return;
      }
      if (mounted) setState(() => _isLoadingAudio = true);
      await _audioPlayer.stop();
      final bytes = await _loadAudioBytes(url);
      final lower = url.toLowerCase();
      final mimeType = lower.endsWith('.wav')
          ? 'audio/wav'
          : lower.endsWith('.m4a')
              ? 'audio/mp4'
              : lower.endsWith('.ogg')
                  ? 'audio/ogg'
                  : 'audio/mpeg';
      await AudioSettingsService.instance.load();
      final listenNumber = (_listenCounts[url] ?? 0) + 1;
      _listenCounts[url] = listenNumber;
      await _audioPlayer.play(
        BytesSource(bytes, mimeType: mimeType),
        volume: AudioSettingsService.instance.voiceVolume,
      );
      await _audioPlayer.setPlaybackRate(listenNumber.isEven ? 0.72 : 1.0);
      if (mounted) {
        setState(() {
          _currentAudioUrl = url;
          _isLoadingAudio = false;
        });
      }
    } on DioException {
      if (!mounted) return;
      setState(() {
        _isLoadingAudio = false;
        _isPlayingAudio = false;
        _currentAudioUrl = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('audioPlayFailed'))),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingAudio = false;
        _isPlayingAudio = false;
        _currentAudioUrl = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('audioPlayFailed'))));
    }
  }

  Future<void> _changeWord(int newIndex) async {
    await _audioPlayer.stop();
    if (!mounted) return;
    setState(() {
      _wordIndex = newIndex;
      _isPlayingAudio = false;
      _isLoadingAudio = false;
      _currentAudioUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _imagesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: ZenviaLoadingScreen());
        }
        return _buildReady(context);
      },
    );
  }

  Widget _buildReady(BuildContext context) {
    final topic = widget.topic;
    final learnedWords = topic.learnedWords;
    if (learnedWords.isEmpty) {
      return Scaffold(
        body: FantasyBackground(
          child: SafeArea(
            child: Center(
              child: MagicCard(child: Text(context.tr('dictionaryNoLearnedWords'))),
            ),
          ),
        ),
      );
    }

    final word = learnedWords[_wordIndex];
    final transcription = word.transcriptionFor(widget.language);
    final audioUrl = word.audioFor(widget.language);
    final hasAudio = audioUrl != null && audioUrl.trim().isNotEmpty;
    final progress = (_wordIndex + 1) / learnedWords.length;
    final remaining = learnedWords.length - (_wordIndex + 1);

    return Scaffold(
      body: FantasyBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    _circleButton(Icons.arrow_back_rounded, () async {
                      await _audioPlayer.stop();
                      if (context.mounted) Navigator.pop(context);
                    }),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            topic.title,
                            style: const TextStyle(
                              color: AppColors.deepBlue,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.tr('lessonStep', {'current': _wordIndex + 1, 'total': learnedWords.length}),
                            style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    _smallBadge(text: '${(_wordIndex + 1)}/${learnedWords.length}', icon: Icons.auto_awesome_rounded),
                  ],
                ),
                const SizedBox(height: 14),
                MagicCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                  radius: 30,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3AA7FF), Color(0xFF1C67D2)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.tr('learnWithDragon'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .22),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              remaining == 0 ? context.tr('lastWord') : context.tr('remaining', {'count': remaining}),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: Colors.white.withValues(alpha: .28),
                          valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: MagicCard(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    radius: 34,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _sideSoundButton(
                              icon: Icons.volume_up_rounded,
                              enabled: hasAudio,
                              loading: _isLoadingAudio,
                              playing: _isPlayingAudio,
                              onTap: hasAudio ? () => _playAudio(audioUrl) : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6F8FF),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr('listenLookRemember'),
                                      style: const TextStyle(
                                        color: AppColors.deepBlue,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      hasAudio ? context.tr('tapRepeatAloud') : context.tr('audioNotAddedShort'),
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FBFF),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: Center(
                                    child: _WordImage(imageUrl: word.imageUrl),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  word.translationFor(widget.language),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.deepBlue,
                                    height: 1,
                                  ),
                                ),
                                if (transcription != null && transcription.trim().isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    transcription,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFFFEF90), Color(0xFFFFD23F)],
                                    ),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    _wordIndex == learnedWords.length - 1 ? context.tr('almostDoneStar') : context.tr('rememberAndMove'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.deepBlue,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_wordIndex > 0) ...[
                      Expanded(
                        child: _ghostButton(
                          label: context.tr('back'),
                          icon: Icons.arrow_back_rounded,
                          onPressed: () => _changeWord(_wordIndex - 1),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 2,
                      child: MagicPrimaryButton(
                        label: _wordIndex < learnedWords.length - 1 ? context.tr('nextWord') : context.tr('finish'),
                        icon: _wordIndex < learnedWords.length - 1 ? Icons.arrow_forward_rounded : Icons.star_rounded,
                        onPressed: () async {
                          if (_wordIndex < learnedWords.length - 1) {
                            await _changeWord(_wordIndex + 1);
                          } else {
                            await _audioPlayer.stop();
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: .95),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(width: 46, height: 46, child: Icon(icon, color: AppColors.deepBlue)),
      ),
    );
  }

  Widget _smallBadge({required String text, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.goldDark),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.deepBlue,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ghostButton({required String label, required IconData icon, required VoidCallback onPressed}) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.deepBlue,
        side: BorderSide(color: AppColors.deepBlue.withValues(alpha: .18)),
        backgroundColor: Colors.white.withValues(alpha: .88),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
      ),
    );
  }

  Widget _sideSoundButton({
    required IconData icon,
    required bool enabled,
    required bool loading,
    required bool playing,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: enabled ? AppColors.gold : AppColors.trackGrey,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 58,
          height: 58,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                  )
                : Icon(
                    playing ? Icons.stop_rounded : icon,
                    color: enabled ? Colors.white : AppColors.textMuted,
                    size: 28,
                  ),
          ),
        ),
      ),
    );
  }
}

class _WordImage extends StatelessWidget {
  final String? imageUrl;
  const _WordImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return Center(child: Image.asset('assets/images/ui/picture.webp', width: 132, height: 132, fit: BoxFit.contain));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => Center(child: Image.asset('assets/images/ui/picture.webp', width: 118, height: 118, fit: BoxFit.contain)),
      ),
    );
  }
}
