from django.utils import timezone
from rest_framework import serializers

from .models import (
    User,
    Avatar,
    ChildProfile,
    TariffPlan,
    Subscription,
    PromoCode,
    PromoCodeUsage,
)
from word_learning.models import Language, Level


class AvatarSerializer(serializers.ModelSerializer):
    class Meta:
        model = Avatar
        fields = ['id', 'title', 'image']


class ParentRegisterSerializer(serializers.ModelSerializer):
    email = serializers.EmailField(
        required=True,
        error_messages={
            'blank': 'Введите email.',
            'required': 'Введите email.',
            'invalid': 'Введите корректный email.',
        },
    )
    first_name = serializers.CharField(
        min_length=2,
        max_length=128,
        error_messages={
            'blank': 'Введите имя родителя.',
            'required': 'Введите имя родителя.',
        },
    )
    password = serializers.CharField(
        write_only=True,
        min_length=6,
        error_messages={
            'blank': 'Введите пароль.',
            'required': 'Введите пароль.',
            'min_length': 'Пароль должен содержать минимум 6 символов.',
        },
    )
    password_confirm = serializers.CharField(
        write_only=True,
        min_length=6,
        error_messages={
            'blank': 'Подтвердите пароль.',
            'required': 'Подтвердите пароль.',
            'min_length': 'Пароль должен содержать минимум 6 символов.',
        },
    )
    accept_privacy_policy = serializers.BooleanField(
        write_only=True,
        required=True,
        error_messages={
            'required': 'Необходимо принять Политику конфиденциальности.',
        },
    )
    accept_terms_of_use = serializers.BooleanField(
        write_only=True,
        required=True,
        error_messages={
            'required': 'Необходимо принять Условия использования.',
        },
    )

    class Meta:
        model = User
        fields = [
            'id',
            'email',
            'first_name',
            'interface_language',
            'password',
            'password_confirm',
            'accept_privacy_policy',
            'accept_terms_of_use',
        ]
        read_only_fields = ['id']

    def validate_email(self, value):
        value = value.strip().lower()
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError('Родитель с таким email уже зарегистрирован.')
        if User.objects.filter(username__iexact=value).exists():
            raise serializers.ValidationError('Этот email уже используется.')
        return value

    def validate(self, attrs):
        errors = {}
        if attrs.get('password') != attrs.get('password_confirm'):
            errors['password_confirm'] = 'Пароли не совпадают.'
        if attrs.get('accept_privacy_policy') is not True:
            errors['accept_privacy_policy'] = (
                'Необходимо принять Политику конфиденциальности.'
            )
        if attrs.get('accept_terms_of_use') is not True:
            errors['accept_terms_of_use'] = (
                'Необходимо принять Условия использования.'
            )
        if errors:
            raise serializers.ValidationError(errors)
        return attrs

    def create(self, validated_data):
        validated_data.pop('password_confirm')
        validated_data.pop('accept_privacy_policy')
        validated_data.pop('accept_terms_of_use')
        password = validated_data.pop('password')
        email = validated_data['email'].lower()

        user = User(
            username=email,  # техническое поле, внешняя авторизация идёт по email
            email=email,
            first_name=validated_data['first_name'].strip(),
            interface_language=validated_data.get(
                'interface_language',
                User.INTERFACE_LANGUAGE_RU,
            ),
        )
        user.set_password(password)
        user.save()

        # Если утверждённые юридические документы уже опубликованы,
        # фиксируем точные версии, действовавшие на момент регистрации.
        # До публикации финальных документов регистрация остаётся доступной,
        # но запись LegalAcceptance не создаётся.
        try:
            from legal_documents.models import (
                LegalAcceptance,
                LegalDocumentVersion,
            )
            from legal_documents.views import get_published_document

            for document_type in (
                LegalDocumentVersion.TYPE_PRIVACY,
                LegalDocumentVersion.TYPE_TERMS,
            ):
                document = get_published_document(
                    document_type,
                    user.interface_language,
                )
                if document is not None:
                    LegalAcceptance.objects.get_or_create(
                        user=user,
                        document=document,
                    )
        except (ImportError, RuntimeError):
            # Позволяет account-приложению не ломаться, если модуль юридических
            # документов ещё не установлен в конкретном окружении.
            pass

        return user


class ParentLoginSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)
    password = serializers.CharField(write_only=True, required=True)

    def validate(self, attrs):
        email = attrs['email'].strip().lower()
        password = attrs['password']

        user = User.objects.filter(email__iexact=email).first()
        if not user or not user.check_password(password):
            raise serializers.ValidationError('Неверный email или пароль.')
        if not user.is_active:
            raise serializers.ValidationError('Аккаунт отключён.')

        attrs['user'] = user
        return attrs


class ParentSerializer(serializers.ModelSerializer):
    children_count = serializers.IntegerField(source='children.count', read_only=True)

    class Meta:
        model = User
        fields = [
            'id',
            'email',
            'first_name',
            'interface_language',
            'children_count',
        ]


class ParentSettingsSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['first_name', 'interface_language']

    def validate_first_name(self, value):
        value = value.strip()
        if len(value) < 2:
            raise serializers.ValidationError('Имя родителя должно содержать минимум 2 символа.')
        return value


class ChangePasswordSerializer(serializers.Serializer):
    old_password = serializers.CharField(write_only=True, required=True)
    new_password = serializers.CharField(write_only=True, required=True, min_length=6)
    new_password_confirm = serializers.CharField(write_only=True, required=True, min_length=6)

    def validate_old_password(self, value):
        user = self.context['request'].user
        if not user.check_password(value):
            raise serializers.ValidationError('Текущий пароль указан неверно.')
        return value

    def validate(self, attrs):
        if attrs['new_password'] != attrs['new_password_confirm']:
            raise serializers.ValidationError({
                'new_password_confirm': 'Новые пароли не совпадают.'
            })
        if attrs['old_password'] == attrs['new_password']:
            raise serializers.ValidationError({
                'new_password': 'Новый пароль должен отличаться от текущего.'
            })
        return attrs

    def save(self, **kwargs):
        user = self.context['request'].user
        user.set_password(self.validated_data['new_password'])
        user.save(update_fields=['password'])
        return user


class DeleteAccountSerializer(serializers.Serializer):
    password = serializers.CharField(
        write_only=True,
        required=True,
        allow_blank=False,
        error_messages={
            'blank': 'Введите пароль родителя.',
            'required': 'Введите пароль родителя.',
        },
    )
    confirm_deletion = serializers.BooleanField(
        write_only=True,
        required=True,
        error_messages={
            'required': 'Необходимо подтвердить удаление аккаунта.',
        },
    )

    def validate_password(self, value):
        user = self.context['request'].user
        if not user.check_password(value):
            raise serializers.ValidationError(
                'Неверный пароль.',
                code='invalid_password',
            )
        return value

    def validate_confirm_deletion(self, value):
        if value is not True:
            raise serializers.ValidationError(
                'Необходимо подтвердить удаление аккаунта.',
                code='confirmation_required',
            )
        return value


class DeleteAccountRequestCodeSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)

    def validate_email(self, value):
        return value.strip().lower()


class DeleteAccountConfirmCodeSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)
    code = serializers.RegexField(
        regex=r'^\d{6}$',
        required=True,
        error_messages={
            'invalid': 'Код должен состоять из 6 цифр.',
            'required': 'Введите код подтверждения.',
            'blank': 'Введите код подтверждения.',
        },
    )

    def validate_email(self, value):
        return value.strip().lower()


class ChildLanguageSerializer(serializers.ModelSerializer):
    class Meta:
        model = Language
        fields = ['id', 'title', 'code', 'icon']


class ChildProfileSerializer(serializers.ModelSerializer):
    base_language = ChildLanguageSerializer(read_only=True)
    icon = AvatarSerializer(read_only=True)
    level = serializers.SerializerMethodField()

    class Meta:
        model = ChildProfile
        fields = [
            'id',
            'name',
            'base_language',
            'icon',
            'total_xp',
            'level',
            'is_active',
            'created_at',
            'updated_at',
        ]

    def get_level(self, obj):
        level = (
            Level.objects
            .filter(xp_required__lte=obj.total_xp)
            .order_by('-xp_required')
            .first()
        )
        if not level:
            return None
        return {
            'number': level.number,
            'title': level.title,
            'xp_required': level.xp_required,
        }


