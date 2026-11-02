import logging
import secrets
from datetime import timedelta
from uuid import uuid4

from django.db import transaction
from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.core.mail import send_mail
from django.utils import timezone

from rest_framework import status
from rest_framework.decorators import action
from rest_framework.generics import CreateAPIView
from rest_framework.mixins import CreateModelMixin, ListModelMixin, RetrieveModelMixin
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.viewsets import ModelViewSet, ReadOnlyModelViewSet, GenericViewSet
from rest_framework_simplejwt.tokens import RefreshToken

from .models import (
    User, Avatar, ChildProfile, TariffPlan, Subscription, PromoCode, PromoCodeUsage,
    AccountDeletionVerification,
)
from .services import (
    TRIAL_DEFAULT_DAYS,
    TRIAL_TARIFF_CODE,
    get_active_subscription,
    get_child_profile_access,
    get_subscription_access,
    get_trial_access,
)
from .fake_payments import fake_payments_enabled_for
from .google_play import (
    GooglePlayConfigurationError,
    GooglePlayVerificationError,
    apply_google_subscription,
    cancel_google_subscription,
    refresh_parent_google_subscription,
)
from .serializers import (
    ParentRegisterSerializer,
    ParentLoginSerializer,
    ParentSerializer,
    ParentSettingsSerializer,
    ChangePasswordSerializer,
    DeleteAccountSerializer,
    DeleteAccountRequestCodeSerializer,
    DeleteAccountConfirmCodeSerializer,
    AvatarSerializer,
    ChildProfileSerializer,
    ChildProfileWriteSerializer,
    TariffPlanSerializer,
    SubscriptionSerializer,
    SubscriptionCreateSerializer,
    PromoCodeValidateSerializer,
    PromoCodeRedeemSerializer,
    FakePaymentPurchaseSerializer,
    GooglePlayPurchaseVerifySerializer,
)


logger = logging.getLogger('django.request')

class RegisterView(CreateAPIView):
    queryset = User.objects.all()
    serializer_class = ParentRegisterSerializer
    permission_classes = [AllowAny]
    # Публичный endpoint не должен пытаться валидировать старый JWT.
    # После удаления аккаунта приложение может ещё отправлять токен удалённого пользователя.
    authentication_classes = []


