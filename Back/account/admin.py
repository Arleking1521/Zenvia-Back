from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import (
    User,
    Avatar,
    ChildProfile,
    ChildLearningLanguage,
    TariffPlan,
    Subscription,
    Kindergarten,
    PromoCode,
    PromoCodeUsage,
)


@admin.register(User)
class ParentAdmin(UserAdmin):
    list_display = (
        'id',
        'email',
        'first_name',
        'interface_language',
        'is_active',
        'is_staff',
    )
    list_filter = UserAdmin.list_filter + ('interface_language',)
    search_fields = ('email', 'first_name')
    ordering = ('id',)
    fieldsets = UserAdmin.fieldsets + (
        ('Zenvia Kids', {'fields': ('interface_language',)}),
    )
    add_fieldsets = UserAdmin.add_fieldsets + (
        ('Родитель', {'fields': ('email', 'first_name', 'interface_language')}),
    )


@admin.register(Avatar)
class AvatarAdmin(admin.ModelAdmin):
    list_display = ('id', 'title')
    search_fields = ('title',)


@admin.register(ChildProfile)
class ChildProfileAdmin(admin.ModelAdmin):
    list_display = ('id', 'name', 'parent', 'base_language', 'total_xp', 'is_active')
    list_filter = ('is_active', 'base_language')
    search_fields = ('name', 'parent__email', 'parent__first_name')
    autocomplete_fields = ('parent', 'base_language', 'icon')


@admin.register(ChildLearningLanguage)
class ChildLearningLanguageAdmin(admin.ModelAdmin):
    list_display = ('id', 'profile', 'language', 'is_active')
    list_filter = ('is_active', 'language')
    search_fields = ('profile__name', 'profile__parent__email')


@admin.register(TariffPlan)
class TariffPlanAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'title',
        'price',
        'currency',
        'duration_days',
        'max_children',
        'google_play_enabled',
        'apple_store_enabled',
        'is_public',
        'is_active',
    )
    list_filter = (
        'is_public',
        'is_active',
        'google_play_enabled',
        'apple_store_enabled',
        'currency',
    )
    search_fields = (
        'title',
        'code',
        'google_product_id',
        'google_base_plan_id',
        'apple_product_id',
    )
    ordering = ('position', 'id')
    fieldsets = (
        ('Тариф Zenvia', {
            'fields': (
                'code', 'title', 'description', 'price', 'currency',
                'duration_days', 'max_children', 'position', 'is_public', 'is_active',
            ),
        }),
        ('Google Play', {
            'fields': ('google_play_enabled', 'google_product_id', 'google_base_plan_id'),
        }),
        ('Apple App Store (на будущее)', {
            'fields': ('apple_store_enabled', 'apple_product_id'),
        }),
    )


@admin.register(Kindergarten)
class KindergartenAdmin(admin.ModelAdmin):
    list_display = ('id', 'name', 'is_active', 'created_at')
    list_filter = ('is_active',)
    search_fields = ('name',)
    readonly_fields = ('created_at',)


@admin.register(PromoCode)
class PromoCodeAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'code',
        'mode',
        'channel',
        'display_partner',
        'campaign_name',
        'manager_name',
        'tariff',
        'is_active',
        'max_uses',
        'usage_count',
    )
    list_filter = (
        'mode',
        'channel',
        'is_active',
        'one_use_per_parent',
        'kindergarten',
        'tariff',
    )
    search_fields = (
        'code',
        'partner_name',
        'campaign_name',
        'manager_name',
        'kindergarten__name',
        'tariff__title',
    )
    autocomplete_fields = ('kindergarten', 'tariff')
    readonly_fields = ('created_at', 'updated_at', 'usage_count')
    fieldsets = (
        ('Код', {
            'fields': ('code', 'is_active', 'mode', 'channel'),
        }),
        ('Канал и партнёр', {
            'fields': (
                'kindergarten', 'partner_name', 'campaign_name', 'manager_name',
            ),
        }),
        ('Доступ / оплата', {
            'fields': ('tariff', 'access_days'),
            'description': (
                'Для прямого доступа задайте число дней или оставьте пустым, '
                'чтобы использовать срок тарифа. Для Google Play выберите '
                'тариф с настроенными Product ID и Base Plan ID.'
            ),
        }),
        ('Ограничения', {
            'fields': (
                'valid_from', 'valid_until', 'max_uses', 'one_use_per_parent',
            ),
        }),
        ('Статистика', {
            'fields': ('usage_count', 'created_at', 'updated_at'),
            'classes': ('collapse',),
        }),
    )

    @admin.display(description='Партнёр / источник')
    def display_partner(self, obj):
        return obj.display_name

    @admin.display(description='Использований')
    def usage_count(self, obj):
        if obj is None or not obj.pk:
            return 0
        return obj.usages.count()


@admin.register(PromoCodeUsage)
class PromoCodeUsageAdmin(admin.ModelAdmin):
    list_display = ('id', 'promo_code', 'promo_channel', 'parent', 'subscription', 'used_at')
    list_filter = ('promo_code__mode', 'promo_code__channel', 'promo_code', 'used_at')
    search_fields = (
        'promo_code__code',
        'promo_code__kindergarten__name',
        'promo_code__partner_name',
        'promo_code__campaign_name',
        'promo_code__manager_name',
        'parent__email',
    )
    autocomplete_fields = ('promo_code', 'parent', 'subscription')
    readonly_fields = ('used_at',)

    @admin.display(description='Канал')
    def promo_channel(self, obj):
        return obj.promo_code.get_channel_display()


@admin.register(Subscription)
class SubscriptionAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'parent',
        'tariff',
        'status',
        'payment_provider',
        'auto_renew',
        'starts_at',
        'ends_at',
        'created_at',
    )
    list_filter = ('status', 'payment_provider', 'tariff')
    search_fields = (
        'parent__email', 'parent__first_name', 'external_payment_id',
        'google_order_id', 'google_product_id', 'google_purchase_token',
    )
    readonly_fields = ('created_at', 'updated_at')
    fieldsets = (
        ('Подписка', {
            'fields': ('parent', 'tariff', 'status', 'auto_renew'),
        }),
        ('Срок действия', {
            'fields': ('starts_at', 'ends_at'),
        }),
        ('Оплата', {
            'fields': ('payment_provider', 'external_payment_id'),
        }),
        ('Google Play', {
            'fields': (
                'google_product_id', 'google_base_plan_id', 'google_order_id',
                'google_purchase_token', 'google_subscription_state',
                'google_last_verified_at',
            ),
            'classes': ('collapse',),
        }),
        ('Служебное', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',),
        }),
    )
