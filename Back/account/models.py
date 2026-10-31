from django.db import models
from django.contrib.auth.models import AbstractUser
from django.core.exceptions import ValidationError
from django.utils import timezone
from django.utils.translation import gettext_lazy as _


class Avatar(models.Model):
    title = models.CharField(max_length=128, verbose_name=_('Название'))
    image = models.ImageField(upload_to='profile_icons/')

    class Meta:
        verbose_name = 'Иконка профиля'
        verbose_name_plural = 'Иконки профилей'

    def __str__(self):
        return self.title


class User(AbstractUser):
    """Родительский аккаунт.

    Авторизация во внешнем API выполняется по email + password. Поле username
    сохранено как техническое, чтобы не ломать существующую AUTH_USER_MODEL и
    старые миграции Django; для новых родителей в username записывается email.

    interface_language относится только к интерфейсу родительского кабинета.
    Он не связан с ChildProfile.base_language (язык интерфейса ребёнка) и с
    языками, которые ребёнок изучает.
    """

    INTERFACE_LANGUAGE_RU = 'ru'
    INTERFACE_LANGUAGE_KK = 'kk'
    INTERFACE_LANGUAGE_EN = 'en'
    INTERFACE_LANGUAGE_ZH = 'zh'
    INTERFACE_LANGUAGE_CHOICES = (
        (INTERFACE_LANGUAGE_RU, 'Русский'),
        (INTERFACE_LANGUAGE_KK, 'Қазақша'),
        (INTERFACE_LANGUAGE_EN, 'English'),
        (INTERFACE_LANGUAGE_ZH, '中文'),
    )

    username = models.CharField(max_length=128, unique=True, verbose_name=_('Технический логин'))
    password = models.CharField(max_length=128, verbose_name=_('Пароль'))
    email = models.EmailField(unique=True, verbose_name=_('Email'))
    first_name = models.CharField(max_length=128, verbose_name=_('Имя родителя'))
    parental_pin_hash = models.CharField(
        max_length=128,
        blank=True,
        default='',
        verbose_name=_('Хеш родительского PIN'),
    )
    interface_language = models.CharField(
        max_length=5,
        choices=INTERFACE_LANGUAGE_CHOICES,
        default=INTERFACE_LANGUAGE_RU,
        verbose_name=_('Язык интерфейса родителя'),
    )

    REQUIRED_FIELDS = ['email', 'first_name']

    class Meta:
        verbose_name = 'Родитель'
        verbose_name_plural = 'Родители'

    def __str__(self):
        return f'{self.first_name} <{self.email}>'


class ChildProfile(models.Model):
    parent = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='children',
        verbose_name='Родитель',
    )
    name = models.CharField(max_length=128, verbose_name='Имя ребёнка')
    base_language = models.ForeignKey(
        'word_learning.Language',
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name='child_profiles',
        verbose_name='Базовый язык',
    )
    icon = models.ForeignKey(
        Avatar,
        on_delete=models.SET_NULL,
        blank=True,
        null=True,
        related_name='child_profiles',
        verbose_name='Аватар',
    )
    total_xp = models.PositiveIntegerField(default=0, verbose_name='Опыт')
    is_active = models.BooleanField(default=True, verbose_name='Активный профиль')
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Создан')
    updated_at = models.DateTimeField(auto_now=True, verbose_name='Обновлён')

    class Meta:
        verbose_name = 'Профиль ребёнка'
        verbose_name_plural = 'Профили детей'
        ordering = ['id']

    def __str__(self):
        return f'{self.name} — {self.parent.email}'


class ChildLearningLanguage(models.Model):
    profile = models.ForeignKey(
        ChildProfile,
        on_delete=models.CASCADE,
        related_name='learning_languages',
        verbose_name='Профиль ребёнка',
    )
    language = models.ForeignKey(
        'word_learning.Language',
        on_delete=models.CASCADE,
        verbose_name='Изучаемый язык',
    )
    is_active = models.BooleanField(default=True)

    class Meta:
        verbose_name = 'Изучаемый язык ребёнка'
        verbose_name_plural = 'Изучаемые языки детей'
        constraints = [
            models.UniqueConstraint(
                fields=['profile', 'language'],
                name='unique_child_learning_language',
            )
        ]

    def __str__(self):
        return f'{self.profile.name}: {self.language.code}'


