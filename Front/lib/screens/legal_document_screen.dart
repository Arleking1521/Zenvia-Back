import 'package:flutter/material.dart';

import '../data/legal_repository.dart';
import '../l10n/app_strings.dart';
import '../models/legal_document.dart';
import '../theme/app_colors.dart';
import '../widgets/magic_ui.dart';

class LegalDocumentScreen extends StatefulWidget {
  final LegalRepository repository;
  final String type;

  const LegalDocumentScreen({
    super.key,
    required this.repository,
    required this.type,
  });

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  Future<LegalDocument>? _future;
  String? _loadedLanguage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final language = Localizations.localeOf(context).languageCode;

    if (_future == null || _loadedLanguage != language) {
      _loadedLanguage = language;
      _future = widget.repository.getDocument(
        type: widget.type,
        language: language,
      );
    }
  }

  void _reload() {
    setState(() {
      _future = widget.repository.getDocument(
        type: widget.type,
        language: _loadedLanguage ?? 'ru',
        forceRefresh: true,
      );
    });
  }

  String _fallbackTitle(BuildContext context) {
    return widget.type == 'terms'
        ? context.tr('termsOfUse')
        : context.tr('privacyPolicy');
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';

    final local = date.toLocal();

    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(local.day)}.${two(local.month)}.${local.year}';
  }

  String _documentText(LegalDocument document) {
    final plainText = document.plainText.trim();
    if (plainText.isNotEmpty) {
      return plainText;
    }

    final html = document.html.trim();
    if (html.isNotEmpty) {
      return _htmlToPlainText(html);
    }

    final sourceUrl = document.sourceFileUrl?.trim();
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      return sourceUrl;
    }

    return '';
  }

  String _htmlToPlainText(String value) {
    var text = value;

    text = text.replaceAll(
      RegExp(
        r'<\s*(br|/p|/div|/li|/h[1-6]|/tr)\s*/?>',
        caseSensitive: false,
      ),
      '\n',
    );

    text = text.replaceAll(
      RegExp(
        r'<\s*li[^>]*>',
        caseSensitive: false,
      ),
      '• ',
    );

    text = text.replaceAll(
      RegExp(
        r'<\s*/?(td|th)[^>]*>',
        caseSensitive: false,
      ),
      '   ',
    );

    text = text.replaceAll(
      RegExp(
        r'<[^>]+>',
        multiLine: true,
        caseSensitive: false,
      ),
      '',
    );

    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    text = text.replaceAll(
      RegExp(r'[ \t]+\n'),
      '\n',
    );

    text = text.replaceAll(
      RegExp(r'\n{3,}'),
      '\n\n',
    );

    return text.trim();
  }

  Widget _documentHeader(
    BuildContext context,
    LegalDocument document,
  ) {
    final effectiveDate = _formatDate(document.effectiveFrom);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          document.title.isEmpty
              ? _fallbackTitle(context)
              : document.title,
          style: const TextStyle(
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w900,
            color: AppColors.deepBlue,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          effectiveDate.isEmpty
              ? context.tr(
                  'legalVersion',
                  {'version': document.version},
                )
              : context.tr(
                  'legalVersionEffective',
                  {
                    'version': document.version,
                    'date': effectiveDate,
                  },
                ),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _documentBody(
    BuildContext context,
    LegalDocument document,
  ) {
    final text = _documentText(document);

    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          40,
        ),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                18,
                20,
                18,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _documentHeader(
                    context,
                    document,
                  ),
                  const Divider(height: 30),
                  if (text.isNotEmpty)
                    SelectableText(
                      text,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.55,
                        color: AppColors.textPrimary,
                      ),
                    )
                  else
                    Text(
                      context.tr('legalNotPublished'),
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView(
    BuildContext context,
    Object error,
  ) {
    final notPublished =
        error is LegalDocumentNotPublishedException;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  notPublished
                      ? Icons.description_outlined
                      : Icons.cloud_off_rounded,
                  size: 48,
                  color: AppColors.deepBlue,
                ),
                const SizedBox(height: 14),
                Text(
                  notPublished
                      ? context.tr('legalNotPublished')
                      : error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                  ),
                ),
                if (!notPublished) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(
                      Icons.refresh_rounded,
                    ),
                    label: Text(
                      context.tr('retry'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _fallbackTitle(context),
        ),
      ),
      body: FutureBuilder<LegalDocument>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState !=
              ConnectionState.done) {
            return const ZenviaLoadingScreen();
          }

          if (snapshot.hasError) {
            return _errorView(
              context,
              snapshot.error!,
            );
          }

          final document = snapshot.data;

          if (document == null) {
            return Center(
              child: Text(
                context.tr('legalNotPublished'),
              ),
            );
          }

          return _documentBody(
            context,
            document,
          );
        },
      ),
    );
  }
}
