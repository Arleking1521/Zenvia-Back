import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/daily_lesson.dart';
import '../l10n/app_strings.dart';
import '../models/language.dart';
import '../models/topic.dart';
import '../services/audio_settings_service.dart';
import '../services/background_music_service.dart';
import '../services/daily_lesson_service.dart';
import '../widgets/magic_ui.dart';

class DailyWordsLessonScreen extends StatefulWidget {
  final Topic topic;
  final AppLanguage language;
  final AppRepository repository;

  const DailyWordsLessonScreen({
    super.key,
    required this.topic,
    required this.language,
    required this.repository,
  });

  @override
  State<DailyWordsLessonScreen> createState() => _DailyWordsLessonScreenState();
}

class _DailyWordsLessonScreenState extends State<DailyWordsLessonScreen> {
  late final DailyLessonService _lessonService;
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
  final Object _musicSilenceToken = Object();

  DailyLessonPlan? _plan;
  String? _dragonUrl;
  int _index = 0;
  bool _loading = true;
  bool _audioLoading = false;
  bool _playing = false;
  bool _nextBusy = false;
  bool _reviewMode = false;
  String? _currentAudioUrl;
  String? _reviewLoadingAudioUrl;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<void>? _completeSubscription;

  @override
  void initState() {
    super.initState();
    BackgroundMusicService.instance.silence(_musicSilenceToken);
    _lessonService = DailyLessonService(widget.repository);
    _stateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
    _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _audioLoading = false;
        _currentAudioUrl = null;
        _reviewLoadingAudioUrl = null;
      });
    });
    _load();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _completeSubscription?.cancel();
    _audioPlayer.dispose();
    BackgroundMusicService.instance.unsilence(_musicSilenceToken);
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        _lessonService.loadPlan(topic: widget.topic, language: widget.language),
        widget.repository.getLevelDragonUrl(),
      ]);
      if (!mounted) return;
      final plan = results[0] as DailyLessonPlan;
      await precacheBackendImages(
        context,
        <String?>[
          results[1] as String?,
          ...plan.words.map((word) => word.imageUrl),
        ],
      );
      if (!mounted) return;
      var index = plan.words.indexWhere((word) => !plan.isWordStudied(word));
      if (index < 0) index = math.max(0, plan.words.length - 1);
      setState(() {
        _plan = plan;
        _dragonUrl = results[1] as String?;
        _index = index;
        _reviewMode = plan.isComplete && plan.words.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('lessonLoadFailed', {'error': e}))),
      );
    }
  }

  Future<Uint8List> _loadAudio(String url) async {
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
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw StateError('Empty audio');
    }
    final bytes = Uint8List.fromList(data);
    _audioCache[url] = bytes;
    return bytes;
  }

  Future<void> _studyCurrentWord() async {
    final plan = _plan;
    if (plan == null || plan.words.isEmpty || _audioLoading) return;
    final word = plan.words[_index];

    final audioUrl = word.audioFor(widget.language)?.trim();
    if (audioUrl == null || audioUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('audioNotAdded')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      if (_playing && _currentAudioUrl == audioUrl) {
        await _audioPlayer.stop();
        if (!mounted) return;
        setState(() {
          _playing = false;
          _audioLoading = false;
          _currentAudioUrl = null;
        });
        return;
      }
      if (mounted) setState(() => _audioLoading = true);
      await _audioPlayer.stop();
      final bytes = await _loadAudio(audioUrl);
      final lower = audioUrl.toLowerCase();
      final mimeType = lower.endsWith('.wav')
          ? 'audio/wav'
          : lower.endsWith('.ogg')
              ? 'audio/ogg'
              : lower.endsWith('.m4a')
                  ? 'audio/mp4'
                  : 'audio/mpeg';
      await AudioSettingsService.instance.load();
      final listenNumber = (_listenCounts[audioUrl] ?? 0) + 1;
      _listenCounts[audioUrl] = listenNumber;
      await _audioPlayer.play(
        BytesSource(bytes, mimeType: mimeType),
        volume: AudioSettingsService.instance.voiceVolume,
      );
      await _audioPlayer.setPlaybackRate(listenNumber.isEven ? 0.72 : 1.0);

      // Only now tell Django that the word was listened to. If audio loading
      // or playback fails, the word stays unfinished and games remain locked.
      final updated = await _lessonService.markStudied(
        topic: widget.topic,
        language: widget.language,
        wordId: word.id,
        lessonId: plan.lessonId,
      );

      if (!mounted) return;
      setState(() {
        _plan = updated;
        _currentAudioUrl = audioUrl;
        _audioLoading = false;
      });
    } catch (_) {
      await _audioPlayer.stop();
      if (!mounted) return;
      setState(() {
        _audioLoading = false;
        _playing = false;
        _currentAudioUrl = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('audioPlayFailed'))),
      );
    }
  }

  Future<void> _playReviewWord(WordItem word) async {
    final audioUrl = word.audioFor(widget.language)?.trim();
    if (audioUrl == null || audioUrl.isEmpty || _audioLoading) {
      if (audioUrl == null || audioUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('audioNotAdded')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      if (_playing && _currentAudioUrl == audioUrl) {
        await _audioPlayer.stop();
        if (!mounted) return;
        setState(() {
          _playing = false;
          _audioLoading = false;
          _currentAudioUrl = null;
          _reviewLoadingAudioUrl = null;
        });
        return;
      }

      setState(() {
        _audioLoading = true;
        _reviewLoadingAudioUrl = audioUrl;
      });
      await _audioPlayer.stop();
      final bytes = await _loadAudio(audioUrl);
      final lower = audioUrl.toLowerCase();
      final mimeType = lower.endsWith('.wav')
          ? 'audio/wav'
          : lower.endsWith('.ogg')
              ? 'audio/ogg'
              : lower.endsWith('.m4a')
                  ? 'audio/mp4'
                  : 'audio/mpeg';

      await AudioSettingsService.instance.load();
      final listenNumber = (_listenCounts[audioUrl] ?? 0) + 1;
      _listenCounts[audioUrl] = listenNumber;
      await _audioPlayer.play(
        BytesSource(bytes, mimeType: mimeType),
        volume: AudioSettingsService.instance.voiceVolume,
      );
      await _audioPlayer.setPlaybackRate(listenNumber.isEven ? 0.72 : 1.0);

      if (!mounted) return;
      setState(() {
        _currentAudioUrl = audioUrl;
        _audioLoading = false;
        _reviewLoadingAudioUrl = null;
      });
    } catch (_) {
      await _audioPlayer.stop();
      if (!mounted) return;
      setState(() {
        _audioLoading = false;
        _playing = false;
        _currentAudioUrl = null;
        _reviewLoadingAudioUrl = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('audioPlayFailed'))),
      );
    }
  }

  Future<void> _next() async {
    if (_nextBusy) return;
    _nextBusy = true;
    try {
      final plan = _plan;
      if (plan == null || plan.words.isEmpty) {
        if (mounted) Navigator.of(context).pop(true);
        return;
      }

      final current = plan.words[_index];
      if (!plan.isWordStudied(current)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('listenFirst')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      await _audioPlayer.stop();
      if (_index < plan.words.length - 1) {
        if (!mounted) return;
        setState(() {
          _index++;
          _playing = false;
          _audioLoading = false;
          _currentAudioUrl = null;
        });
        return;
      }

      final latest = await _lessonService.loadPlan(
        topic: widget.topic,
        language: widget.language,
      );
      if (!mounted) return;
      if (latest.isComplete) {
        setState(() {
          _plan = latest;
          _reviewMode = true;
          _index = math.max(0, latest.words.length - 1);
          _playing = false;
          _audioLoading = false;
          _currentAudioUrl = null;
          _reviewLoadingAudioUrl = null;
        });
      }
    } finally {
      _nextBusy = false;
    }
  }

  Widget _buildReviewScreen(DailyLessonPlan plan) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/daily_words_bg.webp',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF138EDC).withValues(alpha: .08),
                  Colors.white.withValues(alpha: .04),
                  Colors.white.withValues(alpha: .13),
                ],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                final uiScale = math.min(width / 390, height / 820)
                    .clamp(.86, 1.18)
                    .toDouble();

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    14 * uiScale,
                    8 * uiScale,
                    14 * uiScale,
                    12 * uiScale,
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.fromLTRB(
                          10 * uiScale,
                          10 * uiScale,
                          14 * uiScale,
                          12 * uiScale,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF12A8EA), Color(0xFF0879CA)],
                          ),
                          borderRadius: BorderRadius.circular(28 * uiScale),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .35),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF075CA5)
                                  .withValues(alpha: .24),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            _RoundHeaderButton(
                              icon: Icons.arrow_back_rounded,
                              uiScale: uiScale,
                              onTap: () async {
                                await _audioPlayer.stop();
                                if (!mounted) return;
                                setState(() {
                                  _reviewMode = false;
                                  _playing = false;
                                  _audioLoading = false;
                                  _currentAudioUrl = null;
                                  _reviewLoadingAudioUrl = null;
                                });
                              },
                            ),
                            SizedBox(width: 10 * uiScale),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr('reviewWordsToday'),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: (18 * uiScale).clamp(16.0, 22.0),
                                    ),
                                  ),
                                  SizedBox(height: 3 * uiScale),
                                  Text(
                                    context.tr('reviewWordsHint'),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: .92),
                                      fontWeight: FontWeight.w700,
                                      fontSize: (11.5 * uiScale).clamp(10.5, 14.0),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 11 * uiScale,
                                vertical: 7 * uiScale,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .20),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '${plan.words.length}/${plan.words.length}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: (12 * uiScale).clamp(11.0, 14.0),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 12 * uiScale),
                      Expanded(
                        child: ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.symmetric(vertical: 2 * uiScale),
                          itemCount: plan.words.length,
                          separatorBuilder: (_, __) =>
                              SizedBox(height: 9 * uiScale),
                          itemBuilder: (context, index) {
                            final word = plan.words[index];
                            final audioUrl =
                                word.audioFor(widget.language)?.trim();
                            return _ReviewWordCard(
                              word: word,
                              number: index + 1,
                              translation:
                                  word.translationFor(widget.language),
                              transcription:
                                  word.transcriptionFor(widget.language)?.trim(),
                              uiScale: uiScale,
                              loading: audioUrl != null &&
                                  audioUrl.isNotEmpty &&
                                  _audioLoading &&
                                  _reviewLoadingAudioUrl == audioUrl,
                              playing: audioUrl != null &&
                                  audioUrl.isNotEmpty &&
                                  _playing &&
                                  _currentAudioUrl == audioUrl,
                              enabled: audioUrl != null && audioUrl.isNotEmpty,
                              onTap: () => _playReviewWord(word),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 10 * uiScale),
                      _NextButton(
                        uiScale: uiScale,
                        enabled: true,
                        isLast: true,
                        onTap: () async {
                          await _audioPlayer.stop();
                          if (context.mounted) {
                            Navigator.of(context).pop(true);
                          }
                        },
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: ZenviaLoadingScreen());
    }

    final plan = _plan;
    if (plan == null) {
      return Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: _load,
            child: Text(context.tr('retry')),
          ),
        ),
      );
    }

    if (plan.words.isEmpty) {
      return Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/daily_words_bg.webp', fit: BoxFit.cover),
            SafeArea(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/images/correct_star.webp', width: 82, height: 82, fit: BoxFit.contain),
                      const SizedBox(height: 10),
                      Text(
                        context.tr('allWordsOpened'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(context.tr('goToTopic')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_reviewMode && plan.words.isNotEmpty) {
      return _buildReviewScreen(plan);
    }

    final word = plan.words[_index];
    final studied = plan.isWordStudied(word);
    final translation = word.translationFor(widget.language);
    final transcription = word.transcriptionFor(widget.language)?.trim();
    final progress = plan.requiredCount == 0
        ? 1.0
        : (plan.studiedCount / plan.requiredCount).clamp(0.0, 1.0);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/daily_words_bg.webp',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF138EDC).withValues(alpha: .08),
                  Colors.transparent,
                  Colors.white.withValues(alpha: .05),
                ],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                final uiScale = math.min(width / 390, height / 820).clamp(.86, 1.18).toDouble();

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    14 * uiScale,
                    8 * uiScale,
                    14 * uiScale,
                    12 * uiScale,
                  ),
                  child: Column(
                    children: [
                      _LessonHeader(
                        topicTitle: widget.topic.title,
                        progress: progress,
                        studied: plan.studiedCount,
                        total: plan.requiredCount,
                        uiScale: uiScale,
                        audioLoading: _audioLoading,
                        playing: _playing,
                        onBack: () => Navigator.of(context).pop(false),
                        onSound: _studyCurrentWord,
                      ),
                      SizedBox(height: 14 * uiScale),
                      Expanded(
                        child: Center(
                          child: FractionallySizedBox(
                            widthFactor: .94,
                            heightFactor: .86,
                            child: _WordCard(
                              word: word,
                              translation: translation,
                              transcription: transcription,
                              studied: studied,
                              audioLoading: _audioLoading,
                              uiScale: uiScale,
                              onImageTap: _studyCurrentWord,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 10 * uiScale),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: math.min(width * .74, 330.0).toDouble(),
                        padding: EdgeInsets.symmetric(
                          horizontal: 18 * uiScale,
                          vertical: 10 * uiScale,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: studied
                                ? const [Color(0xFFFFE24F), Color(0xFFFFBC28)]
                                : const [Color(0xFFFFFFFF), Color(0xFFEFF8FF)],
                          ),
                          borderRadius: BorderRadius.circular(26 * uiScale),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .10),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Text(
                          studied ? context.tr('repeatWordGreat') : context.tr('tapListen'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xFF173B75),
                            fontWeight: FontWeight.w900,
                            fontSize: (14 * uiScale).clamp(12.0, 17.0),
                          ),
                        ),
                      ),
                      SizedBox(height: 8 * uiScale),
                      _NextButton(
                        uiScale: uiScale,
                        enabled: studied,
                        isLast: _index == plan.words.length - 1,
                        onTap: _next,
                      ),
                      SizedBox(height: 6 * uiScale),
                      SizedBox(
                        height: (150 * uiScale).clamp(126.0, 196.0),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 2 * uiScale),
                            child: _Dragon(
                              url: _dragonUrl,
                              size: (138 * uiScale).clamp(118.0, 188.0),
                            ),
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
  }
}

class _LessonHeader extends StatelessWidget {
  final String topicTitle;
  final double progress;
  final int studied;
  final int total;
  final double uiScale;
  final bool audioLoading;
  final bool playing;
  final VoidCallback onBack;
  final VoidCallback onSound;

  const _LessonHeader({
    required this.topicTitle,
    required this.progress,
    required this.studied,
    required this.total,
    required this.uiScale,
    required this.audioLoading,
    required this.playing,
    required this.onBack,
    required this.onSound,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(10 * uiScale, 10 * uiScale, 10 * uiScale, 11 * uiScale),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF12A8EA), Color(0xFF0879CA)],
        ),
        borderRadius: BorderRadius.circular(28 * uiScale),
        border: Border.all(color: Colors.white.withValues(alpha: .35)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF075CA5).withValues(alpha: .24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _RoundHeaderButton(icon: Icons.arrow_back_rounded, onTap: onBack, uiScale: uiScale),
          SizedBox(width: 9 * uiScale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('fiveWordsTopic', {'topic': topicTitle}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: (13.5 * uiScale).clamp(12.0, 16.0),
                        ),
                      ),
                    ),
                    Text(
                      '$studied/$total',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: (13.5 * uiScale).clamp(12.0, 16.0),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 7 * uiScale),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: (12 * uiScale).clamp(9.0, 14.0),
                    backgroundColor: Colors.white.withValues(alpha: .36),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFFFD54A)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 9 * uiScale),
          Material(
            color: Colors.white.withValues(alpha: .18),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onSound,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 50 * uiScale,
                height: 50 * uiScale,
                child: Center(
                  child: audioLoading
                      ? SizedBox(
                          width: 22 * uiScale,
                          height: 22 * uiScale,
                          child: const CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Icon(
                          playing ? Icons.stop_rounded : Icons.volume_up_rounded,
                          color: Colors.white,
                          size: 29 * uiScale,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundHeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double uiScale;
  const _RoundHeaderButton({required this.icon, required this.onTap, required this.uiScale});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .18),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 45 * uiScale,
          height: 45 * uiScale,
          child: Icon(icon, color: Colors.white, size: 27 * uiScale),
        ),
      ),
    );
  }
}

