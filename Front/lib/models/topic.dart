import 'package:flutter/material.dart';
import 'language.dart';

class WordItem {
  final String id;
  final Map<AppLanguage, String> translations;
  final Map<AppLanguage, String?> audioUrls;
  final Map<AppLanguage, String?> transcriptions;
  final String? imageUrl;
  final String emoji;

  const WordItem({
    required this.id,
    required this.translations,
    this.audioUrls = const {},
    this.transcriptions = const {},
    this.imageUrl,
    this.emoji = '',
  });

  String translationFor(AppLanguage lang) => translations[lang] ?? '';

  String? audioFor(AppLanguage lang) => audioUrls[lang];

  String? transcriptionFor(AppLanguage lang) => transcriptions[lang];
}

class Topic {
  final String id;
  final int number;
  final String title;
  final String description;
  final String emoji;
  final String? iconUrl;
  final Color color;
  final List<WordItem> words;
  final int learnedCount;
  final Set<String> learnedWordIds;

  const Topic({
    required this.id,
    required this.number,
    required this.title,
    required this.description,
    required this.emoji,
    this.iconUrl,
    required this.color,
    required this.words,
    required this.learnedCount,
    this.learnedWordIds = const <String>{},
  });

  int get totalCount => words.length;
  List<WordItem> get learnedWords => words
      .where((word) => learnedWordIds.contains(word.id))
      .toList(growable: false);
  bool isWordLearned(WordItem word) => learnedWordIds.contains(word.id);
  double get progress => totalCount == 0 ? 0 : learnedCount / totalCount;
  bool get isCompleted => totalCount > 0 && learnedCount >= totalCount;
}
