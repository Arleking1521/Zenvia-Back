import 'package:flutter/material.dart';

import '../data/parent_repository.dart';
import '../models/child_profile.dart';
import '../l10n/app_strings.dart';
import '../services/audio_settings_service.dart';
import '../theme/app_colors.dart';
import '../widgets/magic_ui.dart';
import 'child_editor_screen.dart';

class ChildSettingsScreen extends StatefulWidget {
  final ParentRepository repository;
  final int childId;
  final Future<bool> Function() requestParentAccess;

  const ChildSettingsScreen({
    super.key,
    required this.repository,
    required this.childId,
    required this.requestParentAccess,
  });

  @override
  State<ChildSettingsScreen> createState() => _ChildSettingsScreenState();
}

class _ChildSettingsScreenState extends State<ChildSettingsScreen> {
  late Future<ChildProfile> _future;
  double _musicVolume = AudioSettingsService.defaultBackgroundMusicVolume;
  double _voiceVolume = AudioSettingsService.defaultVoiceVolume;
  bool _audioSettingsLoading = true;

  @override
  void initState() {
    super.initState();
    _future = _loadChild();
    _loadAudioSettings();
  }

  Future<ChildProfile> _loadChild() async {
    final child = await widget.repository.getChild(widget.childId);
    if (mounted) {
      await precacheBackendImages(
        context,
        <String?>[child.avatar?.imageUrl, child.baseLanguage?.iconUrl],
      );
    }
    return child;
  }

  Future<void> _loadAudioSettings() async {
    final service = AudioSettingsService.instance;
    await service.load();
    if (!mounted) return;
    setState(() {
      _musicVolume = service.backgroundMusicVolume;
      _voiceVolume = service.voiceVolume;
      _audioSettingsLoading = false;
    });
  }

  Future<void> _setMusicVolume(double value) async {
    setState(() => _musicVolume = value);
    await AudioSettingsService.instance.setBackgroundMusicVolume(value);
  }

  Future<void> _setVoiceVolume(double value) async {
    setState(() => _voiceVolume = value);
    await AudioSettingsService.instance.setVoiceVolume(value);
  }

  Future<void> _edit(ChildProfile child) async {
    final allowed = await widget.requestParentAccess();
    if (!allowed || !mounted) return;

    final updated = await Navigator.of(context).push<ChildProfile>(
      MaterialPageRoute(
        builder: (_) => ChildEditorScreen(
          repository: widget.repository,
          child: child,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _future = _loadChild();
      });
    }
  }

  Future<void> _returnToParent() async {
    final allowed = await widget.requestParentAccess();
    if (!allowed || !mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChildProfile>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: ZenviaLoadingScreen());
        }
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(title: Text(context.tr('childProfile'))),
            body: Center(child: Text(snapshot.error.toString())),
          );
        }
        final child = snapshot.data!;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: Text(context.tr('childProfile'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: Colors.white,
                  backgroundImage: child.avatar?.imageUrl == null
                      ? null
                      : NetworkImage(child.avatar!.imageUrl!),
                  child: child.avatar?.imageUrl == null
                      ? Image.asset('assets/images/dragon_hero.webp', width: 54, height: 54, fit: BoxFit.contain)
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                child.name,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                context.tr('xpLevel', {'xp': child.totalXp, 'level': child.level?.number ?? 0}),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: const Icon(Icons.translate_rounded),
                title: Text(context.tr('baseLanguage')),
                subtitle: Text(child.baseLanguage?.title ?? context.tr('notSelected')),
                trailing: const Icon(Icons.lock_outline_rounded),
                onTap: () => _edit(child),
              ),
              const SizedBox(height: 8),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: const Icon(Icons.face_rounded),
                title: Text(context.tr('nameAndAvatar')),
                trailing: const Icon(Icons.lock_outline_rounded),
                onTap: () => _edit(child),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('learningSound'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.deepBlue,
                    ),
              ),
              const SizedBox(height: 10),
              _VolumeSettingCard(
                icon: Icons.music_note_rounded,
                title: context.tr('backgroundMusic'),
                subtitle: context.tr('backgroundMusicHint'),
                value: _musicVolume,
                enabled: !_audioSettingsLoading,
                onChanged: _setMusicVolume,
              ),
              const SizedBox(height: 10),
              _VolumeSettingCard(
                icon: Icons.record_voice_over_rounded,
                title: context.tr('voiceover'),
                subtitle: context.tr('voiceoverHint'),
                value: _voiceVolume,
                enabled: !_audioSettingsLoading,
                onChanged: _setVoiceVolume,
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('volumeSavedHint'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _returnToParent,
                icon: const Icon(Icons.family_restroom_rounded),
                label: Text(context.tr('returnToParent')),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('childSettingsProtected'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}


class _VolumeSettingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _VolumeSettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (value * 100).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlue.withValues(alpha: .08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primaryDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                child: Text(
                  '$percent%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppColors.deepBlue,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(0.0, 1.0).toDouble(),
            min: 0,
            max: 1,
            divisions: 20,
            label: '$percent%',
            onChanged: enabled ? onChanged : null,
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0%', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              Text('100%', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
