import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/parent_repository.dart';
import '../data/legal_repository.dart';
import '../l10n/app_strings.dart';
import '../models/parent_account.dart';
import '../services/app_locale_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_text_field.dart';
import '../widgets/parent_pin_dialog.dart';
import '../widgets/magic_ui.dart';
import 'legal_document_screen.dart';

class ParentSettingsScreen extends StatefulWidget {
  final AuthRepository authRepository;
  final ParentRepository parentRepository;
  final LegalRepository legalRepository;

  const ParentSettingsScreen({
    super.key,
    required this.authRepository,
    required this.parentRepository,
    required this.legalRepository,
  });

  @override
  State<ParentSettingsScreen> createState() => _ParentSettingsScreenState();
}

class _ParentSettingsScreenState extends State<ParentSettingsScreen> {
  late Future<ParentAccount> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.authRepository.getParent();
  }

  Future<void> _changeName(ParentAccount parent) async {
    final controller = TextEditingController(text: parent.firstName);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('parentName')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: context.tr('name')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.tr('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().length < 2) return;
    try {
      await widget.authRepository.updateParentName(value);
      if (mounted) {
        setState(() {
          _future = widget.authRepository.getParent();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _changeInterfaceLanguage(ParentAccount parent) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                child: Text(
                  sheetContext.tr('interfaceLanguage'),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepBlue,
                  ),
                ),
              ),
              for (final code in const ['ru', 'kk', 'en', 'zh'])
                RadioListTile<String>(
                  value: code,
                  groupValue: parent.interfaceLanguage,
                  title: Text(AppStrings.languageName(sheetContext, code)),
                  secondary: Text(
                    switch (code) {
                      'ru' => 'RU',
                      'kk' => 'KZ',
                      'en' => 'EN',
                      _ => '中',
                    },
                    style: const TextStyle(fontSize: 26),
                  ),
                  onChanged: (value) => Navigator.pop(sheetContext, value),
                ),
            ],
          ),
        ),
      ),
    );

    if (selected == null || selected == parent.interfaceLanguage) return;

    try {
      final updated = await widget.authRepository
          .updateParentInterfaceLanguage(selected);
      appLocaleController.setCode(updated.interfaceLanguage);
      if (!mounted) return;
      setState(() {
        _future = Future.value(updated);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _changePassword() async {
    final old = TextEditingController();
    final fresh = TextEditingController();
    final confirm = TextEditingController();
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('changePassword')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  controller: old,
                  label: context.tr('currentPassword'),
                  hint: context.tr('enterPassword'),
                  obscure: true,
                ),
                const SizedBox(height: 10),
                AppTextField(
                  controller: fresh,
                  label: context.tr('newPassword'),
                  hint: context.tr('min6'),
                  obscure: true,
                ),
                const SizedBox(height: 10),
                AppTextField(
                  controller: confirm,
                  label: context.tr('confirmation'),
                  hint: context.tr('repeatPassword'),
                  obscure: true,
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                if (fresh.text != confirm.text) {
                  setDialogState(() => error = context.tr('passwordMismatch'));
                  return;
                }
                try {
                  await widget.authRepository.changePassword(
                    oldPassword: old.text,
                    newPassword: fresh.text,
                    newPasswordConfirm: confirm.text,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (e) {
                  setDialogState(() => error = e.toString());
                }
              },
              child: Text(context.tr('change')),
            ),
          ],
        ),
      ),
    );
    old.dispose();
    fresh.dispose();
    confirm.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('passwordChanged'))),
      );
    }
  }

  Future<void> _changeParentPin() async {
    try {
      final hasPin = await widget.parentRepository.hasParentPin();
      if (!mounted) return;
      final saved = await showParentPinSetupDialog(
        context: context,
        repository: widget.parentRepository,
        changing: hasPin,
      );
      if (saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(hasPin ? 'parentPinChanged' : 'parentPinCreated'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _openLegalDocument(String type) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocumentScreen(
          repository: widget.legalRepository,
          type: type,
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final password = TextEditingController();
    bool understood = false;
    bool deleting = false;
    String? error;

    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red),
              const SizedBox(width: 10),
              Expanded(child: Text(context.tr('deleteAccountTitle'))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('deleteAccountWarning'),
                  style: const TextStyle(height: 1.4),
                ),
                const SizedBox(height: 14),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.red,
                  value: understood,
                  onChanged: deleting
                      ? null
                      : (value) => setDialogState(
                            () => understood = value ?? false,
                          ),
                  title: Text(
                    context.tr('deleteAccountUnderstand'),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 8),
                AppTextField(
                  controller: password,
                  label: context.tr('parentPassword'),
                  hint: context.tr('deleteAccountPasswordHint'),
                  obscure: true,
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: deleting
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: (!understood || deleting)
                  ? null
                  : () async {
                      if (password.text.isEmpty) {
                        setDialogState(
                          () => error = context.tr('enterParentPassword'),
                        );
                        return;
                      }

                      setDialogState(() {
                        deleting = true;
                        error = null;
                      });

                      try {
                        await widget.authRepository.deleteAccount(
                          password: password.text,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (e) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          deleting = false;
                          error = e.toString() == 'invalid_password'
                              ? context.tr('deleteAccountWrongPassword')
                              : context.tr('deleteAccountFailed');
                        });
                      }
                    },
              child: deleting
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(context.tr('deletingAccount')),
                      ],
                    )
                  : Text(context.tr('deleteAccountAction')),
            ),
          ],
        ),
      ),
    );

    // showDialog() завершается сразу после pop(), но route диалога ещё некоторое
    // время участвует в reverse-анимации. Нельзя тут же удалять родительский
    // экран настроек: это может привести к framework assertion
    // `_dependents.isEmpty`. Даём диалогу полностью выйти из дерева.
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 420));

    password.dispose();

    if (deleted == true && mounted) {
      // Возвращаем ParentDashboard признак завершённой сессии. Сам dashboard
      // покажет Login локально, не заставляя корневой AuthGate перестраивать
      // всё приложение одновременно с удалением route настроек.
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _logout() async {
    await widget.authRepository.logout();
    if (!mounted) return;
    // Та же безопасная схема используется для обычного выхода.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(context.tr('parentSettings'))),
      body: FutureBuilder<ParentAccount>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ZenviaLoadingScreen();
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final parent = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                  title: Text(parent.firstName),
                  subtitle: Text(parent.email),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(Icons.translate_rounded),
                title: Text(context.tr('interfaceLanguage')),
                subtitle: Text(AppStrings.languageName(
                  context,
                  parent.interfaceLanguage,
                )),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _changeInterfaceLanguage(parent),
              ),
              const SizedBox(height: 8),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(Icons.edit_rounded),
                title: Text(context.tr('changeName')),
                onTap: () => _changeName(parent),
              ),
              const SizedBox(height: 8),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(Icons.lock_reset_rounded),
                title: Text(context.tr('changePassword')),
                onTap: _changePassword,
              ),
              const SizedBox(height: 8),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(Icons.lock_rounded),
                title: Text(context.tr('parentPin')),
                subtitle: Text(context.tr('parentPinProtection')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _changeParentPin,
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  context.tr('privacyAndDocuments'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepBlue,
                  ),
                ),
              ),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(context.tr('privacyPolicy')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openLegalDocument('privacy'),
              ),
              const SizedBox(height: 8),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(Icons.description_outlined),
                title: Text(context.tr('termsOfUse')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openLegalDocument('terms'),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  context.tr('accountManagement'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepBlue,
                  ),
                ),
              ),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.red.withValues(alpha: .18)),
                ),
                leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                title: Text(
                  context.tr('deleteAccount'),
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(context.tr('deleteAccountHint')),
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.red),
                onTap: _deleteAccount,
              ),
              const SizedBox(height: 20),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(Icons.logout_rounded, color: Colors.red),
                title: Text(
                  context.tr('logout'),
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: _logout,
              ),
            ],
          );
        },
      ),
    );
  }
}
