import '../models/child_profile.dart';
import '../models/parent_account.dart';
import '../models/registration_option.dart';
import '../models/subscription.dart';

abstract class ParentRepository {
  Future<ParentDashboard> getDashboard();
  Future<List<ChildProfile>> getChildren();
  Future<ChildProfile> getChild(int id);

  Future<List<RegistrationLanguage>> getLanguages();
  Future<List<AvatarOption>> getAvatars();

  Future<ChildProfile> createChild({
    required String name,
    required int baseLanguageId,
    required int avatarId,
  });

  Future<ChildProfile> updateChild({
    required int childId,
    String? name,
    int? baseLanguageId,
    int? avatarId,
  });

  Future<void> archiveChild(int childId);

  Future<void> selectChild(int childId);
  Future<int?> getSelectedChildId();
  Future<void> clearSelectedChild();

  Future<bool> hasParentPin();
  Future<void> setParentPin({
    required String password,
    required String pin,
    required String pinConfirm,
  });
  Future<bool> verifyParentPin(String pin);

  Future<List<TariffPlan>> getTariffs();
  Future<PromoOffer> validatePromoCode(String code);
  Future<SubscriptionInfo> redeemPromoCode(String code);
  Future<SubscriptionInfo?> getCurrentSubscription();
  Future<SubscriptionInfo> startTrial();
  Future<SubscriptionInfo> disableAutoRenew(int subscriptionId);
  Future<SubscriptionInfo> verifyGooglePlayPurchase(
    String purchaseToken, {
    String? promoCode,
  });
  Future<SubscriptionAccessStatus> getSubscriptionAccessStatus();
  Future<SubscriptionInfo> createSubscription(
    int tariffId, {
    String? promoCode,
  });
  Future<FakePaymentResult> fakePurchase(
    int tariffId, {
    String? promoCode,
    required FakePaymentScenario scenario,
  });
  Future<void> resetFakeSubscription();
}

class ParentApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool isNetworkError;

  const ParentApiException(
    this.message, {
    this.statusCode,
    this.isNetworkError = false,
  });

  @override
  String toString() => message;
}
