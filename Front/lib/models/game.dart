import 'language.dart';

enum GameType {
  imageChoice,
  wordChoice,
  audioChoice,
  matching,
}

extension GameTypeX on GameType {
  String get apiCode {
    switch (this) {
      case GameType.imageChoice:
        return 'image_choice';
      case GameType.wordChoice:
        return 'word_choice';
      case GameType.audioChoice:
        return 'audio_choice';
      case GameType.matching:
        return 'matching';
    }
  }

  String get title {
    switch (this) {
      case GameType.imageChoice:
        return 'Выбери картинку';
      case GameType.wordChoice:
        return 'Выбери слово';
      case GameType.audioChoice:
        return 'Прослушай и выбери';
      case GameType.matching:
        return 'Найди пару';
    }
  }

  String get assetPath {
    switch (this) {
      case GameType.imageChoice:
        return 'assets/images/ui/game_choose_picture.webp';
      case GameType.wordChoice:
        return 'assets/images/ui/book.webp';
      case GameType.audioChoice:
        return 'assets/images/ui/game_listen_choose.webp';
      case GameType.matching:
        return 'assets/images/ui/game_find_pair.webp';
    }
  }

  static GameType fromApiCode(String? value) {
    switch (value) {
      case 'image_choice':
        return GameType.imageChoice;
      case 'audio_choice':
        return GameType.audioChoice;
      case 'matching':
        return GameType.matching;
      case 'word_choice':
      default:
        return GameType.wordChoice;
    }
  }
}

class GameSessionData {
  final int id;
  final GameType gameType;
  final String languageCode;
  final int topicId;
  final int questionCount;
  final int roundsAnswered;
  final int correctCount;
  final int wrongCount;
  final int xpEarned;
  final bool finished;

  const GameSessionData({
    required this.id,
    required this.gameType,
    required this.languageCode,
    required this.topicId,
    required this.questionCount,
    required this.roundsAnswered,
    required this.correctCount,
    required this.wrongCount,
    required this.xpEarned,
    required this.finished,
  });
}

class GamePrompt {
  final String kind;
  final String? text;
  final String? transcription;
  final String? imageUrl;
  final String? audioUrl;

  const GamePrompt({
    required this.kind,
    this.text,
    this.transcription,
    this.imageUrl,
    this.audioUrl,
  });
}

class GameOption {
  final int id;
  final String? text;
  final String? transcription;
  final String? imageUrl;

  const GameOption({
    required this.id,
    this.text,
    this.transcription,
    this.imageUrl,
  });
}

class GameQuestionData {
  final int id;
  final int sequence;
  final int total;
  final GameType gameType;
  final GamePrompt? prompt;
  final List<GameOption> options;
  final List<GameOption> left;
  final List<GameOption> right;

  const GameQuestionData({
    required this.id,
    required this.sequence,
    required this.total,
    required this.gameType,
    this.prompt,
    this.options = const [],
    this.left = const [],
    this.right = const [],
  });
}

class GameNextResult {
  final bool complete;
  final GameQuestionData? question;

  const GameNextResult({
    required this.complete,
    this.question,
  });
}

class PairAnswerResult {
  final int conceptId;
  final int wordId;
  final int correctWordId;
  final bool correct;

  const PairAnswerResult({
    required this.conceptId,
    required this.wordId,
    required this.correctWordId,
    required this.correct,
  });
}

class GameAnswerResult {
  final bool correct;
  final int correctItems;
  final int wrongItems;
  final int? correctAnswerId;
  final List<PairAnswerResult> pairResults;
  final GameSessionData session;

  const GameAnswerResult({
    required this.correct,
    required this.correctItems,
    required this.wrongItems,
    required this.session,
    this.correctAnswerId,
    this.pairResults = const [],
  });
}

class GameFinishResult {
  final GameSessionData session;
  final int totalXp;
  final int xpRequested;
  final int xpGranted;
  final int dailyXp;
  final int dailyXpLimit;
  final int dailyXpRemaining;
  final bool dailyLimitReached;

  const GameFinishResult({
    required this.session,
    required this.totalXp,
    required this.xpRequested,
    required this.xpGranted,
    required this.dailyXp,
    required this.dailyXpLimit,
    required this.dailyXpRemaining,
    required this.dailyLimitReached,
  });

  double get dailyProgress {
    if (dailyXpLimit <= 0) return 1;
    return (dailyXp / dailyXpLimit).clamp(0.0, 1.0).toDouble();
  }
}

class GameStartRequest {
  final int topicId;
  final AppLanguage language;
  final GameType gameType;
  final int questionCount;

  const GameStartRequest({
    required this.topicId,
    required this.language,
    required this.gameType,
    required this.questionCount,
  });
}
