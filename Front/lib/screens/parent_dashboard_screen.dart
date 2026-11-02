import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/parent_repository.dart';
import '../data/legal_repository.dart';
import '../models/child_profile.dart';
import '../l10n/app_strings.dart';
import '../models/parent_account.dart';
import '../theme/app_colors.dart';
import '../services/app_locale_controller.dart';
import '../widgets/magic_ui.dart';
import '../widgets/parent_pin_dialog.dart';
import 'child_editor_screen.dart';
import 'parent_settings_screen.dart';
import 'parent_login_screen.dart';
import 'tariffs_screen.dart';

class ParentDashboardScreen extends StatefulWidget {
  final AuthRepository authRepository;
  final ParentRepository parentRepository;
  final LegalRepository legalRepository;
  final Future<void> Function(ChildProfile child) onOpenChild;
  final VoidCallback onLoggedOut;

  const ParentDashboardScreen({
    super.key,
    required this.authRepository,
    required this.parentRepository,
    required this.legalRepository,
    required this.onOpenChild,
    required this.onLoggedOut,
  });

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  late Future<ParentDashboard> _future;
  bool _showLogin = false;
  bool _startingTrial = false;

  @override
  void initState() {
    super.initState();
    _future = widget.parentRepository.getDashboard();
  }

  void _reload() {
    setState(() {
      _future = widget.parentRepository.getDashboard();
    });
  }