class ChildProfileWriteSerializer(serializers.ModelSerializer):
    base_language = serializers.PrimaryKeyRelatedField(
        queryset=Language.objects.all(),
        required=True,
        error_messages={
            'required': 'Выберите базовый язык ребёнка.',
            'does_not_exist': 'Выбранный язык не найден.',
        },
    )
    icon = serializers.PrimaryKeyRelatedField(
        queryset=Avatar.objects.all(),
        required=True,
        error_messages={
            'required': 'Выберите аватар ребёнка.',
            'does_not_exist': 'Выбранный аватар не найден.',
        },
    )

    class Meta:
        model = ChildProfile
        fields = ['id', 'name', 'base_language', 'icon']
        read_only_fields = ['id']

    def validate_name(self, value):
        value = value.strip()
        if len(value) < 2:
            raise serializers.ValidationError('Имя ребёнка должно содержать минимум 2 символа.')
        return value


class TariffPlanSerializer(serializers.ModelSerializer):
    class Meta:
        model = TariffPlan
        fields = [
            'id',
            'code',
            'title',
            'description',
            'price',
            'currency',
            'duration_days',
            'max_children',
            'google_play_enabled',
            'google_product_id',
            'google_base_plan_id',
            'apple_store_enabled',
            'apple_product_id',
        ]


def _has_blocking_subscription(parent):
    """Pending or currently active subscription blocks a second purchase.

    Expired ACTIVE rows must not block renewal just because their status field
    has not been normalized to EXPIRED yet.
    """
    if parent.subscriptions.filter(status=Subscription.STATUS_PENDING).exists():
        return True

    active_rows = parent.subscriptions.filter(status=Subscription.STATUS_ACTIVE)
    return any(item.is_current for item in active_rows)


def _normalize_promo_code(value):
    return (value or '').strip().upper()


def _promo_error(promo, parent=None):
    return promo.unavailability_reason(parent)


class PromoCodeValidateSerializer(serializers.Serializer):
    code = serializers.CharField(max_length=64)

    def validate_code(self, value):
        code = _normalize_promo_code(value)
        if not code:
            raise serializers.ValidationError('Введите промокод.')
        return code

    def validate(self, attrs):
        code = attrs['code']
        promo = (
            PromoCode.objects
            .select_related('kindergarten', 'tariff')
            .filter(code__iexact=code)
            .first()
        )
        if promo is None:
            raise serializers.ValidationError({'code': 'Промокод не найден.'})

        error = _promo_error(promo, self.context['request'].user)
        if error:
            raise serializers.ValidationError({'code': error})

        attrs['promo'] = promo
        return attrs


class PromoCodeRedeemSerializer(PromoCodeValidateSerializer):
    def validate(self, attrs):
        attrs = super().validate(attrs)
        promo = attrs['promo']
        if promo.mode != PromoCode.MODE_DIRECT_ACCESS:
            raise serializers.ValidationError({
                'code': 'Этот промокод используется вместе с оплатой через Google Play.'
            })
        return attrs


class SubscriptionSerializer(serializers.ModelSerializer):
    tariff = TariffPlanSerializer(read_only=True)
    is_current = serializers.BooleanField(read_only=True)
    promo_code = serializers.SerializerMethodField()
    kindergarten = serializers.SerializerMethodField()

    class Meta:
        model = Subscription
        fields = [
            'id',
            'tariff',
            'status',
            'starts_at',
            'ends_at',
            'auto_renew',
            'payment_provider',
            'external_payment_id',
            'google_product_id',
            'google_base_plan_id',
            'google_order_id',
            'google_subscription_state',
            'is_current',
            'promo_code',
            'kindergarten',
            'created_at',
            'updated_at',
        ]

    def get_promo_code(self, obj):
        try:
            return obj.promo_usage.promo_code.code
        except PromoCodeUsage.DoesNotExist:
            return None

    def get_kindergarten(self, obj):
        try:
            kindergarten = obj.promo_usage.promo_code.kindergarten
        except PromoCodeUsage.DoesNotExist:
            return None
        if kindergarten is None:
            return None
        return {
            'id': kindergarten.id,
            'name': kindergarten.name,
        }


class GooglePlayPurchaseVerifySerializer(serializers.Serializer):
    purchase_token = serializers.CharField(max_length=2048, trim_whitespace=True)
    promo_code = serializers.CharField(
        max_length=64,
        required=False,
        allow_blank=False,
        trim_whitespace=True,
    )


