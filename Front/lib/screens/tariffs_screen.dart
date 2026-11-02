import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../data/parent_repository.dart';
import '../models/subscription.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../widgets/magic_ui.dart';

const bool _fakePaymentsEnabled = bool.fromEnvironment(
  'FAKE_PAYMENTS',
  defaultValue: false,
);

class TariffsScreen extends StatefulWidget {
  final ParentRepository repository;
  const TariffsScreen({super.key, required this.repository});

  @override
  State<TariffsScreen> createState() => _TariffsScreenState();
}

class _TariffsScreenState extends State<TariffsScreen> {
  late Future<_Data> _future;
  final TextEditingController _promoController = TextEditingController();

  int? _processingId;
  bool _validatingPromo = false;
  bool _disablingAutoRenew = false;
  PromoOffer? _promoOffer;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Map<int, ProductDetails> _googleProducts = const {};
  Map<int, String> _googlePrices = const {};
  Set<String> _googleNotFoundIds = const <String>{};
  final Set<String> _verifyingPurchaseTokens = <String>{};
  bool _googleStoreAvailable = false;
  bool _restoringPurchases = false;
  String? _googleStoreError;

  @override
  void initState() {
    super.initState();
    _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _processingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('googlePlayPurchaseFailed'))),
        );
      },
    );
    _future = _load();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _promoController.dispose();
    super.dispose();
  }

  Future<_Data> _load() async {
    final values = await Future.wait([
      widget.repository.getTariffs(),
      widget.repository.getCurrentSubscription(),
    ]);
    final tariffs = values[0] as List<TariffPlan>;
    if (!_fakePaymentsEnabled && Platform.isAndroid) {
      await _loadGoogleProducts(tariffs);
    }
    return _Data(
      tariffs: tariffs,
      current: values[1] as SubscriptionInfo?,
    );
  }

  Future<void> _loadGoogleProducts(
    List<TariffPlan> tariffs, {
    bool merge = false,
  }) async {
    _googleStoreError = null;
    _googleNotFoundIds = const <String>{};

    try {
      final available = await InAppPurchase.instance.isAvailable();
      if (!available) {
        _googleStoreAvailable = false;
        _googleProducts = const {};
        _googlePrices = const {};
        _googleStoreError = 'billing_unavailable';
        debugPrint('[Billing] Google Play Billing is unavailable.');
        return;
      }

      final productIds = tariffs
          .where((plan) =>
              plan.googlePlayEnabled &&
              plan.googleProductId.trim().isNotEmpty &&
              plan.googleBasePlanId.trim().isNotEmpty)
          .map((plan) => plan.googleProductId.trim())
          .toSet();
      if (productIds.isEmpty) {
        _googleStoreAvailable = true;
        _googleProducts = const {};
        _googlePrices = const {};
        debugPrint('[Billing] No Google Play products are configured by the backend.');
        return;
      }

      debugPrint('[Billing] Querying products: ${productIds.join(', ')}');
      final response =
          await InAppPurchase.instance.queryProductDetails(productIds);
      final products = merge
          ? <int, ProductDetails>{..._googleProducts}
          : <int, ProductDetails>{};
      final prices = merge ? <int, String>{..._googlePrices} : <int, String>{};
      _googleNotFoundIds = merge
          ? <String>{..._googleNotFoundIds, ...response.notFoundIDs}
          : response.notFoundIDs.toSet();

      final responseError = response.error;
      if (responseError != null) {
        _googleStoreError = '${responseError.code}: ${responseError.message}';
        debugPrint('[Billing] queryProductDetails error: $_googleStoreError');
      }
      if (_googleNotFoundIds.isNotEmpty) {
        debugPrint(
          '[Billing] Products not found: ${_googleNotFoundIds.join(', ')}',
        );
      }

      for (final plan in tariffs) {
        if (!plan.googlePlayEnabled) continue;
        GooglePlayProductDetails? fallback;
        GooglePlayProductDetails? preferred;

        for (final details in response.productDetails) {
          if (details.id.trim() != plan.googleProductId.trim() ||
              details is! GooglePlayProductDetails) {
            continue;
          }

          final index = details.subscriptionIndex;
          final offers = details.productDetails.subscriptionOfferDetails;
          if (index == null ||
              offers == null ||
              index < 0 ||
              index >= offers.length) {
            debugPrint(
              '[Billing] ${details.id}: invalid subscription offer index $index.',
            );
            continue;
          }

          final offer = offers[index];
          debugPrint(
            '[Billing] ${details.id}: basePlan=${offer.basePlanId}, '
            'offer=${offer.offerId ?? '<base-plan>'}, price=${details.price}',
          );
          if (offer.basePlanId.trim() != plan.googleBasePlanId.trim()) continue;

          fallback ??= details;
          // Prefer the regular base-plan offer. If Google returns only an
          // eligible promotional offer, keep it as a safe fallback.
          if (offer.offerId == null) {
            preferred = details;
            break;
          }
        }

        final selected = preferred ?? fallback;
        if (selected != null) {
          products[plan.id] = selected;
          prices[plan.id] = selected.price;
          debugPrint(
            '[Billing] Tariff ${plan.code}: ${plan.googleProductId}/'
            '${plan.googleBasePlanId} is ready (${selected.price}).',
          );
        } else {
          debugPrint(
            '[Billing] Tariff ${plan.code}: no matching Google Play offer for '
            '${plan.googleProductId}/${plan.googleBasePlanId}.',
          );
        }
      }

      _googleStoreAvailable = true;
      _googleProducts = products;
      _googlePrices = prices;
    } catch (error, stackTrace) {
      if (!merge) {
        _googleStoreAvailable = false;
        _googleProducts = const {};
        _googlePrices = const {};
      }
      _googleStoreError = error.toString();
      debugPrint('[Billing] Failed to load products: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  String? _googlePlayIssue(TariffPlan plan) {
    if (_fakePaymentsEnabled) return null;
    if (!Platform.isAndroid) return context.tr('googlePlayAndroidOnly');
    if (!plan.googlePlayEnabled ||
        plan.googleProductId.trim().isEmpty ||
        plan.googleBasePlanId.trim().isEmpty) {
      return context.tr('googlePlayTariffNotConfigured');
    }
    if (!_googleStoreAvailable) {
      return context.tr('googlePlayStoreUnavailable');
    }
    if (_googleProducts[plan.id] != null) return null;
    if (_googleNotFoundIds.contains(plan.googleProductId.trim())) {
      return context.tr(
        'googlePlayProductNotFound',
        {'product': plan.googleProductId},
      );
    }
    if (_googleStoreError != null && _googleStoreError!.isNotEmpty) {
      return context.tr(
        'googlePlayStoreError',
        {'error': _googleStoreError!},
      );
    }
    return context.tr(
      'googlePlayBasePlanNotFound',
      {
        'product': plan.googleProductId,
        'basePlan': plan.googleBasePlanId,
      },
    );
  }

  void _reloadBilling() {
    if (!mounted) return;
    setState(() {
      _googleStoreError = null;
      _future = _load();
    });
  }

  void _showGooglePlayIssue(TariffPlan plan) {
    final message = _googlePlayIssue(plan) ??
        context.tr('googlePlayProductUnavailable');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: context.tr('retry'),
          onPressed: _reloadBilling,
        ),
      ),
    );
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      debugPrint(
        '[Billing] Purchase update: product=${purchase.productID}, '
        'status=${purchase.status}, pendingComplete=${purchase.pendingCompletePurchase}',
      );

      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) {
          setState(() => _processingId = null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('paymentPending'))),
          );
        }
        continue;
      }

      if (purchase.status == PurchaseStatus.error ||
          purchase.status == PurchaseStatus.canceled) {
        if (mounted) {
          setState(() => _processingId = null);
          final error = purchase.error;
          final message = purchase.status == PurchaseStatus.canceled
              ? context.tr('paymentCancelled')
              : error == null
                  ? context.tr('googlePlayPurchaseFailed')
                  : context.tr(
                      'googlePlayPurchaseError',
                      {'code': error.code, 'message': error.message},
                    );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
        continue;
      }

      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      if (purchase is! GooglePlayPurchaseDetails) {
        debugPrint('[Billing] Ignoring non-Google purchase on Android.');
        continue;
      }

      final token = purchase.verificationData.serverVerificationData.trim();
      if (token.isEmpty) {
        if (mounted) {
          setState(() => _processingId = null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('googlePlayMissingToken'))),
          );
        }
        continue;
      }

      // The purchase stream can emit the same active purchase more than once
      // (for example after restore). Do not verify one token concurrently.
      if (!_verifyingPurchaseTokens.add(token)) {
        debugPrint('[Billing] Purchase token is already being verified.');
        continue;
      }

      try {
        String? promoCode;
        final activePromo = _promoOffer;
        if (activePromo != null &&
            activePromo.requiresGooglePlay &&
            activePromo.tariff.googleProductId.trim() == purchase.productID.trim()) {
          promoCode = activePromo.code.trim();
        }

        final subscription = await widget.repository.verifyGooglePlayPurchase(
          token,
          promoCode: promoCode,
        );
        if (purchase.pendingCompletePurchase) {
          try {
            await InAppPurchase.instance.completePurchase(purchase);
          } catch (error) {
            // Backend performs server-side acknowledgement. Keep the client
            // completion attempt as recommended by the Flutter plugin, but do
            // not invalidate an already verified subscription if it races with
            // the server acknowledgement.
            debugPrint('[Billing] completePurchase warning: $error');
          }
        }
        if (!mounted) continue;
        setState(() {
          _processingId = null;
          _promoOffer = null;
          _promoController.clear();
          _future = _load();
        });
        if (subscription.isCurrent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('googlePlayPurchaseVerified'))),
          );
        }
      } catch (error) {
        debugPrint('[Billing] Server verification failed: $error');
        if (!mounted) continue;
        setState(() => _processingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      } finally {
        _verifyingPurchaseTokens.remove(token);
      }
    }
  }

  Future<void> _restoreGooglePurchases() async {
    if (_restoringPurchases) return;
    setState(() => _restoringPurchases = true);
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _restoringPurchases = false);
    }
  }

  Future<void> _validatePromo() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('promoEnter'))),
      );
      return;
    }

    setState(() => _validatingPromo = true);
    try {
      final offer = await widget.repository.validatePromoCode(code);

      // Hidden kindergarten tariffs are not part of the initial public tariff
      // list, so their Google Play ProductDetails are not loaded on screen open.
      // Load the validated promo tariff explicitly and merge it with the
      // already loaded public products (for example zenvia_family/monthly).
      if (offer.requiresGooglePlay && !_fakePaymentsEnabled && Platform.isAndroid) {
        await _loadGoogleProducts([offer.tariff], merge: true);
      }

      if (!mounted) return;
      setState(() {
        _promoOffer = offer;
        _promoController.text = offer.code;
        _promoController.selection = TextSelection.collapsed(
          offset: _promoController.text.length,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('promoApplied', {'name': offer.displayName}),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _promoOffer = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _validatingPromo = false);
    }
  }

  Future<FakePaymentScenario?> _chooseFakePaymentScenario(
    TariffPlan plan,
  ) {
    return showModalBottomSheet<FakePaymentScenario>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        Widget option({
          required FakePaymentScenario scenario,
          required IconData icon,
          required String subtitle,
          required Color color,
        }) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: .14),
              child: Icon(icon, color: color),
            ),
            title: Text(
              _fakeScenarioTitle(sheetContext, scenario),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(subtitle),
            onTap: () => Navigator.of(sheetContext).pop(scenario),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sheetContext.tr('fakePayment'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${plan.title} • ${plan.price} ${plan.currency}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                option(
                  scenario: FakePaymentScenario.success,
                  icon: Icons.check_circle_rounded,
                  subtitle: sheetContext.tr('fakeImmediate'),
                  color: AppColors.primary,
                ),
                option(
                  scenario: FakePaymentScenario.declined,
                  icon: Icons.credit_card_off_rounded,
                  subtitle: sheetContext.tr('fakeDecline'),
                  color: AppColors.coral,
                ),
                option(
                  scenario: FakePaymentScenario.cancelled,
                  icon: Icons.close_rounded,
                  subtitle: sheetContext.tr('fakeCancel'),
                  color: AppColors.purple,
                ),
                option(
                  scenario: FakePaymentScenario.pending,
                  icon: Icons.hourglass_top_rounded,
                  subtitle: sheetContext.tr('fakePending'),
                  color: AppColors.goldDark,
                ),
                option(
                  scenario: FakePaymentScenario.networkError,
                  icon: Icons.wifi_off_rounded,
                  subtitle: sheetContext.tr('fakeError'),
                  color: AppColors.deepBlue,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _fakeScenarioTitle(BuildContext context, FakePaymentScenario scenario) {
    switch (scenario) {
      case FakePaymentScenario.success:
        return context.tr('fakeSuccess');
      case FakePaymentScenario.declined:
        return context.tr('paymentDeclined');
      case FakePaymentScenario.cancelled:
        return context.tr('paymentCancelled');
      case FakePaymentScenario.pending:
        return context.tr('paymentPending');
      case FakePaymentScenario.networkError:
        return context.tr('fakePaymentError');
    }
  }

  Future<void> _showFakePaymentResult(FakePaymentResult result) async {
    if (!mounted) return;

    final success = result.result == 'success';
    final pending = result.result == 'pending';
    final title = success
        ? context.tr('fakeSuccess')
        : pending
            ? context.tr('paymentPending')
            : result.result == 'declined'
                ? context.tr('paymentDeclined')
                : result.result == 'cancelled'
                    ? context.tr('paymentCancelled')
                    : context.tr('fakePayment');

    final subscription = result.subscription;
    final period = subscription?.endsAt == null
        ? ''
        : '\nПодписка действует до: '
            '${subscription!.endsAt!.toLocal().toString().split(' ').first}.';

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text('${result.message}$period'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('understood')),
          ),
        ],
      ),
    );
  }

  Future<void> _buy(
    TariffPlan plan, {
    String? promoCode,
    PromoOffer? promoOffer,
  }) async {
    if (promoOffer?.isDirectAccess == true) {
      setState(() => _processingId = plan.id);
      try {
        final subscription = await widget.repository.redeemPromoCode(
          promoOffer!.code,
        );
        if (!mounted) return;
        setState(() {
          _promoOffer = null;
          _promoController.clear();
          _future = _load();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'promoAccessActivated',
                {'date': _dateLabel(subscription.endsAt)},
              ),
            ),
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      } finally {
        if (mounted) setState(() => _processingId = null);
      }
      return;
    }
    if (_fakePaymentsEnabled) {
      final scenario = await _chooseFakePaymentScenario(plan);
      if (scenario == null || !mounted) return;

      setState(() => _processingId = plan.id);
      try {
        final result = await widget.repository.fakePurchase(
          plan.id,
          promoCode: promoCode,
          scenario: scenario,
        );
        if (!mounted) return;

        await _showFakePaymentResult(result);

        if (result.subscription != null) {
          setState(() {
            _promoOffer = null;
            _promoController.clear();
            _future = _load();
          });
        }
      } catch (e) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(context.tr('fakePaymentError')),
              content: Text(e.toString()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr('close')),
                ),
              ],
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _processingId = null);
      }
      return;
    }

    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('googlePlayAndroidOnly'))),
      );
      return;
    }

    final issue = _googlePlayIssue(plan);
    final product = _googleProducts[plan.id];
    if (issue != null || product == null) {
      _showGooglePlayIssue(plan);
      return;
    }

    setState(() => _processingId = plan.id);
    try {
      final purchaseParam = GooglePlayPurchaseParam(productDetails: product);
      final started = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      if (!started && mounted) {
        setState(() => _processingId = null);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _processingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'googlePlayPurchaseStartError',
              {'error': e.toString()},
            ),
          ),
        ),
      );
    }
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return '—';
    final date = value.toLocal();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  Future<void> _disableAutoRenew(SubscriptionInfo subscription) async {
    if (_disablingAutoRenew || !subscription.autoRenew) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('disableAutoRenewTitle')),
        content: Text(
          dialogContext.tr(
            'disableAutoRenewText',
            {'date': _dateLabel(subscription.endsAt)},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.tr('disableAutoRenew')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _disablingAutoRenew = true);
    try {
      final updated = await widget.repository.disableAutoRenew(subscription.id);
      if (!mounted) return;
      setState(() => _future = _load());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'autoRenewDisabledSuccess',
              {'date': _dateLabel(updated.endsAt)},
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _disablingAutoRenew = false);
    }
  }

  Future<void> _resetFakeSubscription() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.tr('resetFakeTitle')),
        content: Text(context.tr('resetFakeText')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('reset')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.repository.resetFakeSubscription();
      if (!mounted) return;
      setState(() {
        _promoOffer = null;
        _promoController.clear();
        _future = _load();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('fakeResetDone'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Widget _tariffCard({
    required BuildContext context,
    required TariffPlan plan,
    required bool disabled,
    String? promoCode,
    PromoOffer? promoOffer,
    String? badge,
    String? subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              plan.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (plan.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(plan.description),
            ],
            const SizedBox(height: 10),
            Text(
              promoOffer?.isDirectAccess == true
                  ? context.tr('promoDirectAccessDays', {
                      'days': promoOffer?.accessDays ?? plan.durationDays,
                    })
                  : _googlePrices[plan.id] != null && !_fakePaymentsEnabled
                      ? '${_googlePrices[plan.id]} / ${plan.durationDays} ${context.tr('daysShort')}'
                      : context.tr('priceDays', {
                          'price': plan.price,
                          'currency': plan.currency,
                          'days': plan.durationDays,
                        }),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(context.tr('childrenUpTo', {'count': plan.maxChildren})),
            if (promoOffer?.isDirectAccess != true &&
                !_fakePaymentsEnabled &&
                _googlePlayIssue(plan) != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _googlePlayIssue(plan)!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: disabled || _processingId != null
                    ? null
                    : () => _buy(
                          plan,
                          promoCode: promoCode,
                          promoOffer: promoOffer,
                        ),
                child: _processingId == plan.id
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        promoOffer?.isDirectAccess == true
                            ? context.tr('activateAccessCode')
                            : _fakePaymentsEnabled
                                ? (promoCode == null
                                    ? context.tr('fakePayment')
                                    : context.tr('fakePromoPayment'))
                                : (promoCode == null
                                    ? context.tr('purchasePlan')
                                    : context.tr('connectPromo')),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _promoSection({
    required bool disabled,
  }) {
    final offer = _promoOffer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          context.tr('promoCodeTitle'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(context.tr('promoUniversalHint')),
        const SizedBox(height: 12),
        TextField(
          controller: _promoController,
          enabled: !disabled && !_validatingPromo,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: context.tr('promoExample'),
            prefixIcon: const Icon(Icons.confirmation_number_outlined),
            suffixIcon: _promoController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: context.tr('clear'),
                    onPressed: disabled || _validatingPromo
                        ? null
                        : () {
                            setState(() {
                              _promoController.clear();
                              _promoOffer = null;
                            });
                          },
                    icon: const Icon(Icons.close),
                  ),
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) {
            if (offer != null &&
                value.trim().toUpperCase() != offer.code.toUpperCase()) {
              setState(() => _promoOffer = null);
            } else {
              setState(() {});
            }
          },
          onSubmitted: disabled || _validatingPromo
              ? null
              : (_) => _validatePromo(),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: disabled || _validatingPromo
                ? null
                : _validatePromo,
            icon: _validatingPromo
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_outlined),
            label: Text(
              _validatingPromo ? context.tr('checking') : context.tr('applyPromo'),
            ),
          ),
        ),
        if (offer != null) ...[
          const SizedBox(height: 16),
          _tariffCard(
            context: context,
            plan: offer.tariff,
            disabled: disabled,
            promoCode: offer.code,
            promoOffer: offer,
            badge: context.tr('specialPlan'),
            subtitle: offer.displayName,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(context.tr('tariffs'))),
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ZenviaLoadingScreen();
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final data = snapshot.data!;
          final hasSubscription = data.current != null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_fakePaymentsEnabled) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.goldDark.withValues(alpha: .35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.science_rounded, color: AppColors.goldDark),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              context.tr('fakeModeNotice'),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      if (data.current?.paymentProvider == 'fake') ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _resetFakeSubscription,
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: Text(context.tr('resetFakeSubscription')),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (data.current != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.workspace_premium_rounded),
                          title: Text(data.current!.tariff.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr(
                                  'statusValue',
                                  {
                                    'status': AppStrings.subscriptionStatus(
                                      context,
                                      data.current!.status,
                                    ),
                                  },
                                ),
                              ),
                              if (data.current!.isCurrent) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      data.current!.autoRenew
                                          ? Icons.autorenew_rounded
                                          : Icons.event_available_rounded,
                                      size: 17,
                                      color: data.current!.autoRenew
                                          ? AppColors.primary
                                          : AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        data.current!.autoRenew
                                            ? context.tr('autoRenewEnabled')
                                            : context.tr(
                                                'autoRenewDisabledUntil',
                                                {
                                                  'date': _dateLabel(
                                                    data.current!.endsAt,
                                                  ),
                                                },
                                              ),
                                        style: const TextStyle(fontSize: 12.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (data.current!.isCurrent && data.current!.autoRenew)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: OutlinedButton.icon(
                              onPressed: _disablingAutoRenew
                                  ? null
                                  : () => _disableAutoRenew(data.current!),
                              icon: _disablingAutoRenew
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : const Icon(Icons.autorenew_rounded),
                              label: Text(
                                _disablingAutoRenew
                                    ? context.tr('disablingAutoRenew')
                                    : context.tr('disableAutoRenew'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              ...data.tariffs.map(
                (plan) => _tariffCard(
                  context: context,
                  plan: plan,
                  disabled: hasSubscription,
                ),
              ),
              if (!_fakePaymentsEnabled && Platform.isAndroid) ...[
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _restoringPurchases ? null : _restoreGooglePurchases,
                  icon: _restoringPurchases
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restore_rounded),
                  label: Text(
                    _restoringPurchases
                        ? context.tr('restoringPurchases')
                        : context.tr('restorePurchases'),
                  ),
                ),
              ],
              const Divider(height: 32),
              _promoSection(disabled: hasSubscription),
            ],
          );
        },
      ),
    );
  }
}

class _Data {
  final List<TariffPlan> tariffs;
  final SubscriptionInfo? current;

  const _Data({
    required this.tariffs,
    required this.current,
  });
}