  Future<void> _requestAddChild(ParentDashboard data) async {
    if (!data.childAccess.canCreateChild) {
      final useTrial = data.trial.eligible;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          title: Text(
            useTrial
                ? context.tr(
                    'trialOfferTitle',
                    {'days': data.trial.daysTotal},
                  )
                : (data.childAccess.activeSubscription
                    ? context.tr('profileLimitTitle')
                    : context.tr('subscriptionRequiredTitle')),
          ),
          content: Text(
            useTrial
                ? context.tr('trialOfferSubtitle')
                : (data.childAccess.reason ?? context.tr('profileLimitText')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('close')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                useTrial ? context.tr('trialStart') : context.tr('tariffs'),
              ),
            ),
          ],
        ),
      );
      if (proceed == true && mounted) {
        if (useTrial) {
          await _startTrial(data);
        } else {
          await _openTariffs();
        }
      }
      return;
    }

    final created = await Navigator.of(context).push<ChildProfile>(
      MaterialPageRoute(
        builder: (_) => ChildEditorScreen(repository: widget.parentRepository),
      ),
    );
    if (created != null && mounted) _reload();
  }

  Future<void> _openChild(ChildProfile child) async {
    try {
      final hasPin = await widget.parentRepository.hasParentPin();
      if (!mounted) return;

      if (!hasPin) {
        final created = await showParentPinSetupDialog(
          context: context,
          repository: widget.parentRepository,
        );
        if (!created || !mounted) return;
      }

      await widget.parentRepository.selectChild(child.id);
      await widget.onOpenChild(child);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _editChild(ChildProfile child) async {
    final result = await Navigator.of(context).push<ChildProfile>(
      MaterialPageRoute(
        builder: (_) => ChildEditorScreen(
          repository: widget.parentRepository,
          child: child,
        ),
      ),
    );
    if (result != null && mounted) _reload();
  }

  Future<void> _archiveChild(ChildProfile child) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        title: Text(context.tr('deleteProfileTitle')),
        content: Text(
          context.tr('deleteProfileText', {'name': child.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.parentRepository.archiveChild(child.id);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }


  Future<void> _startTrial(ParentDashboard data) async {
    if (_startingTrial || !data.trial.eligible) return;

    setState(() => _startingTrial = true);
    try {
      await widget.parentRepository.startTrial();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('trialStarted', {'days': data.trial.daysTotal}),
          ),
        ),
      );
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _startingTrial = false);
    }
  }

  Future<void> _openTariffs() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TariffsScreen(repository: widget.parentRepository),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _handleLoginAfterSessionEnded() async {
    try {
      final parent = await widget.authRepository.getParent();
      appLocaleController.setCode(parent.interfaceLanguage);
    } catch (_) {
      // Locale не должен блокировать вход в новый аккаунт.
    }

    if (!mounted) return;
    setState(() {
      _showLogin = false;
      _future = widget.parentRepository.getDashboard();
    });
  }

  Future<void> _openSettings() async {
    final shouldReturnToLogin = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ParentSettingsScreen(
          authRepository: widget.authRepository,
          parentRepository: widget.parentRepository,
          legalRepository: widget.legalRepository,
        ),
      ),
    );

    if (!mounted) return;

    if (shouldReturnToLogin == true) {
      // После logout/delete-account не трогаем корневой AuthGate. Переключаем
      // только содержимое ParentDashboard на Login — Navigator уже закончил
      // удаление экрана настроек, поэтому inherited-зависимости не ломаются.
      setState(() => _showLogin = true);
      return;
    }

    _reload();
  }

  Future<void> _logout() async {
    await widget.authRepository.logout();
    if (!mounted) return;
    widget.onLoggedOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_showLogin) {
      return ParentLoginScreen(
        authRepository: widget.authRepository,
        legalRepository: widget.legalRepository,
        onLoggedIn: _handleLoginAfterSessionEnded,
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/home_language_bg.webp',
            fit: BoxFit.cover,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: .18),
                  Colors.white.withValues(alpha: .42),
                  const Color(0xFFF3FFF1).withValues(alpha: .62),
                ],
              ),
            ),
          ),
          SafeArea(
            child: FutureBuilder<ParentDashboard>(
              future: _future,
              builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: MagicCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('☁️', style: TextStyle(fontSize: 44)),
                          const SizedBox(height: 8),
                          Text(snapshot.error.toString(), textAlign: TextAlign.center),
                          const SizedBox(height: 14),
                          MagicPrimaryButton(label: context.tr('retry'), onPressed: _reload),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final data = snapshot.data!;
              return RefreshIndicator(
                onRefresh: () async {
                  _reload();
                  await _future;
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 155,
                          child: Image.asset(
                            'assets/images/zenvia_kids_logo.webp',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const Spacer(),
                        _DashboardActionButton(
                          label: context.tr('logout'),
                          icon: Icons.logout_rounded,
                          onTap: _logout,
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          child: IconButton(
                            onPressed: _openSettings,
                            tooltip: context.tr('settings'),
                            icon: const Icon(Icons.settings_rounded, color: AppColors.deepBlue),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    MagicCard(
                      padding: EdgeInsets.zero,
                      gradient: AppColors.magicGradient,
                      child: SizedBox(
                        height: 168,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: Image.asset(
                                  'assets/images/dragon_wave.webp',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.deepBlue.withValues(alpha: .88),
                                      AppColors.skyTop.withValues(alpha: .52),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 18,
                              top: 24,
                              width: 215,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr('helloParent', {'name': data.parent.firstName}),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 23,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    data.parent.email,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    context.tr('familyLearning'),
                                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (data.trial.eligible) ...[
                      _TrialOfferCard(
                        trial: data.trial,
                        loading: _startingTrial,
                        onStart: () => _startTrial(data),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _SubscriptionCard(
                      dashboard: data,
                      trial: data.trial,
                      onTap: _openTariffs,
                    ),
                    const SizedBox(height: 22),
                    MagicSectionTitle(
                      title: context.tr('childrenProfiles'),
                      action: context.tr('add'),
                      onAction: () => _requestAddChild(data),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.childAccess.activeSubscription
                          ? context.tr('profilesCount', {'active': data.childAccess.activeChildren, 'max': data.childAccess.maxChildren})
                          : context.tr('noActiveSubscription'),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    if (!data.childAccess.canCreateChild && !data.trial.eligible) ...[
                      const SizedBox(height: 10),
                      _LimitNotice(access: data.childAccess, onTariffs: _openTariffs),
                    ],
                    const SizedBox(height: 12),
                    if (data.children.isEmpty)
                      MagicCard(
                        child: Column(
                          children: [
                            const Text('🐣', style: TextStyle(fontSize: 54)),
                            const SizedBox(height: 8),
                            Text(
                              data.childAccess.canCreateChild
                                  ? context.tr('createFirstChild')
                                  : data.trial.eligible
                                      ? context.tr(
                                          'trialCreateChildHint',
                                          {'days': data.trial.daysTotal},
                                        )
                                      : (data.childAccess.reason ??
                                          context.tr('chooseTariffFirst')),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 14),
                            MagicPrimaryButton(
                              label: data.childAccess.canCreateChild
                                  ? context.tr('createProfile')
                                  : data.trial.eligible
                                      ? (_startingTrial
                                          ? context.tr('trialStarting')
                                          : context.tr('trialStart'))
                                      : context.tr('chooseTariff'),
                              icon: data.childAccess.canCreateChild
                                  ? Icons.add_rounded
                                  : data.trial.eligible
                                      ? Icons.auto_awesome_rounded
                                      : Icons.workspace_premium_rounded,
                              onPressed: data.childAccess.canCreateChild
                                  ? () => _requestAddChild(data)
                                  : data.trial.eligible
                                      ? (_startingTrial
                                          ? null
                                          : () => _startTrial(data))
                                      : _openTariffs,
                            ),
                          ],
                        ),
                      ),
                    ...data.children.map(
                      (child) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ChildCard(
                          child: child,
                          onOpen: () => _openChild(child),
                          onEdit: () => _editChild(child),
                          onDelete: () => _archiveChild(child),
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

class _DashboardActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _DashboardActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.deepBlue),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.deepBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _TrialOfferCard extends StatelessWidget {
  final TrialAccessInfo trial;
  final bool loading;
  final VoidCallback onStart;

  const _TrialOfferCard({
    required this.trial,
    required this.loading,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return MagicCard(
      color: const Color(0xFFEAF8FF),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.card_giftcard_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(
                        'trialOfferTitle',
                        {'days': trial.daysTotal},
                      ),
                      style: const TextStyle(
                        color: AppColors.deepBlue,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('trialOfferSubtitle'),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          MagicPrimaryButton(
            label: loading
                ? context.tr('trialStarting')
                : context.tr('trialStart'),
            icon: Icons.auto_awesome_rounded,
            onPressed: loading ? null : onStart,
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              context.tr('trialNoCard'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime? value) {
  if (value == null) return '—';
  final date = value.toLocal();
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day.$month.${date.year}';
}

class _SubscriptionCard extends StatelessWidget {
  final ParentDashboard dashboard;
  final TrialAccessInfo trial;
  final VoidCallback onTap;
  const _SubscriptionCard({
    required this.dashboard,
    required this.trial,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sub = dashboard.subscription;
    final access = dashboard.childAccess;
    String title;
    String subtitle;
    if (trial.active) {
      title = context.tr('trialActiveTitle');
      subtitle = context.tr('trialDaysRemaining', {
        'days': trial.daysRemaining,
        'date': _formatDate(trial.endsAt),
      });
    } else if (sub == null && trial.used) {
      title = context.tr('trialEnded');
      subtitle = context.tr('chooseFamilyTariff');
    } else if (sub == null) {
      title = context.tr('tariffNotSelected');
      subtitle = context.tr('chooseFamilyTariff');
    } else if (sub.status == 'pending') {
      title = sub.tariff.title;
      subtitle = context.tr('pendingProfiles');
    } else if (access.activeSubscription) {
      title = sub.tariff.title;
      subtitle = context.tr('activeProfiles', {
        'active': access.activeChildren,
        'max': access.maxChildren,
      });
    } else {
      title = sub.tariff.title;
      subtitle = context.tr(
        'statusValue',
        {'status': AppStrings.subscriptionStatus(context, sub.status)},
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF4C7), Color(0xFFFFE3A1)],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.gold.withValues(alpha: .55)),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white,
                child: Icon(Icons.workspace_premium_rounded, color: AppColors.goldDark, size: 28),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.deepBlue,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.goldDark),
            ],
          ),
        ),
      ),
    );
  }
}

class _LimitNotice extends StatelessWidget {
  final ChildProfileAccess access;
  final VoidCallback onTariffs;
  const _LimitNotice({required this.access, required this.onTariffs});

  @override
  Widget build(BuildContext context) {
    return MagicCard(
      color: const Color(0xFFFFF3E6),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              access.reason ?? context.tr('extraProfileUnavailable'),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          TextButton(onPressed: onTariffs, child: Text(context.tr('tariffs'))),
        ],
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final ChildProfile child;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ChildCard({
    required this.child,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return MagicCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFE6F7FF), Color(0xFFE9FFE9)]),
              borderRadius: BorderRadius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            child: child.avatar?.imageUrl == null
                ? const Center(child: Text('🐉', style: TextStyle(fontSize: 34)))
                : Image.network(
                    child.avatar!.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(child: Text('🐉', style: TextStyle(fontSize: 34))),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  child.name,
                  style: const TextStyle(
                    color: AppColors.deepBlue,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.tr('levelXp', {'level': child.level?.number ?? 0, 'xp': child.totalXp}),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                Text(
                  child.baseLanguage?.title ?? context.tr('languageNotSelected'),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(context.tr('edit'))),
              PopupMenuItem(value: 'delete', child: Text(context.tr('delete'))),
            ],
          ),
          IconButton.filled(
            onPressed: onOpen,
            style: IconButton.styleFrom(backgroundColor: AppColors.primary),
            icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