class TariffPlan(models.Model):
    code = models.SlugField(max_length=64, unique=True, verbose_name='Код')
    title = models.CharField(max_length=128, verbose_name='Название')
    description = models.TextField(blank=True, verbose_name='Описание')
    price = models.DecimalField(max_digits=10, decimal_places=2, verbose_name='Цена')
    currency = models.CharField(max_length=8, default='KZT', verbose_name='Валюта')
    duration_days = models.PositiveIntegerField(default=30, verbose_name='Срок, дней')
    max_children = models.PositiveSmallIntegerField(default=1, verbose_name='Максимум профилей детей')
    is_active = models.BooleanField(default=True, verbose_name='Активен')
    is_public = models.BooleanField(
        default=True,
        verbose_name='Показывать в общем списке',
        help_text='Отключите для скрытых тарифов, доступных только по промокоду.',
    )
    position = models.PositiveIntegerField(default=0, verbose_name='Порядок')
    google_play_enabled = models.BooleanField(
        default=False,
        verbose_name='Оплата через Google Play',
    )
    google_product_id = models.CharField(
        max_length=128,
        null=True,
        blank=True,
        verbose_name='Google Play Product ID',
    )
    google_base_plan_id = models.CharField(
        max_length=128,
        null=True,
        blank=True,
        verbose_name='Google Play Base Plan ID',
    )
    apple_store_enabled = models.BooleanField(
        default=False,
        verbose_name='Оплата через App Store',
    )
    apple_product_id = models.CharField(
        max_length=128,
        null=True,
        blank=True,
        unique=True,
        verbose_name='Apple Product ID',
    )

    class Meta:
        verbose_name = 'Тариф'
        verbose_name_plural = 'Тарифы'
        ordering = ['position', 'id']
        constraints = [
            models.UniqueConstraint(
                fields=['google_product_id', 'google_base_plan_id'],
                name='unique_google_play_tariff_mapping',
            ),
        ]

    def clean(self):
        super().clean()
        errors = {}
        if self.google_play_enabled:
            if not (self.google_product_id or '').strip():
                errors['google_product_id'] = 'Укажите Google Play Product ID.'
            if not (self.google_base_plan_id or '').strip():
                errors['google_base_plan_id'] = 'Укажите Google Play Base Plan ID.'
        if self.apple_store_enabled and not (self.apple_product_id or '').strip():
            errors['apple_product_id'] = 'Укажите Apple Product ID.'
        if errors:
            raise ValidationError(errors)

    def save(self, *args, **kwargs):
        self.google_product_id = (self.google_product_id or '').strip() or None
        self.google_base_plan_id = (self.google_base_plan_id or '').strip() or None
        self.apple_product_id = (self.apple_product_id or '').strip() or None
        super().save(*args, **kwargs)

    def __str__(self):
        return self.title



class Kindergarten(models.Model):
    name = models.CharField(max_length=255, verbose_name='Название детского сада')
    is_active = models.BooleanField(default=True, verbose_name='Активен')
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Создан')

    class Meta:
        verbose_name = 'Детский сад'
        verbose_name_plural = 'Детские сады'
        ordering = ['name', 'id']

    def __str__(self):
        return self.name


class PromoCode(models.Model):
    code = models.CharField(
        max_length=64,
        unique=True,
        db_index=True,
        verbose_name='Промокод',
    )
    kindergarten = models.ForeignKey(
        Kindergarten,
        on_delete=models.CASCADE,
        related_name='promo_codes',
        verbose_name='Детский сад',
    )
    tariff = models.ForeignKey(
        TariffPlan,
        on_delete=models.PROTECT,
        related_name='promo_codes',
        verbose_name='Скрытый тариф',
    )
    is_active = models.BooleanField(default=True, verbose_name='Активен')
    valid_from = models.DateTimeField(
        null=True,
        blank=True,
        verbose_name='Действует с',
    )
    valid_until = models.DateTimeField(
        null=True,
        blank=True,
        verbose_name='Действует до',
    )
    max_uses = models.PositiveIntegerField(
        null=True,
        blank=True,
        verbose_name='Максимальное число использований',
        help_text='Оставьте пустым, если лимита нет.',
    )
    one_use_per_parent = models.BooleanField(
        default=True,
        verbose_name='Одно использование на родителя',
    )
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Создан')
    updated_at = models.DateTimeField(auto_now=True, verbose_name='Обновлён')

    class Meta:
        verbose_name = 'Промокод'
        verbose_name_plural = 'Промокоды'
        ordering = ['kindergarten__name', 'code']

    def clean(self):
        super().clean()
        if self.tariff_id and self.tariff.is_public:
            raise ValidationError({
                'tariff': 'Для промокода выберите скрытый тариф (is_public=False).'
            })

    def save(self, *args, **kwargs):
        self.code = (self.code or '').strip().upper()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.code} — {self.kindergarten.name}'


