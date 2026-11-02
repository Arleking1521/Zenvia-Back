import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../data/game_repository.dart';
import '../models/game.dart';
import '../l10n/app_strings.dart';
import '../services/audio_settings_service.dart';
import '../services/background_music_service.dart';
import '../theme/app_colors.dart';
import '../widgets/magic_ui.dart';
import 'game_result_screen.dart';

class GamePlayScreen extends StatefulWidget {
  final GameRepository repository;
  final GameSessionData session;
  final String topicTitle;

  const GamePlayScreen({
    super.key,
    required this.repository,
    required this.session,
    required this.topicTitle,
  });

  @override
  State<GamePlayScreen> createState() => _GamePlayScreenState();
}

class _GamePlayScreenState extends State<GamePlayScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Dio _audioDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 10),
    ),
  );
  final Map<String, Uint8List> _audioCache = <String, Uint8List>{};
  final Object _musicSilenceToken = Object();

  GameQuestionData? _question;
  GameAnswerResult? _answerResult;
  bool _loading = true;
  bool _sending = false;
  bool _loadingAudio = false;
  bool _playingAudio = false;
  String? _currentAudioUrl;
  int? _selectedAnswerId;
  final Map<int, int> _matchingPairs = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    BackgroundMusicService.instance.silence(_musicSilenceToken);
    _loadNext();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    BackgroundMusicService.instance.unsilence(_musicSilenceToken);
    super.dispose();
  }

  Future<void> _loadNext() async {
    await _audioPlayer.stop();
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _question = null;
      _answerResult = null;
      _selectedAnswerId = null;
      _matchingPairs.clear();
      _loadingAudio = false;
      _playingAudio = false;
      _currentAudioUrl = null;
    });

    try {
      final next = await widget.repository.getNextQuestion(widget.session.id);
      if (!mounted) return;
      if (next.complete) {
        await _finish();
        return;
      }
      final loadedQuestion = next.question;
      setState(() {
        _question = loadedQuestion;
        _loading = false;
      });

      // Автоозвучка учебных заданий: ребёнок может ещё не уметь читать.
      // Сразу произносим слово в трёх играх, где аудио помогает понять задание.
      final autoPlayGame = loadedQuestion?.gameType == GameType.imageChoice ||
          loadedQuestion?.gameType == GameType.wordChoice ||
          loadedQuestion?.gameType == GameType.audioChoice;
      final shouldAutoPlay = autoPlayGame &&
          (loadedQuestion?.prompt?.audioUrl ?? '').trim().isNotEmpty;
      if (shouldAutoPlay) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _question?.id != loadedQuestion?.id) return;
          _playAudio(restart: true, showError: false);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submitSingle(int answerId) async {
    final question = _question;
    if (question == null || _sending || _answerResult != null) return;
    setState(() {
      _selectedAnswerId = answerId;
      _sending = true;
    });
    try {
      final result = await widget.repository.answerSingle(
        sessionId: widget.session.id,
        questionId: question.id,
        answerId: answerId,
      );
      if (!mounted) return;
      setState(() => _answerResult = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submitMatching() async {
    final question = _question;
    if (question == null || _sending || _answerResult != null) return;
    if (_matchingPairs.length != question.left.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('connectAllPairsFirst'))),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final result = await widget.repository.answerMatching(
        sessionId: widget.session.id,
        questionId: question.id,
        pairs: Map<int, int>.from(_matchingPairs),
      );
      if (!mounted) return;
      setState(() => _answerResult = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<Uint8List> _loadAudioBytes(String url) async {
    final cached = _audioCache[url];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final response = await _audioDio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        headers: const {
          'Accept': 'audio/mpeg,audio/*;q=0.9,*/*;q=0.8',
        },
      ),
    );

    final raw = response.data;
    if (raw == null || raw.isEmpty) {
      throw StateError('Сервер вернул пустой аудиофайл');
    }

    final bytes = Uint8List.fromList(raw);
    _audioCache[url] = bytes;
    return bytes;
  }

  Future<void> _playAudio({
    bool restart = false,
    bool showError = true,
  }) async {
    final url = _question?.prompt?.audioUrl?.trim();
    if (url == null || url.isEmpty || _loadingAudio) return;

    try {
      // Для обычного аудио-задания повторный тап оставляет прежнее
      // поведение «остановить». Для слова в «Выбери картинку»
      // restart=true всегда запускает произношение заново с начала.
      if (!restart && _playingAudio && _currentAudioUrl == url) {
        await _audioPlayer.stop();
        if (!mounted) return;
        setState(() {
          _playingAudio = false;
          _currentAudioUrl = null;
        });
        return;
      }

      setState(() {
        _loadingAudio = true;
      });

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
      await _audioPlayer.play(
        BytesSource(
          bytes,
          mimeType: mimeType,
        ),
        volume: AudioSettingsService.instance.voiceVolume,
      );

      if (!mounted) return;
      setState(() {
        _loadingAudio = false;
        _playingAudio = true;
        _currentAudioUrl = url;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAudio = false;
        _playingAudio = false;
        _currentAudioUrl = null;
      });

      final status = e.response?.statusCode;
      final message = status == null
          ? 'Не удалось скачать аудио с сервера'
          : 'Сервер не отдал аудио (HTTP $status)';
      if (showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAudio = false;
        _playingAudio = false;
        _currentAudioUrl = null;
      });
      if (showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось воспроизвести аудио: $e')),
        );
      }
    }
  }

  Future<void> _finish() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final result = await widget.repository.finishGame(widget.session.id);
      if (!mounted) return;

      Navigator.of(context).pushReplacement<bool, bool>(
        MaterialPageRoute<bool>(
          builder: (_) => GameResultScreen(
            result: result,
            topicTitle: widget.topicTitle,
          ),
        ),
        result: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _LearningCloudBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                child: Row(
                  children: [
                    Material(
                      color: Colors.white.withValues(alpha: .95),
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.deepBlue),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.topicTitle,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 21),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : _error != null
                        ? _ErrorView(message: _error!, onRetry: _loadNext)
                        : _buildQuestion(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    final question = _question;
    if (question == null) {
      return Center(child: Text(context.tr('noQuestion')));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: question.total == 0
                        ? 0
                        : question.sequence / question.total,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${question.sequence}/${question.total}',
                style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: MagicCard(
              child: question.gameType == GameType.matching
                  ? _buildMatching(question)
                  : _buildSingleChoice(question),
            ),
          ),
        ),
        if (_answerResult != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loadNext,
                child: Text(
                  question.sequence >= question.total ? context.tr('finish') : context.tr('next'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSingleChoice(GameQuestionData question) {
    return Column(
      children: [
        Text(
          _instruction(context, question.gameType),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 18),
        _buildPrompt(question),
        const SizedBox(height: 22),
        if (question.gameType == GameType.wordChoice)
          ...question.options.map(_wordOption)
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.05,
            ),
            itemCount: question.options.length,
            itemBuilder: (_, index) => _imageOption(question.options[index]),
          ),
        if (_sending) ...[
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
        ],
        if (_answerResult != null) ...[
          const SizedBox(height: 18),
          _FeedbackBanner(result: _answerResult!),
        ],
      ],
    );
  }

  Widget _buildPrompt(GameQuestionData question) {
    final prompt = question.prompt;
    if (prompt == null) return const SizedBox.shrink();
    switch (prompt.kind) {
      case 'image':
        final canRepeatAudio =
            question.gameType == GameType.wordChoice &&
            (prompt.audioUrl ?? '').trim().isNotEmpty;

        if (!canRepeatAudio) {
          return _NetworkPicture(url: prompt.imageUrl, size: 180);
        }

        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            onTap: !_loadingAudio
                ? () => _playAudio(restart: true)
                : null,
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      _NetworkPicture(url: prompt.imageUrl, size: 180),
                      Container(
                        margin: const EdgeInsets.all(8),
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primaryDark.withValues(alpha: .92),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _loadingAudio
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.volume_up_rounded,
                                  color: Colors.white,
                                  size: 25,
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('tapPictureHearAgain'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case 'audio':
        final hasAudio = (prompt.audioUrl ?? '').trim().isNotEmpty;
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            onTap: hasAudio && !_loadingAudio
                ? () => _playAudio(restart: true)
                : null,
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  if (_loadingAudio)
                    const SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(strokeWidth: 4),
                    )
                  else
                    Icon(
                      Icons.volume_up_rounded,
                      size: 64,
                      color: hasAudio
                          ? AppColors.primaryDark
                          : AppColors.textMuted,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    !hasAudio
                        ? context.tr('noAudioWord')
                        : _loadingAudio
                            ? context.tr('loadingAudio')
                            : _playingAudio
                                ? context.tr('tapRepeat')
                                : context.tr('tapListenAgain'),
                  ),
                ],
              ),
            ),
          ),
        );
      case 'word':
      default:
        final canRepeatAudio =
            question.gameType == GameType.imageChoice &&
            (prompt.audioUrl ?? '').trim().isNotEmpty;

        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            onTap: canRepeatAudio && !_loadingAudio
                ? () => _playAudio(restart: true)
                : null,
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          prompt.text ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (canRepeatAudio) ...[
                        const SizedBox(width: 10),
                        if (_loadingAudio)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.6),
                          )
                        else
                          const Icon(
                            Icons.volume_up_rounded,
                            color: AppColors.primaryDark,
                            size: 30,
                          ),
                      ],
                    ],
                  ),
                  if ((prompt.transcription ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      prompt.transcription!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                  if (canRepeatAudio) ...[
                    const SizedBox(height: 8),
                    Text(
                      context.tr('tapWordHearAgain'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
    }
  }

  Widget _wordOption(GameOption option) {
    final state = _singleOptionState(option.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: state.background,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: _answerResult == null && !_sending
              ? () => _submitSingle(option.id)
              : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: state.border, width: 2),
            ),
            child: Column(
              children: [
                Text(
                  option.text ?? '',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((option.transcription ?? '').isNotEmpty)
                  Text(
                    option.transcription!,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _imageOption(GameOption option) {
    final state = _singleOptionState(option.id);
    return Material(
      color: state.background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: _answerResult == null && !_sending
            ? () => _submitSingle(option.id)
            : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: state.border, width: 2),
          ),
          child: _NetworkPicture(url: option.imageUrl, size: double.infinity),
        ),
      ),
    );
  }

  _OptionVisual _singleOptionState(int id) {
    const neutral = _OptionVisual(Colors.white, AppColors.trackGrey);
    final result = _answerResult;
    if (result == null) {
      if (_selectedAnswerId == id) {
        return const _OptionVisual(
          AppColors.bottomNavSelectedBg,
          AppColors.primaryDark,
        );
      }
      return neutral;
    }

    if (result.correctAnswerId == id) {
      return const _OptionVisual(Color(0xFFE1F5E1), AppColors.primary);
    }
    if (_selectedAnswerId == id && !result.correct) {
      return const _OptionVisual(Color(0xFFFFE7E7), AppColors.danger);
    }
    return neutral;
  }

  Widget _buildMatching(GameQuestionData question) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('findPair'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('dragWordPicture'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 18),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: .88,
          ),
          itemCount: question.left.length,
          itemBuilder: (_, index) {
            final concept = question.left[index];
            final assignedWordId = _matchingPairs[concept.id];
            final assigned = _findOption(question.right, assignedWordId);
            final result = _pairResult(concept.id);

            Color border = assigned == null
                ? AppColors.trackGrey
                : AppColors.accentBlue;
            Color background = Colors.white;

            if (result != null) {
              border = result.correct ? AppColors.primary : AppColors.danger;
              background = result.correct
                  ? const Color(0xFFF0FFF2)
                  : const Color(0xFFFFF2F2);
            }

            return DragTarget<int>(
              onWillAcceptWithDetails: (_) => _answerResult == null,
              onAcceptWithDetails: (details) {
                if (_answerResult != null) return;
                final wordId = details.data;
                setState(() {
                  // Одно слово может принадлежать только одной картинке.
                  _matchingPairs.removeWhere(
                    (conceptId, existingWordId) => existingWordId == wordId,
                  );
                  _matchingPairs[concept.id] = wordId;
                });
              },
              builder: (context, candidateData, rejectedData) {
                final hovering = candidateData.isNotEmpty;
                final activeBorder = hovering && _answerResult == null
                    ? AppColors.gold
                    : border;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  transform: Matrix4.identity()..scale(hovering ? 1.025 : 1.0),
                  transformAlignment: Alignment.center,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hovering
                        ? const Color(0xFFFFF8D9)
                        : background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: activeBorder,
                      width: hovering ? 3 : 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: hovering ? .12 : .06),
                        blurRadius: hovering ? 14 : 8,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: _NetworkPicture(
                          url: concept.imageUrl,
                          size: double.infinity,
                        ),
                      ),
                      const SizedBox(height: 7),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: assigned == null
                            ? Container(
                                key: ValueKey('empty-${concept.id}'),
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F8),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.trackGrey,
                                  ),
                                ),
                                child: Text(
                                  context.tr('dragHere'),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              )
                            : Container(
                                key: ValueKey('word-${concept.id}-${assigned.id}'),
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: result == null
                                      ? AppColors.bottomNavSelectedBg
                                      : result.correct
                                          ? const Color(0xFFE1F5E1)
                                          : const Color(0xFFFFE7E7),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (result != null) ...[
                                      result.correct
                                          ? Image.asset(
                                              'assets/images/correct_star.webp',
                                              width: 16,
                                              height: 16,
                                              fit: BoxFit.contain,
                                            )
                                          : const Icon(
                                              Icons.cancel_rounded,
                                              size: 16,
                                              color: AppColors.danger,
                                            ),
                                      const SizedBox(width: 4),
                                    ],
                                    Flexible(
                                      child: Text(
                                        assigned.text ?? '',
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary,
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
            );
          },
        ),
        const SizedBox(height: 18),
        if (_answerResult == null) ...[
          Text(
            context.tr('words'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: question.right.map((word) {
              final used = _matchingPairs.values.contains(word.id);
              return _DraggableWord(
                word: word,
                used: used,
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _sending || _matchingPairs.length != question.left.length
                ? null
                : _submitMatching,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Image.asset(
                    'assets/images/correct_star.webp',
                    width: 18,
                    height: 18,
                    fit: BoxFit.contain,
                  ),
            label: Text(
              _matchingPairs.length == question.left.length
                  ? context.tr('check')
                  : context.tr('makeAllPairs'),
            ),
          ),
        ] else ...[
          _FeedbackBanner(result: _answerResult!),
        ],
      ],
    );
  }

  GameOption? _findOption(List<GameOption> options, int? id) {
    if (id == null) return null;
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }

  PairAnswerResult? _pairResult(int conceptId) {
    final rows = _answerResult?.pairResults ?? const [];
    for (final row in rows) {
      if (row.conceptId == conceptId) return row;
    }
    return null;
  }

  String _instruction(BuildContext context, GameType type) {
    switch (type) {
      case GameType.imageChoice:
        return context.tr('chooseCorrectPicture');
      case GameType.wordChoice:
        return context.tr('whatPictureCalled');
      case GameType.audioChoice:
        return context.tr('listenChoosePicture');
      case GameType.matching:
        return context.tr('findPair');
    }
  }
}


class _DraggableWord extends StatelessWidget {
  final GameOption word;
  final bool used;

  const _DraggableWord({
    required this.word,
    required this.used,
  });

  @override
  Widget build(BuildContext context) {
    final label = word.text ?? '';

    Widget card({bool dragging = false}) {
      return Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(minWidth: 92),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: dragging
                  ? const [Color(0xFFFFE56A), Color(0xFFFFC83D)]
                  : used
                      ? const [Color(0xFFE8EEF3), Color(0xFFDCE5EC)]
                      : const [Color(0xFFFFFFFF), Color(0xFFF2F8FF)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: dragging
                  ? AppColors.gold
                  : used
                      ? AppColors.trackGrey
                      : AppColors.accentBlue,
              width: 2,
            ),
            boxShadow: dragging
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .20),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.drag_indicator_rounded,
                size: 19,
                color: used ? AppColors.textMuted : AppColors.primaryDark,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: used
                      ? AppColors.textMuted
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Draggable<int>(
      data: word.id,
      maxSimultaneousDrags: 1,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.08,
          child: card(dragging: true),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: .28,
        child: card(),
      ),
      child: card(),
    );
  }
}

class _NetworkPicture extends StatelessWidget {
  final String? url;
  final double size;

  const _NetworkPicture({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return SizedBox(
        width: size.isFinite ? size : null,
        height: size.isFinite ? size : null,
        child: const Center(
          child: Text('🖼️', style: TextStyle(fontSize: 52)),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        url!,
        width: size.isFinite ? size : null,
        height: size.isFinite ? size : null,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
          child: Text('🖼️', style: TextStyle(fontSize: 52)),
        ),
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  final GameAnswerResult result;

  const _FeedbackBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final fullyCorrect = result.correct;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fullyCorrect ? const Color(0xFFE1F5E1) : const Color(0xFFFFE7E7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          fullyCorrect
              ? Image.asset(
                  'assets/images/correct_star.webp',
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                )
              : const Text(
                  '💪',
                  style: TextStyle(fontSize: 24),
                ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fullyCorrect
                  ? context.tr('right')
                  : result.correctItems > 0
                      ? context.tr('resultCorrectWrong', {'correct': result.correctItems, 'wrong': result.wrongItems})
                      : context.tr('tryNextSaved'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 44),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: Text(context.tr('retry'))),
          ],
        ),
      ),
    );
  }
}

class _OptionVisual {
  final Color background;
  final Color border;

  const _OptionVisual(this.background, this.border);
}

class _LearningCloudBackground extends StatelessWidget {
  final Widget child;

  const _LearningCloudBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Image(
          image: AssetImage('assets/images/world_map_sky.webp'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: .04),
                Colors.transparent,
                Colors.white.withValues(alpha: .03),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