class SubscriptionCreateSerializer(serializers.Serializer):
    tariff = serializers.PrimaryKeyRelatedField(
        queryset=TariffPlan.objects.filter(is_active=True),
        required=False,
    )
    promo_code = serializers.CharField(
        max_length=64,
        required=False,
        allow_blank=False,
        write_only=True,
    )

    def validate(self, attrs):
        parent = self.context['request'].user
        tariff = attrs.get('tariff')
        promo_code = _normalize_promo_code(attrs.get('promo_code'))

        if not tariff and not promo_code:
            raise serializers.ValidationError(
                'Выберите тариф или введите промокод.'
            )

        if promo_code:
            promo = (
                PromoCode.objects
                .select_related('kindergarten', 'tariff')
                .filter(code__iexact=promo_code)
                .first()
            )
            if promo is None:
                raise serializers.ValidationError({
                    'promo_code': 'Промокод не найден.'
                })
            error = _promo_error(promo, parent)
            if error:
                raise serializers.ValidationError({'promo_code': error})
            if promo.mode == PromoCode.MODE_DIRECT_ACCESS:
                raise serializers.ValidationError({
                    'promo_code': (
                        'Этот код активирует доступ напрямую. Используйте активацию промокода.'
                    )
                })
            if tariff is not None and tariff.pk != promo.tariff_id:
                raise serializers.ValidationError({
                    'tariff': 'Этот тариф не соответствует указанному промокоду.'
                })
            tariff = promo.tariff
            attrs['promo'] = promo
            attrs['promo_code'] = promo.code
        elif tariff is not None and not tariff.is_public:
            raise serializers.ValidationError({
                'tariff': 'Этот тариф доступен только по промокоду.'
            })

        if _has_blocking_subscription(parent):
            raise serializers.ValidationError(
                'У родителя уже есть активная подписка или подписка, ожидающая оплаты.'
            )

        children_count = parent.children.filter(is_active=True).count()
        if tariff is not None and children_count > tariff.max_children:
            raise serializers.ValidationError(
                f'Тариф поддерживает максимум {tariff.max_children} профилей детей, '
                f'а у вас уже создано {children_count}.'
            )

        attrs['tariff'] = tariff
        return attrs

    def create(self, validated_data):
        from django.db import transaction

        request = self.context['request']
        promo = validated_data.pop('promo', None)
        validated_data.pop('promo_code', None)

        with transaction.atomic():
            parent = (
                User.objects
                .select_for_update()
                .get(pk=request.user.pk)
            )

            if _has_blocking_subscription(parent):
                raise serializers.ValidationError(
                    'У родителя уже есть активная подписка или подписка, ожидающая оплаты.'
                )

            tariff = validated_data['tariff']

            if promo is not None:
                promo = (
                    PromoCode.objects
                    .select_for_update()
                    .select_related('kindergarten', 'tariff')
                    .get(pk=promo.pk)
                )
                error = _promo_error(promo, parent)
                if error:
                    raise serializers.ValidationError({'promo_code': error})
                tariff = promo.tariff

            children_count = parent.children.filter(is_active=True).count()
            if children_count > tariff.max_children:
                raise serializers.ValidationError(
                    f'Тариф поддерживает максимум {tariff.max_children} профилей детей, '
                    f'а у вас уже создано {children_count}.'
                )

            subscription = Subscription.objects.create(
                parent=parent,
                tariff=tariff,
                status=Subscription.STATUS_PENDING,
            )

            if promo is not None:
                PromoCodeUsage.objects.create(
                    promo_code=promo,
                    parent=parent,
                    subscription=subscription,
                )

        return subscription

class FakePaymentPurchaseSerializer(SubscriptionCreateSerializer):
    SCENARIO_SUCCESS = 'success'
    SCENARIO_DECLINED = 'declined'
    SCENARIO_CANCELLED = 'cancelled'
    SCENARIO_PENDING = 'pending'
    SCENARIO_NETWORK_ERROR = 'network_error'

    scenario = serializers.ChoiceField(
        choices=(
            SCENARIO_SUCCESS,
            SCENARIO_DECLINED,
            SCENARIO_CANCELLED,
            SCENARIO_PENDING,
            SCENARIO_NETWORK_ERROR,
        ),
        default=SCENARIO_SUCCESS,
    )
