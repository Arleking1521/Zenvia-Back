from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView

from .views import (
    RegisterView,
    ParentLoginView,
    MeView,
    ChangePasswordView,
    DeleteAccountView,
    DeleteAccountRequestCodeView,
    DeleteAccountConfirmCodeView,
    AvatarViewSet,
    ChildProfileViewSet,
    TariffPlanViewSet,
    SubscriptionViewSet,
    DashboardView,
    PromoCodeValidateView,
    PromoCodeRedeemView,
    SubscriptionStatusView,
)

from .pin_views import ParentPinView, ParentPinVerifyView

router = DefaultRouter()
router.register('children', ChildProfileViewSet, basename='children')
router.register('tariffs', TariffPlanViewSet, basename='tariffs')
router.register('subscriptions', SubscriptionViewSet, basename='subscriptions')

avatar_list = AvatarViewSet.as_view({'get': 'list'})

urlpatterns = [
    path('register/', RegisterView.as_view(), name='register'),
    path('login/', ParentLoginView.as_view(), name='login'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('me/', MeView.as_view(), name='me'),
    path('dashboard/', DashboardView.as_view(), name='dashboard'),
    path('change-password/', ChangePasswordView.as_view(), name='change_password'),
    path('delete-account/', DeleteAccountView.as_view(), name='delete_account'),
    path('delete-account/request-code/', DeleteAccountRequestCodeView.as_view(), name='delete_account_request_code'),
    path('delete-account/confirm-code/', DeleteAccountConfirmCodeView.as_view(), name='delete_account_confirm_code'),
    path('parent-pin/', ParentPinView.as_view(), name='parent_pin'),
    path('parent-pin/verify/', ParentPinVerifyView.as_view(), name='parent_pin_verify'),
    path('avatars/', avatar_list, name='avatars'),
    path('promo-codes/validate/', PromoCodeValidateView.as_view(), name='promo_code_validate'),
    path('promo-codes/redeem/', PromoCodeRedeemView.as_view(), name='promo_code_redeem'),
    path('subscription-status/', SubscriptionStatusView.as_view(), name='subscription_status'),
    path('', include(router.urls)),
]