class _WordCard extends StatelessWidget {
  final WordItem word;
  final String translation;
  final String? transcription;
  final bool studied;
  final bool audioLoading;
  final double uiScale;
  final VoidCallback onImageTap;

  const _WordCard({
    required this.word,
    required this.translation,
    required this.transcription,
    required this.studied,
    required this.audioLoading,
    required this.uiScale,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16 * uiScale, 14 * uiScale, 16 * uiScale, 16 * uiScale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(34 * uiScale),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2266A7).withValues(alpha: .16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: Material(
              color: const Color(0xFFF9FBFF),
              borderRadius: BorderRadius.circular(26 * uiScale),
              child: InkWell(
                onTap: onImageTap,
                borderRadius: BorderRadius.circular(26 * uiScale),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(12 * uiScale),
                      child: _WordImage(word: word),
                    ),
                    Positioned(
                      right: 12 * uiScale,
                      bottom: 12 * uiScale,
                      child: Container(
                        width: 46 * uiScale,
                        height: 46 * uiScale,
                        decoration: BoxDecoration(
                          color: studied ? const Color(0xFF16C667) : const Color(0xFF14A9EA),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .14),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: audioLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                )
                              : Icon(
                                  studied ? Icons.check_rounded : Icons.volume_up_rounded,
                                  color: Colors.white,
                                  size: 26 * uiScale,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: 12 * uiScale),
          Text(
            translation,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF163E80),
              fontSize: (31 * uiScale).clamp(25.0, 37.0),
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          if (transcription != null && transcription!.isNotEmpty) ...[
            SizedBox(height: 6 * uiScale),
            Text(
              transcription!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF667998),
                fontSize: (13 * uiScale).clamp(11.0, 16.0),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewWordCard extends StatelessWidget {
  final WordItem word;
  final int number;
  final String translation;
  final String? transcription;
  final double uiScale;
  final bool loading;
  final bool playing;
  final bool enabled;
  final VoidCallback onTap;

  const _ReviewWordCard({
    required this.word,
    required this.number,
    required this.translation,
    required this.transcription,
    required this.uiScale,
    required this.loading,
    required this.playing,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(24 * uiScale),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(24 * uiScale),
        child: Container(
          padding: EdgeInsets.all(10 * uiScale),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24 * uiScale),
            border: Border.all(
              color: const Color(0xFF8DD7FA).withValues(alpha: .55),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF155B91).withValues(alpha: .10),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 34 * uiScale,
                height: 34 * uiScale,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFD54A),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: TextStyle(
                    color: const Color(0xFF173B75),
                    fontWeight: FontWeight.w900,
                    fontSize: 14 * uiScale,
                  ),
                ),
              ),
              SizedBox(width: 9 * uiScale),
              Container(
                width: 72 * uiScale,
                height: 72 * uiScale,
                padding: EdgeInsets.all(5 * uiScale),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8FB),
                  borderRadius: BorderRadius.circular(18 * uiScale),
                ),
                child: _WordImage(word: word),
              ),
              SizedBox(width: 12 * uiScale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      translation,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFF163E80),
                        fontWeight: FontWeight.w900,
                        fontSize: (20 * uiScale).clamp(17.0, 24.0),
                      ),
                    ),
                    if (transcription != null && transcription!.isNotEmpty) ...[
                      SizedBox(height: 4 * uiScale),
                      Text(
                        transcription!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF667998),
                          fontWeight: FontWeight.w700,
                          fontSize: (12 * uiScale).clamp(11.0, 14.0),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8 * uiScale),
              Container(
                width: 46 * uiScale,
                height: 46 * uiScale,
                decoration: BoxDecoration(
                  color: enabled
                      ? const Color(0xFF12A8EA)
                      : const Color(0xFFCBD6DE),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: loading
                      ? SizedBox(
                          width: 20 * uiScale,
                          height: 20 * uiScale,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2.3,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          playing
                              ? Icons.stop_rounded
                              : Icons.volume_up_rounded,
                          color: Colors.white,
                          size: 25 * uiScale,
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

class _WordImage extends StatelessWidget {
  final WordItem word;
  const _WordImage({required this.word});

  @override
  Widget build(BuildContext context) {
    final url = word.imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return Center(child: Image.asset('assets/images/ui/picture.webp', width: 132, height: 132, fit: BoxFit.contain));
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Center(
        child: Image.asset('assets/images/ui/picture.webp', width: 122, height: 122, fit: BoxFit.contain),
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  final double uiScale;
  final bool enabled;
  final bool isLast;
  final VoidCallback onTap;

  const _NextButton({
    required this.uiScale,
    required this.enabled,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = enabled
        ? const [Color(0xFF28D76B), Color(0xFF0FB85D)]
        : const [Color(0xFFC2D0DB), Color(0xFFAFBECA)];

    return Opacity(
      opacity: enabled ? 1 : .92,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(28 * uiScale),
          boxShadow: [
            BoxShadow(
              color: (enabled ? const Color(0xFF15B85F) : const Color(0xFF8AA0B3)).withValues(alpha: .34),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(color: Colors.white.withValues(alpha: .38), width: 1.4),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(28 * uiScale),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 22 * uiScale,
                vertical: 15 * uiScale,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34 * uiScale,
                    height: 34 * uiScale,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isLast ? Icons.star_rounded : Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 21 * uiScale,
                    ),
                  ),
                  SizedBox(width: 10 * uiScale),
                  Text(
                    isLast ? context.tr('finishLesson') : context.tr('next'),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: (17 * uiScale).clamp(15.0, 20.0),
                      letterSpacing: .2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dragon extends StatelessWidget {
  final String? url;
  final double size;

  const _Dragon({required this.url, this.size = 120});

  @override
  Widget build(BuildContext context) {
    final value = url?.trim();
    if (value == null || value.isEmpty) {
      return SizedBox(width: size, height: size);
    }
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        value,
        fit: BoxFit.contain,
        alignment: Alignment.bottomCenter,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
      ),
    );
  }
}
