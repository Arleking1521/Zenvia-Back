import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/legal_repository.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../widgets/app_text_field.dart';
import '../widgets/magic_ui.dart';
import 'legal_document_screen.dart';

class ParentRegisterScreen extends StatefulWidget {
  final AuthRepository authRepository;
  final LegalRepository legalRepository;
  const ParentRegisterScreen({
    super.key,
    required this.authRepository,
    required this.legalRepository,
  });
  @override
  State<ParentRegisterScreen> createState() => _ParentRegisterScreenState();
}

class _ParentRegisterScreenState extends State<ParentRegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _legalAccepted = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _password.dispose(); _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_legalAccepted) {
      setState(() => _error = context.tr('mustAcceptLegalDocuments'));
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = context.tr('passwordsDoNotMatch'));
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await widget.authRepository.register(
        parentName: _name.text,
        email: _email.text,
        password: _password.text,
        passwordConfirm: _confirm.text,
        acceptPrivacyPolicy: _legalAccepted,
        acceptTermsOfUse: _legalAccepted,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openLegal(String type) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocumentScreen(
          repository: widget.legalRepository,
          type: type,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _RegistrationCloudBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Row(
                children: [
                  IconButton.filled(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
                  const SizedBox(width: 10),
                  Text(context.tr('newFamily'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.deepBlue)),
                ],
              ),
              const SizedBox(height: 16),
              const ZenviaLogo(scale: .7),
              const SizedBox(height: 18),
              MagicCard(
                child: Column(
                  children: [
                    AppTextField(controller: _name, label: context.tr('parentName'), hint: 'Наргиз'),
                    const SizedBox(height: 12),
                    AppTextField(controller: _email, label: 'Email', hint: 'parent@example.com', keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 12),
                    AppTextField(controller: _password, label: context.tr('password'), hint: context.tr('min6'), obscure: true),
                    const SizedBox(height: 12),
                    AppTextField(controller: _confirm, label: context.tr('confirmPassword'), hint: context.tr('repeatPassword'), obscure: true),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .58),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _legalAccepted
                              ? AppColors.primary.withValues(alpha: .45)
                              : AppColors.deepBlue.withValues(alpha: .14),
                        ),
                      ),
                      child: CheckboxListTile(
                        value: _legalAccepted,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        activeColor: AppColors.primary,
                        onChanged: _loading
                            ? null
                            : (value) {
                                setState(() {
                                  _legalAccepted = value ?? false;
                                  if (_legalAccepted &&
                                      _error == context.tr('mustAcceptLegalDocuments')) {
                                    _error = null;
                                  }
                                });
                              },
                        title: Text(
                          context.tr('acceptLegalDocuments'),
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => _openLegal('privacy'),
                          child: Text(context.tr('privacyPolicy')),
                        ),
                        TextButton(
                          onPressed: () => _openLegal('terms'),
                          child: Text(context.tr('termsOfUse')),
                        ),
                      ],
                    ),
                    Text(
                      context.tr('legalDocumentsAvailable'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: MagicPrimaryButton(
                        label: _loading
                            ? context.tr('creating')
                            : context.tr('createAccount'),
                        icon: Icons.favorite_rounded,
                        onPressed: (_loading || !_legalAccepted) ? null : _submit,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegistrationCloudBackground extends StatelessWidget {
  final Widget child;

  const _RegistrationCloudBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Image(
          image: AssetImage('assets/images/home_language_bg.webp'),
          fit: BoxFit.cover,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: .10),
                Colors.white.withValues(alpha: .28),
                Colors.white.withValues(alpha: .18),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