class Subscription(models.Model):
    STATUS_PENDING = 'pending'
    STATUS_ACTIVE = 'active'
    STATUS_EXPIRED = 'expired'
    STATUS_CANCELLED = 'cancelled'
    STATUS_CHOICES = (
        (STATUS_PENDING, 'Ожидает оплаты'),
        (STATUS_ACTIVE, 'Активна'),
        (STATUS_EXPIRED, 'Истекла'),
        (STATUS_CANCELLED, 'Отменена'),
    )

    parent = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='subscriptions',
        verbose_name='Родитель',
    )
    tariff = models.ForeignKey(
        TariffPlan,
        on_delete=models.PROTECT,
        related_name='subscriptions',
        verbose_name='Тариф',
    )
    status = models.CharField(
        max_length=16,
        choices=STATUS_CHOICES,
        default=STATUS_PENDING,
        verbose_name='Статус',
    )
    starts_at = models.DateTimeField(null=True, blank=True, verbose_name='Начало')
    ends_at = models.DateTimeField(null=True, blank=True, verbose_name='Окончание')
    auto_renew = models.BooleanField(default=False, verbose_name='Автопродление')
    payment_provider = models.CharField(max_length=64, blank=True, verbose_name='Платёжный провайдер')
    external_payment_id = models.CharField(max_length=128, blank=True, verbose_name='ID платежа у провайдера')
    google_purchase_token = models.CharField(
        max_length=1024,
        null=True,
        blank=True,
        unique=True,
        verbose_name='Google Play purchase token',
    )
    google_product_id = models.CharField(max_length=128, blank=True, default='')
    google_base_plan_id = models.CharField(max_length=128, blank=True, default='')
    google_order_id = models.CharField(max_length=128, blank=True, default='')
    google_subscription_state = models.CharField(max_length=64, blank=True, default='')
    google_last_verified_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Создана')
    updated_at = models.DateTimeField(auto_now=True, verbose_name='Обновлена')

    class Meta:
        verbose_name = 'Подписка'
        verbose_name_plural = 'Подписки'
        ordering = ['-created_at']

    @property
    def is_current(self):
        if self.status != self.STATUS_ACTIVE:
            return False
        if self.starts_at and self.starts_at > timezone.now():
            return False
        if self.ends_at and self.ends_at <= timezone.now():
            return False
        return True

    def __str__(self):
        return f'{self.parent.email}: {self.tariff.title} ({self.status})'

class PromoCodeUsage(models.Model):
    promo_code = models.ForeignKey(
        PromoCode,
        on_delete=models.PROTECT,
        related_name='usages',
        verbose_name='Промокод',
    )
    parent = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='promo_code_usages',
        verbose_name='Родитель',
    )
    subscription = models.OneToOneField(
        Subscription,
        on_delete=models.CASCADE,
        related_name='promo_usage',
        verbose_name='Подписка',
    )
    used_at = models.DateTimeField(auto_now_add=True, verbose_name='Использован')

    class Meta:
        verbose_name = 'Использование промокода'
        verbose_name_plural = 'Использования промокодов'
        ordering = ['-used_at']

    def __str__(self):
        return f'{self.promo_code.code} — {self.parent.email}'

class AccountDeletionVerification(models.Model):
    """Одноразовый код подтверждения удаления родительского аккаунта."""

    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name='deletion_verification',
        verbose_name='Родитель',
    )
    code_hash = models.CharField(max_length=128, verbose_name='Хеш кода')
    expires_at = models.DateTimeField(db_index=True, verbose_name='Действует до')
    attempts = models.PositiveSmallIntegerField(default=0, verbose_name='Ошибочных попыток')
    sent_at = models.DateTimeField(verbose_name='Код отправлен')
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Создано')
    updated_at = models.DateTimeField(auto_now=True, verbose_name='Обновлено')

    class Meta:
        verbose_name = 'Код удаления аккаунта'
        verbose_name_plural = 'Коды удаления аккаунтов'

    def __str__(self):
        return f'Удаление аккаунта: {self.user.email}'

