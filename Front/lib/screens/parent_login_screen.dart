import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/legal_repository.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../widgets/app_text_field.dart';
import '../widgets/magic_ui.dart';
import 'parent_register_screen.dart';
import 'legal_document_screen.dart';

class ParentLoginScreen extends StatefulWidget {
  final AuthRepository authRepository;
  final LegalRepository legalRepository;
  final VoidCallback onLoggedIn;
  const ParentLoginScreen({
    super.key,
    required this.authRepository,
    required this.legalRepository,
    required this.onLoggedIn,
  });
  @override
  State<ParentLoginScreen> createState() => _ParentLoginScreenState();
}

class _ParentLoginScreenState extends State<ParentLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = context.tr('enterEmailPassword'));
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await widget.authRepository.login(email: _email.text, password: _password.text);
      if (mounted) widget.onLoggedIn();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ParentRegisterScreen(
          authRepository: widget.authRepository,
          legalRepository: widget.legalRepository,
        ),
      ),
    );
    if (success == true && mounted) widget.onLoggedIn();
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
      body: _LoginCloudBackground(
        light: false,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  children: [
                    const ZenviaLogo(scale: .9),
                    const SizedBox(height: 14),
                    const DragonImage(asset: 'assets/images/dragon_hero.webp', height: 220),
                    const SizedBox(height: 14),
                    MagicCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(context.tr('parentLoginTitle'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.deepBlue)),
                          const SizedBox(height: 6),
                          Text(context.tr('parentLoginSubtitle'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                          const SizedBox(height: 20),
                          AppTextField(controller: _email, label: 'Email', hint: 'parent@example.com', keyboardType: TextInputType.emailAddress),
                          const SizedBox(height: 12),
                          AppTextField(controller: _password, label: context.tr('password'), hint: context.tr('enterPassword'), obscure: true),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                          ],
                          const SizedBox(height: 18),
                          MagicPrimaryButton(label: _loading ? context.tr('loggingIn') : context.tr('login'), icon: Icons.login_rounded, onPressed: _loading ? null : _submit),
                          const SizedBox(height: 8),
                          TextButton(onPressed: _loading ? null : _register, child: Text(context.tr('createParentAccount'))),
                          const Divider(height: 22),
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

class _LoginCloudBackground extends StatelessWidget {
  final Widget child;
  final bool light;

  const _LoginCloudBackground({
    required this.child,
    this.light = true,
  });

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
                Colors.white.withValues(alpha: .08),
                Colors.white.withValues(alpha: .16),
                const Color(0xFFF3FFF1).withValues(alpha: .22),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

