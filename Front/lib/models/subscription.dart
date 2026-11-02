class TariffPlan {
  final int id;
  final String code;
  final String title;
  final String description;
  final String price;
  final String currency;
  final int durationDays;
  final int maxChildren;
  final bool googlePlayEnabled;
  final String googleProductId;
  final String googleBasePlanId;
  final bool appleStoreEnabled;
  final String appleProductId;

  const TariffPlan({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.price,
    required this.currency,
    required this.durationDays,
    required this.maxChildren,
    this.googlePlayEnabled = false,
    this.googleProductId = '',
    this.googleBasePlanId = '',
    this.appleStoreEnabled = false,
    this.appleProductId = '',
  });
}

class SubscriptionInfo {
  final int id;
  final TariffPlan tariff;
  final String status;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool autoRenew;
  final bool isCurrent;
  final String paymentProvider;
  final String externalPaymentId;
  final String googleProductId;
  final String googleBasePlanId;
  final String googleOrderId;
  final String googleSubscriptionState;

  const SubscriptionInfo({
    required this.id,
    required this.tariff,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.autoRenew,
    required this.isCurrent,
    this.paymentProvider = '',
    this.externalPaymentId = '',
    this.googleProductId = '',
    this.googleBasePlanId = '',
    this.googleOrderId = '',
    this.googleSubscriptionState = '',
  });

  String get statusLabel {
    switch (status) {
      case 'active':
        return 'Активна';
      case 'pending':
        return 'Ожидает оплаты';
      case 'expired':
        return 'Истекла';
      case 'cancelled':
        return 'Отменена';
      default:
        return status;
    }
  }
}


class PromoOffer {
  final String code;
  final String mode;
  final String channel;
  final String displayName;
  final String partnerName;
  final String campaignName;
  final int? kindergartenId;
  final String kindergartenName;
  final int? accessDays;
  final TariffPlan tariff;

  const PromoOffer({
    required this.code,
    required this.mode,
    required this.channel,
    required this.displayName,
    required this.partnerName,
    required this.campaignName,
    required this.kindergartenId,
    required this.kindergartenName,
    required this.accessDays,
    required this.tariff,
  });

  bool get isDirectAccess => mode == 'direct_access';
  bool get requiresGooglePlay => mode == 'google_play';
}


enum FakePaymentScenario {
  success,
  declined,
  cancelled,
  pending,
  networkError,
}

extension FakePaymentScenarioX on FakePaymentScenario {
  String get apiValue {
    switch (this) {
      case FakePaymentScenario.success:
        return 'success';
      case FakePaymentScenario.declined:
        return 'declined';
      case FakePaymentScenario.cancelled:
        return 'cancelled';
      case FakePaymentScenario.pending:
        return 'pending';
      case FakePaymentScenario.networkError:
        return 'network_error';
    }
  }

  String get title {
    switch (this) {
      case FakePaymentScenario.success:
        return 'Успешная оплата';
      case FakePaymentScenario.declined:
        return 'Отклонено банком';
      case FakePaymentScenario.cancelled:
        return 'Пользователь отменил';
      case FakePaymentScenario.pending:
        return 'Платёж в ожидании';
      case FakePaymentScenario.networkError:
        return 'Ошибка сети';
    }
  }
}

class FakePaymentResult {
  final String result;
  final String message;
  final SubscriptionInfo? subscription;

  const FakePaymentResult({
    required this.result,
    required this.message,
    required this.subscription,
  });
}

class SubscriptionAccessStatus {
  final bool active;
  final String reason;
  final int? subscriptionId;
  final String? status;
  final int? tariffId;
  final String? tariffTitle;
  final DateTime? endsAt;

  const SubscriptionAccessStatus({
    required this.active,
    required this.reason,
    this.subscriptionId,
    this.status,
    this.tariffId,
    this.tariffTitle,
    this.endsAt,
  });

  bool get isExpired => reason == 'expired';
  bool get isPending => reason == 'pending';

  factory SubscriptionAccessStatus.connectionError() =>
      const SubscriptionAccessStatus(
        active: false,
        reason: 'connection_error',
      );
}
