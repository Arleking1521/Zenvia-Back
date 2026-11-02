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
    MODE_DIRECT_ACCESS = 'direct_access'
    MODE_GOOGLE_PLAY = 'google_play'
    MODE_CHOICES = (
        (MODE_DIRECT_ACCESS, 'Прямой доступ'),
        (MODE_GOOGLE_PLAY, 'Покупка через Google Play'),
    )

    CHANNEL_KINDERGARTEN = 'kindergarten'
    CHANNEL_BLOGGER = 'blogger'
    CHANNEL_MANAGER = 'manager'
    CHANNEL_ADVERTISING = 'advertising'
    CHANNEL_OTHER = 'other'
    CHANNEL_CHOICES = (
        (CHANNEL_KINDERGARTEN, 'Детский сад'),
        (CHANNEL_BLOGGER, 'Блогер'),
        (CHANNEL_MANAGER, 'Менеджер'),
        (CHANNEL_ADVERTISING, 'Реклама'),
        (CHANNEL_OTHER, 'Другое'),
    )

    code = models.CharField(
        max_length=64,
        unique=True,
        db_index=True,
        verbose_name='Промокод',
    )
    mode = models.CharField(
        max_length=24,
        choices=MODE_CHOICES,
        default=MODE_GOOGLE_PLAY,
        verbose_name='Режим промокода',
        help_text=(
            'Прямой доступ сразу активирует подписку. Google Play — код '
            'учитывается только после подтверждённой покупки в Google Play.'
        ),
    )
    channel = models.CharField(
        max_length=24,
        choices=CHANNEL_CHOICES,
        default=CHANNEL_KINDERGARTEN,
        verbose_name='Канал распространения',
    )
    kindergarten = models.ForeignKey(
        Kindergarten,
        on_delete=models.SET_NULL,
        related_name='promo_codes',
        null=True,
        blank=True,
        verbose_name='Детский сад',
    )
    partner_name = models.CharField(
        max_length=255,
        blank=True,
        verbose_name='Партнёр / блогер',
        help_text='Например: блогер Aida Kids или название партнёра.',
    )
    campaign_name = models.CharField(
        max_length=255,
        blank=True,
        verbose_name='Рекламная кампания',
    )
    manager_name = models.CharField(
        max_length=255,
        blank=True,
        verbose_name='Менеджер',
    )
    tariff = models.ForeignKey(
        TariffPlan,
        on_delete=models.PROTECT,
        related_name='promo_codes',
        verbose_name='Тариф',
    )
    access_days = models.PositiveIntegerField(
        null=True,
        blank=True,
        verbose_name='Дней прямого доступа',
        help_text=(
            'Только для режима «Прямой доступ». Если пусто, используется '
            'duration_days выбранного тарифа.'
        ),
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
        help_text='1 — одноразовый код; пусто — без общего лимита.',
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
        ordering = ['channel', 'campaign_name', 'code']

    @property
    def display_name(self):
        if self.kindergarten_id:
            return self.kindergarten.name
        return (
            (self.partner_name or '').strip()
            or (self.campaign_name or '').strip()
            or self.get_channel_display()
        )

    @property
    def effective_access_days(self):
        return int(self.access_days or self.tariff.duration_days)

    def unavailability_reason(self, parent=None):
        now = timezone.now()
        if not self.is_active:
            return 'Промокод отключён.'
        if self.kindergarten_id and not self.kindergarten.is_active:
            return 'Промокод этого детского сада временно недоступен.'
        if not self.tariff.is_active:
            return 'Тариф по этому промокоду временно недоступен.'
        if self.valid_from and self.valid_from > now:
            return 'Промокод ещё не начал действовать.'
        if self.valid_until and self.valid_until <= now:
            return 'Срок действия промокода истёк.'
        if self.max_uses is not None and self.usages.count() >= self.max_uses:
            return 'Лимит активаций этого промокода исчерпан.'
        if (
            parent is not None
            and self.one_use_per_parent
            and self.usages.filter(parent=parent).exists()
        ):
            return 'Этот промокод уже был использован вашим аккаунтом.'
        return None

    def clean(self):
        super().clean()
        errors = {}
        if self.valid_from and self.valid_until and self.valid_from >= self.valid_until:
            errors['valid_until'] = 'Дата окончания должна быть позже даты начала.'
        if self.mode == self.MODE_GOOGLE_PLAY:
            if self.tariff_id and not self.tariff.google_play_enabled:
                errors['tariff'] = (
                    'Для режима Google Play выберите тариф с включённой оплатой Google Play.'
                )
            if self.access_days is not None:
                errors['access_days'] = (
                    'Для Google Play срок задаётся базовым планом Google Play, '
                    'поле прямого доступа оставьте пустым.'
                )
        elif self.mode == self.MODE_DIRECT_ACCESS:
            if self.access_days is not None and self.access_days < 1:
                errors['access_days'] = 'Срок доступа должен быть не меньше 1 дня.'
        if self.channel == self.CHANNEL_KINDERGARTEN and not (
            self.kindergarten_id or (self.partner_name or '').strip()
        ):
            errors['kindergarten'] = (
                'Для канала «Детский сад» выберите детский сад или укажите партнёра.'
            )
        if errors:
            raise ValidationError(errors)

    def save(self, *args, **kwargs):
        self.code = (self.code or '').strip().upper()
        self.partner_name = (self.partner_name or '').strip()
        self.campaign_name = (self.campaign_name or '').strip()
        self.manager_name = (self.manager_name or '').strip()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.code} — {self.display_name}'


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
        on_delete=models.SET_NULL,
        related_name='promo_code_usages',
        null=True,
        blank=True,
        verbose_name='Родитель',
        help_text='После удаления аккаунта очищается, но факт использования кода сохраняется.',
    )
    subscription = models.OneToOneField(
        Subscription,
        on_delete=models.SET_NULL,
        related_name='promo_usage',
        null=True,
        blank=True,
        verbose_name='Подписка',
        help_text='После удаления подписки факт использования промокода сохраняется.',
    )
    used_at = models.DateTimeField(auto_now_add=True, verbose_name='Использован')

    class Meta:
        verbose_name = 'Использование промокода'
        verbose_name_plural = 'Использования промокодов'
        ordering = ['-used_at']

    def __str__(self):
        return f"{self.promo_code.code} — {self.parent.email if self.parent_id else 'удалённый аккаунт'}"

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