class ParentLoginView(APIView):
    permission_classes = [AllowAny]
    # Логин должен работать независимо от Authorization-заголовка клиента.
    authentication_classes = []

    def post(self, request):
        serializer = ParentLoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data['user']

        refresh = RefreshToken.for_user(user)
        return Response({
            'refresh': str(refresh),
            'access': str(refresh.access_token),
            'parent': ParentSerializer(user, context={'request': request}).data,
        })


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(
            ParentSerializer(request.user, context={'request': request}).data
        )

    def patch(self, request):
        serializer = ParentSettingsSerializer(
            request.user,
            data=request.data,
            partial=True,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(
            ParentSerializer(request.user, context={'request': request}).data
        )


class ChangePasswordView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = ChangePasswordSerializer(
            data=request.data,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(
            {'detail': 'Пароль успешно изменён.'},
            status=status.HTTP_200_OK,
        )


class DeleteAccountView(APIView):
    """Безвозвратно удаляет родительский аккаунт и связанные данные.

    User является корнем пользовательских данных. Связанные ChildProfile,
    Subscription и LegalAcceptance используют CASCADE; PromoCodeUsage обезличивается через SET_NULL;
    учебные данные ребёнка, в свою очередь, каскадно удаляются вместе с
    ChildProfile. Общие справочники, тарифы, промокоды, языки, аватары и
    юридические документы не удаляются.
    """

    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = DeleteAccountSerializer(
            data=request.data,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)

        # Берём строку пользователя под блокировку, чтобы параллельный запрос
        # не смог изменить связанные данные в момент удаления.
        with transaction.atomic():
            user = User.objects.select_for_update().get(pk=request.user.pk)
            user.delete()

        return Response(
            {'detail': 'Аккаунт и связанные с ним данные удалены.'},
            status=status.HTTP_200_OK,
        )


class DeleteAccountRequestCodeView(APIView):
    """Публично запрашивает одноразовый код удаления аккаунта по email.

    Ответ одинаков для существующего и несуществующего email, чтобы endpoint
    нельзя было использовать для проверки регистрации конкретного адреса.
    """

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'account_delete_request'

    def _generic_response(self):
        ttl_minutes = int(getattr(settings, 'ACCOUNT_DELETION_CODE_TTL_MINUTES', 15))
        resend_seconds = int(getattr(settings, 'ACCOUNT_DELETION_CODE_RESEND_SECONDS', 60))
        return {
            'detail': (
                'Если аккаунт с таким email существует, код подтверждения '
                'отправлен на указанную почту.'
            ),
            'expires_in_seconds': ttl_minutes * 60,
            'resend_after_seconds': resend_seconds,
        }

    def post(self, request):
        serializer = DeleteAccountRequestCodeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data['email']

        user = User.objects.filter(email__iexact=email).first()
        if user is None:
            return Response(self._generic_response(), status=status.HTTP_200_OK)

        ttl_minutes = int(getattr(settings, 'ACCOUNT_DELETION_CODE_TTL_MINUTES', 15))
        resend_seconds = int(getattr(settings, 'ACCOUNT_DELETION_CODE_RESEND_SECONDS', 60))
        now = timezone.now()

        try:
            with transaction.atomic():
                user = User.objects.select_for_update().get(pk=user.pk)
                verification = (
                    AccountDeletionVerification.objects
                    .select_for_update()
                    .filter(user=user)
                    .first()
                )

                if verification is not None:
                    elapsed = (now - verification.sent_at).total_seconds()
                    if elapsed < resend_seconds:
                        return Response(self._generic_response(), status=status.HTTP_200_OK)

                code = f'{secrets.randbelow(1_000_000):06d}'
                code_hash = make_password(code)
                expires_at = now + timedelta(minutes=ttl_minutes)

                if verification is None:
                    verification = AccountDeletionVerification(user=user)
                verification.code_hash = code_hash
                verification.expires_at = expires_at
                verification.attempts = 0
                verification.sent_at = now
                verification.save()

                subject = 'Код подтверждения удаления аккаунта Zenvia Kids'
                message = (
                    'Вы запросили удаление родительского аккаунта Zenvia Kids.\n\n'
                    f'Код подтверждения: {code}\n\n'
                    f'Код действует {ttl_minutes} минут.\n'
                    'Если вы не запрашивали удаление аккаунта, просто проигнорируйте это письмо.\n\n'
                    'Никому не сообщайте этот код.'
                )
                html_message = (
                    '<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto">'
                    '<h2 style="color:#234b85">Zenvia Kids</h2>'
                    '<p>Вы запросили удаление родительского аккаунта.</p>'
                    '<p>Код подтверждения:</p>'
                    f'<div style="font-size:32px;font-weight:700;letter-spacing:8px;'
                    f'padding:16px 0;color:#234b85">{code}</div>'
                    f'<p>Код действует {ttl_minutes} минут.</p>'
                    '<p>Если вы не запрашивали удаление аккаунта, просто проигнорируйте это письмо.</p>'
                    '<p><strong>Никому не сообщайте этот код.</strong></p>'
                    '</div>'
                )

                send_mail(
                    subject,
                    message,
                    settings.DEFAULT_FROM_EMAIL,
                    [user.email],
                    html_message=html_message,
                    using='default',
                )
        except Exception:
            logger.exception('Failed to send account deletion code email=%s', email)
            return Response(
                {'detail': 'Не удалось отправить код. Повторите попытку позже.'},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        return Response(self._generic_response(), status=status.HTTP_200_OK)


class DeleteAccountConfirmCodeView(APIView):
    """Проверяет email + одноразовый код и безвозвратно удаляет аккаунт."""

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'account_delete_confirm'

    invalid_response = {'detail': 'Неверный или просроченный код подтверждения.'}

    def post(self, request):
        serializer = DeleteAccountConfirmCodeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data['email']
        code = serializer.validated_data['code']
        max_attempts = int(getattr(settings, 'ACCOUNT_DELETION_CODE_MAX_ATTEMPTS', 5))
        now = timezone.now()

        with transaction.atomic():
            user = (
                User.objects
                .select_for_update()
                .filter(email__iexact=email)
                .first()
            )
            if user is None:
                return Response(self.invalid_response, status=status.HTTP_400_BAD_REQUEST)

            verification = (
                AccountDeletionVerification.objects
                .select_for_update()
                .filter(user=user)
                .first()
            )
            if verification is None:
                return Response(self.invalid_response, status=status.HTTP_400_BAD_REQUEST)

            if verification.expires_at <= now or verification.attempts >= max_attempts:
                verification.delete()
                return Response(self.invalid_response, status=status.HTTP_400_BAD_REQUEST)

            if not check_password(code, verification.code_hash):
                verification.attempts += 1
                if verification.attempts >= max_attempts:
                    verification.delete()
                else:
                    verification.save(update_fields=['attempts', 'updated_at'])
                return Response(self.invalid_response, status=status.HTTP_400_BAD_REQUEST)

            # User является корнем персональных данных проекта. Связанные
            # ChildProfile, учебный прогресс, Subscription и LegalAcceptance удаляются
            # каскадно; PromoCodeUsage остаётся обезличенной записью факта использования.
            user.delete()

        return Response(
            {'detail': 'Аккаунт и связанные с ним данные удалены.'},
            status=status.HTTP_200_OK,
        )


class AvatarViewSet(ReadOnlyModelViewSet):
    queryset = Avatar.objects.all().order_by('id')
    serializer_class = AvatarSerializer
    permission_classes = [AllowAny]
    authentication_classes = []


class ChildProfileViewSet(ModelViewSet):
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return (
            ChildProfile.objects
            .filter(parent=self.request.user)
            .select_related('base_language', 'icon')
            .order_by('id')
        )

    def get_serializer_class(self):
        if self.action in ('create', 'update', 'partial_update'):
            return ChildProfileWriteSerializer
        return ChildProfileSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        # Lock the parent row so two concurrent requests cannot exceed the
        # tariff's child-profile limit. The backend is the source of truth;
        # the Flutter-side disabled button is only UX.
        with transaction.atomic():
            parent = User.objects.select_for_update().get(pk=request.user.pk)
            access = get_child_profile_access(parent)
            if not access['can_create_child']:
                return Response(
                    {
                        'detail': access['reason'],
                        'child_access': access,
                    },
                    status=status.HTTP_403_FORBIDDEN,
                )
            child = serializer.save(parent=parent)

        return Response(
            ChildProfileSerializer(child, context={'request': request}).data,
            status=status.HTTP_201_CREATED,
        )

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop('partial', False)
        child = self.get_object()
        serializer = self.get_serializer(child, data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        child = serializer.save()
        return Response(
            ChildProfileSerializer(child, context={'request': request}).data
        )

    def destroy(self, request, *args, **kwargs):
        # Не удаляем учебную историю физически; профиль можно восстановить из БД.
        child = self.get_object()
        child.is_active = False
        child.save(update_fields=['is_active'])
        return Response(status=status.HTTP_204_NO_CONTENT)


class TariffPlanViewSet(ReadOnlyModelViewSet):
    serializer_class = TariffPlanSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return (
            TariffPlan.objects
            .filter(is_active=True, is_public=True)
            .order_by('position', 'id')
        )


class PromoCodeValidateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = PromoCodeValidateSerializer(
            data=request.data,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        promo = serializer.validated_data['promo']

        kindergarten = None
        if promo.kindergarten_id:
            kindergarten = {
                'id': promo.kindergarten_id,
                'name': promo.kindergarten.name,
            }

        return Response({
            'valid': True,
            'code': promo.code,
            'mode': promo.mode,
            'channel': promo.channel,
            'display_name': promo.display_name,
            'partner_name': promo.partner_name,
            'campaign_name': promo.campaign_name,
            'manager_name': promo.manager_name,
            'access_days': (
                promo.effective_access_days
                if promo.mode == PromoCode.MODE_DIRECT_ACCESS
                else None
            ),
            'kindergarten': kindergarten,
            'tariff': TariffPlanSerializer(
                promo.tariff,
                context={'request': request},
            ).data,
        })


class PromoCodeRedeemView(APIView):
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def post(self, request):
        serializer = PromoCodeRedeemSerializer(
            data=request.data,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        validated_promo = serializer.validated_data['promo']

        parent = User.objects.select_for_update().get(pk=request.user.pk)
        promo = (
            PromoCode.objects
            .select_for_update()
            .select_related('kindergarten', 'tariff')
            .get(pk=validated_promo.pk)
        )

        error = promo.unavailability_reason(parent)
        if error:
            return Response({'code': [error]}, status=status.HTTP_400_BAD_REQUEST)
        if promo.mode != PromoCode.MODE_DIRECT_ACCESS:
            return Response(
                {'code': ['Этот промокод используется вместе с оплатой через Google Play.']},
                status=status.HTTP_400_BAD_REQUEST,
            )

        active = get_active_subscription(parent)
        has_pending = parent.subscriptions.filter(
            status=Subscription.STATUS_PENDING,
        ).exists()
        if active is not None or has_pending:
            return Response(
                {
                    'detail': (
                        'Нельзя активировать код, пока есть активная подписка '
                        'или подписка, ожидающая оплаты.'
                    )
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        tariff = promo.tariff
        children_count = parent.children.filter(is_active=True).count()
        if children_count > tariff.max_children:
            return Response(
                {
                    'detail': (
                        f'Тариф поддерживает максимум {tariff.max_children} '
                        f'профилей детей, а у вас уже создано {children_count}.'
                    )
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        now = timezone.now()
        subscription = Subscription.objects.create(
            parent=parent,
            tariff=tariff,
            status=Subscription.STATUS_ACTIVE,
            starts_at=now,
            ends_at=now + timedelta(days=promo.effective_access_days),
            auto_renew=False,
            payment_provider='promo_code',
            external_payment_id=f'promo:{promo.code}',
        )
        PromoCodeUsage.objects.create(
            promo_code=promo,
            parent=parent,
            subscription=subscription,
        )

        return Response(
            SubscriptionSerializer(
                subscription,
                context={'request': request},
            ).data,
            status=status.HTTP_201_CREATED,
        )


class SubscriptionViewSet(
    CreateModelMixin,
    ListModelMixin,
    RetrieveModelMixin,
    GenericViewSet,
):
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return (
            Subscription.objects
            .filter(parent=self.request.user)
            .select_related(
                'tariff',
                'promo_usage__promo_code__kindergarten',
            )
            .order_by('-created_at')
        )

    def get_serializer_class(self):
        if self.action == 'create':
            return SubscriptionCreateSerializer
        return SubscriptionSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        subscription = serializer.save()
        return Response(
            SubscriptionSerializer(subscription, context={'request': request}).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=False, methods=['post'], url_path='start-trial')
    @transaction.atomic
    def start_trial(self, request):
        # Lock the parent row so two simultaneous taps cannot create two trials.
        parent = User.objects.select_for_update().get(pk=request.user.pk)

        if Subscription.objects.filter(
            parent=parent,
            payment_provider='trial',
        ).exists():
            return Response(
                {'detail': 'Пробный период для этого аккаунта уже использован.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if (
            get_active_subscription(parent) is not None
            or parent.subscriptions.filter(
                status=Subscription.STATUS_PENDING,
            ).exists()
        ):
            return Response(
                {
                    'detail': (
                        'Нельзя запустить пробный период, пока есть активная '
                        'подписка или подписка, ожидающая оплаты.'
                    )
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Keep the historical tariff code for compatibility with existing
        # subscriptions. Existing admin on/off state is preserved, while the
        # duration/title are normalised to the current one-day trial.
        tariff, created = TariffPlan.objects.get_or_create(
            code=TRIAL_TARIFF_CODE,
            defaults={
                'title': 'Пробный период 1 день',
                'description': 'Бесплатный пробный доступ на 1 день без автопродления.',
                'price': '0.00',
                'currency': 'KZT',
                'duration_days': TRIAL_DEFAULT_DAYS,
                'max_children': 2,
                'is_active': True,
                'is_public': False,
                'position': 0,
            },
        )
        if not created and (
            tariff.duration_days != TRIAL_DEFAULT_DAYS
            or tariff.title != 'Пробный период 1 день'
        ):
            tariff.duration_days = TRIAL_DEFAULT_DAYS
            tariff.title = 'Пробный период 1 день'
            tariff.description = 'Бесплатный пробный доступ на 1 день без автопродления.'
            tariff.save(update_fields=['duration_days', 'title', 'description'])
        if not tariff.is_active:
            return Response(
                {'detail': 'Пробный период временно отключён.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        now = timezone.now()
        subscription = Subscription.objects.create(
            parent=parent,
            tariff=tariff,
            status=Subscription.STATUS_ACTIVE,
            starts_at=now,
            ends_at=now + timedelta(days=tariff.duration_days),
            auto_renew=False,
            payment_provider='trial',
            external_payment_id='',
        )

        return Response(
            SubscriptionSerializer(
                subscription,
                context={'request': request},
            ).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=['post'], url_path='disable-auto-renew')
    @transaction.atomic
    def disable_auto_renew(self, request, pk=None):
        """Отключает автопродление, не отменяя текущий оплаченный период.

        Подписка продолжает действовать до ends_at. Для trial автопродление
        изначально выключено. Когда будет подключён реальный Google Play
        Billing, здесь также нужно отменять renewal у платёжного провайдера.
        """
        subscription = (
            Subscription.objects
            .select_for_update()
            .filter(pk=pk, parent=request.user)
            .select_related('tariff')
            .first()
        )
        if subscription is None:
            return Response(
                {'detail': 'Подписка не найдена.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        if not subscription.is_current:
            return Response(
                {'detail': 'Автопродление можно отключить только у активной подписки.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if subscription.payment_provider == 'google_play':
            if not subscription.google_purchase_token:
                return Response(
                    {'detail': 'У подписки отсутствует Google Play purchase token.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            try:
                cancel_google_subscription(subscription.google_purchase_token)
                subscription = apply_google_subscription(
                    request.user,
                    subscription.google_purchase_token,
                    acknowledge=False,
                )
                if subscription.auto_renew:
                    subscription.auto_renew = False
                    subscription.save(update_fields=['auto_renew', 'updated_at'])
            except GooglePlayConfigurationError as exc:
                return Response(
                    {'detail': str(exc)},
                    status=status.HTTP_503_SERVICE_UNAVAILABLE,
                )
            except GooglePlayVerificationError as exc:
                return Response(
                    {'detail': str(exc)},
                    status=status.HTTP_400_BAD_REQUEST,
                )
        elif subscription.auto_renew:
            # Trial/fake/local providers keep the existing local behavior.
            subscription.auto_renew = False
            subscription.save(update_fields=['auto_renew', 'updated_at'])

        return Response(
            SubscriptionSerializer(
                subscription,
                context={'request': request},
            ).data,
            status=status.HTTP_200_OK,
        )

    @action(detail=False, methods=['post'], url_path='google-play/verify')
    def google_play_verify(self, request):
        serializer = GooglePlayPurchaseVerifySerializer(data=request.data)
        if not serializer.is_valid():
            logger.warning(
                'Google Play verify invalid request user=%s errors=%s',
                getattr(request.user, 'pk', None),
                serializer.errors,
            )
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        promo = None
        promo_code = (serializer.validated_data.get('promo_code') or '').strip()
        if promo_code:
            promo_serializer = PromoCodeValidateSerializer(
                data={'code': promo_code},
                context={'request': request},
            )
            if not promo_serializer.is_valid():
                logger.warning(
                    'Google Play verify promo rejected user=%s code=%s errors=%s',
                    getattr(request.user, 'pk', None),
                    promo_code,
                    promo_serializer.errors,
                )
                return Response(
                    promo_serializer.errors,
                    status=status.HTTP_400_BAD_REQUEST,
                )
            promo = promo_serializer.validated_data['promo']
            if promo.mode != PromoCode.MODE_GOOGLE_PLAY:
                return Response(
                    {
                        'promo_code': [
                            'Этот промокод активирует доступ напрямую и не используется для Google Play.'
                        ]
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

        try:
            with transaction.atomic():
                subscription = apply_google_subscription(
                    request.user,
                    serializer.validated_data['purchase_token'],
                )

                if promo is not None:
                    promo = (
                        PromoCode.objects
                        .select_for_update()
                        .select_related('kindergarten', 'tariff')
                        .get(pk=promo.pk)
                    )
                    promo_error = promo.unavailability_reason(request.user)
                    if promo_error:
                        raise GooglePlayVerificationError(promo_error)
                    if promo.mode != PromoCode.MODE_GOOGLE_PLAY:
                        raise GooglePlayVerificationError(
                            'Этот промокод не предназначен для оплаты через Google Play.'
                        )
                    if subscription.tariff_id != promo.tariff_id:
                        raise GooglePlayVerificationError(
                            'Купленный Google Play тариф не соответствует промокоду.'
                        )

                    usage, created = PromoCodeUsage.objects.get_or_create(
                        subscription=subscription,
                        defaults={
                            'promo_code': promo,
                            'parent': request.user,
                        },
                    )
                    if not created and (
                        usage.promo_code_id != promo.id
                        or usage.parent_id != request.user.id
                    ):
                        raise GooglePlayVerificationError(
                            'Эта подписка уже связана с другим промокодом.'
                        )

                    logger.warning(
                        'Google Play promo usage %s user=%s subscription=%s promo=%s',
                        'created' if created else 'already_exists',
                        getattr(request.user, 'pk', None),
                        subscription.pk,
                        promo.code,
                    )
        except GooglePlayConfigurationError as exc:
            logger.warning(
                'Google Play verify configuration error user=%s detail=%s',
                getattr(request.user, 'pk', None),
                str(exc),
            )
            return Response({'detail': str(exc)}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        except GooglePlayVerificationError as exc:
            logger.warning(
                'Google Play verify rejected user=%s detail=%s',
                getattr(request.user, 'pk', None),
                str(exc),
            )
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        logger.warning(
            'Google Play verify success user=%s subscription=%s',
            getattr(request.user, 'pk', None),
            subscription.pk,
        )
        return Response(
            SubscriptionSerializer(subscription, context={'request': request}).data,
            status=status.HTTP_200_OK,
        )

    @action(detail=False, methods=['post'], url_path='fake-purchase')
    def fake_purchase(self, request):
        if not fake_payments_enabled_for(request.user):
            return Response(
                {
                    'detail': (
                        'Тестовая оплата отключена или этот аккаунт не включён '
                        'в список тестировщиков.'
                    )
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        serializer = FakePaymentPurchaseSerializer(
            data=request.data,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        scenario = serializer.validated_data.get(
            'scenario',
            FakePaymentPurchaseSerializer.SCENARIO_SUCCESS,
        )

        if scenario == FakePaymentPurchaseSerializer.SCENARIO_DECLINED:
            return Response({
                'result': 'declined',
                'message': 'Тестовый банк отклонил платёж.',
                'subscription': None,
            })

        if scenario == FakePaymentPurchaseSerializer.SCENARIO_CANCELLED:
            return Response({
                'result': 'cancelled',
                'message': 'Пользователь отменил тестовую оплату.',
                'subscription': None,
            })

        if scenario == FakePaymentPurchaseSerializer.SCENARIO_NETWORK_ERROR:
            return Response(
                {
                    'result': 'network_error',
                    'detail': 'Имитация ошибки сети платёжного провайдера.',
                },
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        subscription = serializer.save()
        subscription.payment_provider = 'fake'
        subscription.external_payment_id = f'FAKE-{uuid4().hex.upper()}'

        if scenario == FakePaymentPurchaseSerializer.SCENARIO_SUCCESS:
            now = timezone.now()
            subscription.status = Subscription.STATUS_ACTIVE
            subscription.starts_at = now
            subscription.ends_at = now + timedelta(
                days=subscription.tariff.duration_days,
            )
            # Fake payment emulates a recurring paid subscription so the
            # auto-renew management flow can be tested in the app.
            subscription.auto_renew = True
            result = 'success'
            message = 'Тестовая оплата успешно проведена.'
        else:
            # pending deliberately remains unpaid so the UI can be tested.
            subscription.status = Subscription.STATUS_PENDING
            result = 'pending'
            message = 'Тестовый платёж оставлен в ожидании.'

        subscription.save(update_fields=[
            'status',
            'starts_at',
            'ends_at',
            'auto_renew',
            'payment_provider',
            'external_payment_id',
            'updated_at',
        ])

        return Response({
            'result': result,
            'message': message,
            'subscription': SubscriptionSerializer(
                subscription,
                context={'request': request},
            ).data,
        })

    @action(detail=False, methods=['post'], url_path='fake-reset')
    def fake_reset(self, request):
        if not fake_payments_enabled_for(request.user):
            return Response(
                {
                    'detail': (
                        'Тестовая оплата отключена или этот аккаунт не включён '
                        'в список тестировщиков.'
                    )
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        fake_subscriptions = Subscription.objects.filter(
            parent=request.user,
            payment_provider='fake',
        )
        deleted_count = fake_subscriptions.count()
        # PromoCodeUsage has CASCADE from Subscription, so test promo usage is
        # removed too and the same code can be tested again.
        fake_subscriptions.delete()

        return Response({
            'reset': True,
            'deleted_subscriptions': deleted_count,
        })

    @action(detail=False, methods=['get'], url_path='current')
    def current(self, request):
        refresh_parent_google_subscription(request.user)
        subscriptions = self.get_queryset()
        current = next((item for item in subscriptions if item.is_current), None)
        if current is None:
            current = subscriptions.filter(status=Subscription.STATUS_PENDING).first()
        if current is None:
            return Response(None, status=status.HTTP_200_OK)
        return Response(
            SubscriptionSerializer(current, context={'request': request}).data
        )


class SubscriptionStatusView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        refresh_parent_google_subscription(request.user)
        return Response(get_subscription_access(request.user))


class DashboardView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        # Keep the local database in sync when the parent opens the dashboard.
        # The refresh function has a short cache, but bypasses it once ends_at
        # has been reached, so an expired Google Play subscription is updated
        # promptly instead of remaining STATUS_ACTIVE in the database.
        refresh_parent_google_subscription(request.user)

        children = (
            ChildProfile.objects
            .filter(parent=request.user, is_active=True)
            .select_related('base_language', 'icon')
            .order_by('id')
        )
        subscriptions = (
            Subscription.objects
            .filter(parent=request.user)
            .select_related('tariff')
            .order_by('-created_at')
        )
        current = next((item for item in subscriptions if item.is_current), None)
        if current is None:
            current = subscriptions.filter(status=Subscription.STATUS_PENDING).first()

        return Response({
            'parent': ParentSerializer(request.user, context={'request': request}).data,
            'children': ChildProfileSerializer(
                children,
                many=True,
                context={'request': request},
            ).data,
            'subscription': (
                SubscriptionSerializer(current, context={'request': request}).data
                if current else None
            ),
            'child_access': get_child_profile_access(request.user),
            'trial': get_trial_access(request.user),
        })
