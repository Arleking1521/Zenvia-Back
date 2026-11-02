import 'package:flutter/material.dart';

import '../data/parent_repository.dart';
import '../l10n/app_strings.dart';
import '../models/child_profile.dart';
import '../models/registration_option.dart';
import '../theme/app_colors.dart';
import '../widgets/app_text_field.dart';
import '../widgets/magic_ui.dart';

class ChildEditorScreen extends StatefulWidget {
  final ParentRepository repository;
  final ChildProfile? child;

  const ChildEditorScreen({super.key, required this.repository, this.child});

  @override
  State<ChildEditorScreen> createState() => _ChildEditorScreenState();
}

class _ChildEditorScreenState extends State<ChildEditorScreen> {
  final _name = TextEditingController();
  late Future<void> _loadFuture;
  List<RegistrationLanguage> _languages = const [];
  List<AvatarOption> _avatars = const [];
  int? _languageId;
  int? _avatarId;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.child != null;

  @override
  void initState() {
    super.initState();
    _name.text = widget.child?.name ?? '';
    _languageId = widget.child?.baseLanguage?.id;
    _avatarId = widget.child?.avatar?.id;
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final data = await Future.wait([
      widget.repository.getLanguages(),
      widget.repository.getAvatars(),
    ]);
    _languages = data[0] as List<RegistrationLanguage>;
    _avatars = data[1] as List<AvatarOption>;
    _languageId ??= _languages.isNotEmpty ? _languages.first.id : null;
    _avatarId ??= _avatars.isNotEmpty ? _avatars.first.id : null;
    if (mounted) {
      await precacheBackendImages(
        context,
        <String?>[
          ..._avatars.map((avatar) => avatar.imageUrl),
          ..._languages.map((language) => language.iconUrl),
        ],
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2 || _languageId == null || _avatarId == null) {
      setState(() => _error = context.tr('fillChildForm'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final child = _editing
          ? await widget.repository.updateChild(
              childId: widget.child!.id,
              name: _name.text,
              baseLanguageId: _languageId,
              avatarId: _avatarId,
            )
          : await widget.repository.createChild(
              name: _name.text,
              baseLanguageId: _languageId!,
              avatarId: _avatarId!,
            );
      if (mounted) Navigator.of(context).pop(child);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: ZenviaLoadingScreen());
        }
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: Text(_editing ? context.tr('childProfile') : context.tr('newChildProfile'))),
          body: snapshot.hasError
              ? Center(child: Text(snapshot.error.toString()))
              : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              AppTextField(controller: _name, label: context.tr('childName'), hint: 'Карим'),
              const SizedBox(height: 20),
              Text(context.tr('baseInterfaceLanguage'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _languages.map((lang) {
                  final selected = lang.id == _languageId;
                  return ChoiceChip(
                    selected: selected,
                    label: Text('${_flag(lang.code)} ${lang.title}'),
                    onSelected: (_) => setState(() => _languageId = lang.id),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Text(context.tr('avatar'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: _avatars.length,
                itemBuilder: (_, index) {
                  final avatar = _avatars[index];
                  final selected = avatar.id == _avatarId;
                  return InkWell(
                    onTap: () => setState(() => _avatarId = avatar.id),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: selected ? AppColors.primary : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: avatar.imageUrl == null
                          ? Center(child: Image.asset('assets/images/dragon_hero.webp', width: 48, height: 48, fit: BoxFit.contain))
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(13),
                              child: Image.network(avatar.imageUrl!, fit: BoxFit.cover),
                            ),
                    ),
                  );
                },
              ),
              if (_avatars.isEmpty)
                Text(context.tr('noAvatarsAdmin'), style: const TextStyle(color: Colors.red)),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _saving || _avatars.isEmpty || _languages.isEmpty ? null : _save,
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_editing ? context.tr('save') : context.tr('createProfileAction')),
              ),
            ],
          ),
        );
      },
    );
  }

  String _flag(String code) {
    switch (code) {
      case 'en': return 'EN';
      case 'kk': return 'KZ';
      case 'zh': return '中';
      case 'ru': return 'RU';
      default: return '•';
    }
  }
}
