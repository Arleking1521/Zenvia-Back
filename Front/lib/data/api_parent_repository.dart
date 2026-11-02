import 'package:dio/dio.dart';

import '../models/child_profile.dart';
import '../models/parent_account.dart';
import '../models/registration_option.dart';
import '../models/subscription.dart';
import 'api/api_client.dart';
import 'api/api_config.dart';
import 'parent_repository.dart';

class ApiParentRepository implements ParentRepository {
  final ApiClient client;

  ApiParentRepository(this.client);

  @override
  Future<ParentDashboard> getDashboard() async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        ApiConfig.account('dashboard/'),
      );
      final data = response.data ?? const <String, dynamic>{};
      final parentMap = _map(data['parent']) ?? const <String, dynamic>{};
      final childRows = _rows(data['children']);
      final subMap = _map(data['subscription']);
      final subscription = subMap == null ? null : _subscription(subMap);
      final children = childRows.map(_child).where((c) => c.isActive).toList();
      final accessMap = _map(data['child_access']);
      final trialMap = _map(data['trial']);

      return ParentDashboard(
        parent: _parent(parentMap),
        children: children,
        subscription: subscription,
        childAccess: accessMap == null
            ? ChildProfileAccess(
                activeSubscription: subscription?.isCurrent == true,
                subscriptionId: subscription?.id,
                tariffId: subscription?.tariff.id,
                tariffTitle: subscription?.tariff.title,
                maxChildren: subscription?.isCurrent == true
                    ? subscription!.tariff.maxChildren
                    : 0,
                activeChildren: children.length,
                remainingSlots: subscription?.isCurrent == true
                    ? (subscription!.tariff.maxChildren - children.length).clamp(0, subscription.tariff.maxChildren).toInt()
                    : 0,
                canCreateChild: subscription?.isCurrent == true &&
                    children.length < subscription!.tariff.maxChildren,
                reason: subscription?.isCurrent == true
                    ? 'Лимит профилей по тарифу исчерпан.'
                    : 'Для создания профиля ребёнка нужна активная подписка.',
              )
            : _childAccess(accessMap),
        trial: trialMap == null
            ? TrialAccessInfo.unavailable
            : _trialAccess(trialMap),
      );
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось загрузить личный кабинет.');
    }
  }

  @override
  Future<List<ChildProfile>> getChildren() async {
    try {
      final response = await client.dio.get<dynamic>(ApiConfig.account('children/'));
      return _rows(response.data).map(_child).toList();
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось загрузить профили детей.');
    }
  }

  @override
  Future<ChildProfile> getChild(int id) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        ApiConfig.account('children/$id/'),
      );
      return _child(response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось загрузить профиль ребёнка.');
    }
  }

  @override
  Future<List<RegistrationLanguage>> getLanguages() async {
    try {
      final response = await client.dio.get<dynamic>(ApiConfig.api('languages/'));
      final languages = _rows(response.data).map((row) {
        final icon = ApiConfig.absoluteMediaUrl(row['icon']?.toString());
        return RegistrationLanguage(
          id: _int(row['id']),
          title: row['title']?.toString() ?? '',
          code: row['code']?.toString() ?? '',
          position: _int(row['position']),
          iconUrl: icon.isEmpty ? null : icon,
        );
      }).where((e) => e.id > 0).toList();

      languages.sort((a, b) {
        final byPosition = a.position.compareTo(b.position);
        if (byPosition != 0) return byPosition;
        return a.id.compareTo(b.id);
      });
      return languages;
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось загрузить языки.');
    }
  }

  @override
  Future<List<AvatarOption>> getAvatars() async {
    try {
      final response = await client.dio.get<dynamic>(ApiConfig.account('avatars/'));
      return _rows(response.data).map((row) {
        final image = ApiConfig.absoluteMediaUrl(row['image']?.toString());
        return AvatarOption(
          id: _int(row['id']),
          title: row['title']?.toString() ?? 'Аватар',
          imageUrl: image.isEmpty ? null : image,
        );
      }).where((e) => e.id > 0).toList();
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось загрузить аватары.');
    }
  }

  @override
  Future<ChildProfile> createChild({
    required String name,
    required int baseLanguageId,
    required int avatarId,
  }) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        ApiConfig.account('children/'),
        data: {
          'name': name.trim(),
          'base_language': baseLanguageId,
          'icon': avatarId,
        },
      );
      return _child(response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось создать профиль ребёнка.');
    }
  }

  @override
  Future<ChildProfile> updateChild({
    required int childId,
    String? name,
    int? baseLanguageId,
    int? avatarId,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name.trim();
    if (baseLanguageId != null) payload['base_language'] = baseLanguageId;
    if (avatarId != null) payload['icon'] = avatarId;

    try {
      final response = await client.dio.patch<Map<String, dynamic>>(
        ApiConfig.account('children/$childId/'),
        data: payload,
      );
      return _child(response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось изменить профиль ребёнка.');
    }
  }

  @override
  Future<void> archiveChild(int childId) async {
    try {
      await client.dio.delete(ApiConfig.account('children/$childId/'));
      final selected = await getSelectedChildId();
      if (selected == childId) await clearSelectedChild();
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось удалить профиль ребёнка.');
    }
  }

  @override
  Future<void> selectChild(int childId) async {
    await getChild(childId);
    await client.childSessionStorage.saveSelectedChildId(childId);
  }

  @override
  Future<int?> getSelectedChildId() => client.childSessionStorage.readSelectedChildId();

  @override
  Future<void> clearSelectedChild() => client.childSessionStorage.clear();

  @override
  Future<bool> hasParentPin() async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        ApiConfig.account('parent-pin/'),
      );
      return response.data?['has_pin'] == true;
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось проверить родительский PIN.');
    }
  }

  @override
  Future<void> setParentPin({
    required String password,
    required String pin,
    required String pinConfirm,
  }) async {
    try {
      await client.dio.post<Map<String, dynamic>>(
        ApiConfig.account('parent-pin/'),
        data: {
          'password': password,
          'pin': pin,
          'pin_confirm': pinConfirm,
        },
      );
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось сохранить родительский PIN.');
    }
  }

  @override
  Future<bool> verifyParentPin(String pin) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        ApiConfig.account('parent-pin/verify/'),
        data: {'pin': pin},
      );
      return response.data?['valid'] == true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw const ParentApiException(
          'Слишком много попыток. Подождите минуту и попробуйте снова.',
          statusCode: 429,
        );
      }
      throw _apiException(e, 'Не удалось проверить родительский PIN.');
    }
  }

  @override
  Future<List<TariffPlan>> getTariffs() async {
    try {
      final response = await client.dio.get<dynamic>(ApiConfig.account('tariffs/'));
      return _rows(response.data).map(_tariff).toList();
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось загрузить тарифы.');
    }
  }

  @override
  Future<KindergartenPromoOffer> validatePromoCode(String code) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        ApiConfig.account('promo-codes/validate/'),
        data: {'code': code.trim()},
      );
      final data = response.data ?? const <String, dynamic>{};
      final kindergarten = _map(data['kindergarten']) ?? const <String, dynamic>{};
      final tariff = _map(data['tariff']) ?? const <String, dynamic>{};

      return KindergartenPromoOffer(
        code: data['code']?.toString() ?? code.trim().toUpperCase(),
        kindergartenId: _int(kindergarten['id']),
        kindergartenName: kindergarten['name']?.toString() ?? '',
        tariff: _tariff(tariff),
      );
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось проверить промокод.');
    }
  }

  @override
  Future<SubscriptionInfo?> getCurrentSubscription() async {
    try {
      final response = await client.dio.get<dynamic>(
        ApiConfig.account('subscriptions/current/'),
      );
      if (response.data == null) return null;
      final row = _map(response.data);
      return row == null ? null : _subscription(row);
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось загрузить подписку.');
    }
  }



  @override
  Future<SubscriptionInfo> startTrial() async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        ApiConfig.account('subscriptions/start-trial/'),
      );
      return _subscription(response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось активировать пробный период.');
    }
  }

  @override
  Future<SubscriptionInfo> disableAutoRenew(int subscriptionId) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        ApiConfig.account(
          'subscriptions/$subscriptionId/disable-auto-renew/',
        ),
      );
      return _subscription(response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось отключить автопродление.');
    }
  }

  @override
  Future<SubscriptionInfo> verifyGooglePlayPurchase(
    String purchaseToken, {
    String? promoCode,
  }) async {
    try {
      final normalizedPromo = promoCode?.trim();
      final response = await client.dio.post<Map<String, dynamic>>(
        ApiConfig.account('subscriptions/google-play/verify/'),
        data: {
          'purchase_token': purchaseToken,
          if (normalizedPromo != null && normalizedPromo.isNotEmpty)
            'promo_code': normalizedPromo,
        },
      );
      return _subscription(response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось подтвердить покупку Google Play.');
    }
  }

  @override
  Future<SubscriptionAccessStatus> getSubscriptionAccessStatus() async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        ApiConfig.account('subscription-status/'),
      );
      final data = response.data ?? const <String, dynamic>{};
      return SubscriptionAccessStatus(
        active: data['active'] == true,
        reason: data['reason']?.toString() ?? 'none',
        subscriptionId: data['subscription_id'] == null
            ? null
            : _int(data['subscription_id']),
        status: data['status']?.toString(),
        tariffId: data['tariff_id'] == null ? null : _int(data['tariff_id']),
        tariffTitle: data['tariff_title']?.toString(),
        endsAt: DateTime.tryParse(data['ends_at']?.toString() ?? ''),
      );
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось проверить подписку.');
    }
  }

  @override
  Future<SubscriptionInfo> createSubscription(
    int tariffId, {
    String? promoCode,
  }) async {
    try {
      final payload = <String, dynamic>{'tariff': tariffId};
      if (promoCode != null && promoCode.trim().isNotEmpty) {
        payload['promo_code'] = promoCode.trim();
      }

      final response = await client.dio.post<Map<String, dynamic>>(
        ApiConfig.account('subscriptions/'),
        data: payload,
      );
      return _subscription(response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось оформить тариф.');
    }
  }

  @override
  Future<FakePaymentResult> fakePurchase(
    int tariffId, {
    String? promoCode,
    required FakePaymentScenario scenario,
  }) async {
    try {
      final payload = <String, dynamic>{
        'tariff': tariffId,
        'scenario': scenario.apiValue,
      };
      if (promoCode != null && promoCode.trim().isNotEmpty) {
        payload['promo_code'] = promoCode.trim();
      }

      final response = await client.dio.post<Map<String, dynamic>>(
        ApiConfig.account('subscriptions/fake-purchase/'),
        data: payload,
      );
      final data = response.data ?? const <String, dynamic>{};
      final subscriptionRow = _map(data['subscription']);
      return FakePaymentResult(
        result: data['result']?.toString() ?? '',
        message: data['message']?.toString() ?? '',
        subscription:
            subscriptionRow == null ? null : _subscription(subscriptionRow),
      );
    } on DioException catch (e) {
      throw _apiException(e, 'Ошибка тестовой оплаты.');
    }
  }


  @override
  Future<void> resetFakeSubscription() async {
    try {
      await client.dio.post<Map<String, dynamic>>(
        ApiConfig.account('subscriptions/fake-reset/'),
      );
    } on DioException catch (e) {
      throw _apiException(e, 'Не удалось сбросить тестовую подписку.');
    }
  }



  TrialAccessInfo _trialAccess(Map<String, dynamic> row) => TrialAccessInfo(
        eligible: row['eligible'] == true,
        used: row['used'] == true,
        active: row['active'] == true,
        daysTotal: _int(row['days_total']) > 0 ? _int(row['days_total']) : 7,
        daysRemaining: _int(row['days_remaining']),
        startsAt: DateTime.tryParse(row['starts_at']?.toString() ?? ''),
        endsAt: DateTime.tryParse(row['ends_at']?.toString() ?? ''),
      );

  ChildProfileAccess _childAccess(Map<String, dynamic> row) => ChildProfileAccess(
        activeSubscription: row['active_subscription'] == true,
        subscriptionId: row['subscription_id'] == null ? null : _int(row['subscription_id']),
        tariffId: row['tariff_id'] == null ? null : _int(row['tariff_id']),
        tariffTitle: row['tariff_title']?.toString(),
        maxChildren: _int(row['max_children']),
        activeChildren: _int(row['active_children']),
        remainingSlots: _int(row['remaining_slots']),
        canCreateChild: row['can_create_child'] == true,
        reason: row['reason']?.toString(),
      );

  ParentAccount _parent(Map<String, dynamic> row) => ParentAccount(
        id: _int(row['id']),
        email: row['email']?.toString() ?? '',
        firstName: row['first_name']?.toString() ?? '',
        childrenCount: _int(row['children_count']),
        interfaceLanguage: row['interface_language']?.toString() ?? 'ru',
      );

  ChildProfile _child(Map<String, dynamic> row) {
    final language = _map(row['base_language']);
    final avatar = _map(row['icon']);
    final level = _map(row['level']);
    return ChildProfile(
      id: _int(row['id']),
      name: row['name']?.toString() ?? '',
      baseLanguage: language == null
          ? null
          : ChildLanguageInfo(
              id: _int(language['id']),
              title: language['title']?.toString() ?? '',
              code: language['code']?.toString() ?? '',
              iconUrl: _media(language['icon']),
            ),
      avatar: avatar == null
          ? null
          : ChildAvatarInfo(
              id: _int(avatar['id']),
              title: avatar['title']?.toString() ?? 'Аватар',
              imageUrl: _media(avatar['image']),
            ),
      totalXp: _int(row['total_xp']),
      level: level == null
          ? null
          : ChildLevelInfo(
              number: _int(level['number']),
              title: level['title']?.toString() ?? '',
              xpRequired: _int(level['xp_required']),
            ),
      isActive: row['is_active'] != false,
    );
  }

  TariffPlan _tariff(Map<String, dynamic> row) => TariffPlan(
        id: _int(row['id']),
        code: row['code']?.toString() ?? '',
        title: row['title']?.toString() ?? '',
        description: row['description']?.toString() ?? '',
        price: row['price']?.toString() ?? '0',
        currency: row['currency']?.toString() ?? 'KZT',
        durationDays: _int(row['duration_days']),
        maxChildren: _int(row['max_children']),
        googlePlayEnabled: row['google_play_enabled'] == true,
        googleProductId: row['google_product_id']?.toString() ?? '',
        googleBasePlanId: row['google_base_plan_id']?.toString() ?? '',
        appleStoreEnabled: row['apple_store_enabled'] == true,
        appleProductId: row['apple_product_id']?.toString() ?? '',
      );

  SubscriptionInfo _subscription(Map<String, dynamic> row) {
    final tariffRow = _map(row['tariff']) ?? const <String, dynamic>{};
    return SubscriptionInfo(
      id: _int(row['id']),
      tariff: _tariff(tariffRow),
      status: row['status']?.toString() ?? '',
      startsAt: DateTime.tryParse(row['starts_at']?.toString() ?? ''),
      endsAt: DateTime.tryParse(row['ends_at']?.toString() ?? ''),
      autoRenew: row['auto_renew'] == true,
      isCurrent: row['is_current'] == true,
      paymentProvider: row['payment_provider']?.toString() ?? '',
      externalPaymentId: row['external_payment_id']?.toString() ?? '',
      googleProductId: row['google_product_id']?.toString() ?? '',
      googleBasePlanId: row['google_base_plan_id']?.toString() ?? '',
      googleOrderId: row['google_order_id']?.toString() ?? '',
      googleSubscriptionState: row['google_subscription_state']?.toString() ?? '',
    );
  }

  String? _media(dynamic value) {
    final result = ApiConfig.absoluteMediaUrl(value?.toString());
    return result.isEmpty ? null : result;
  }

  static List<Map<String, dynamic>> _rows(dynamic data) {
    dynamic source = data;
    if (data is Map && data['results'] is List) source = data['results'];
    if (source is! List) return const [];
    return source.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Map<String, dynamic>? _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static ParentApiException _apiException(
    DioException error,
    String fallback,
  ) {
    return ParentApiException(
      _message(error, fallback),
      statusCode: error.response?.statusCode,
      isNetworkError: _isNetworkError(error),
    );
  }

  static bool _isNetworkError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return true;
      case DioExceptionType.unknown:
        return error.response == null;
      default:
        return false;
    }
  }

  static String _message(DioException error, String fallback) {
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['detail'] ?? data['error'] ?? data['non_field_errors'];
      if (detail is List && detail.isNotEmpty) return detail.first.toString();
      if (detail is String && detail.isNotEmpty) return detail;
      for (final value in data.values) {
        if (value is List && value.isNotEmpty) return value.first.toString();
        if (value is String && value.isNotEmpty) return value;
        if (value is Map) {
          for (final nested in value.values) {
            if (nested is List && nested.isNotEmpty) return nested.first.toString();
            if (nested is String && nested.isNotEmpty) return nested;
          }
        }
      }
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.transformTimeout) {
      return 'Нет соединения с Django. Проверь интернет и доступность сервера.';
    }
    return '$fallback (HTTP ${error.response?.statusCode ?? '-'})';
  }
}
