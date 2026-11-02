import csv
import re
import secrets

from django import forms
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from django.db import transaction
from django.http import HttpResponse
from django.template.response import TemplateResponse
from django.urls import path, reverse

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




_PROMO_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'


class PromoCodeBatchGenerationForm(forms.Form):
    """Форма пакетной генерации универсальных промокодов из Django Admin."""

    mode = forms.ChoiceField(
        label='Режим',
        choices=PromoCode.MODE_CHOICES,
        initial=PromoCode.MODE_DIRECT_ACCESS,
    )
    channel = forms.ChoiceField(
        label='Канал распространения',
        choices=PromoCode.CHANNEL_CHOICES,
        initial=PromoCode.CHANNEL_KINDERGARTEN,
    )
    tariff = forms.ModelChoiceField(
        label='Тариф',
        queryset=TariffPlan.objects.none(),
    )
    kindergarten = forms.ModelChoiceField(
        label='Детский сад',
        queryset=Kindergarten.objects.none(),
        required=False,
    )
    manager_name = forms.CharField(label='Менеджер', max_length=255, required=False)
    partner_name = forms.CharField(label='Партнёр / блогер', max_length=255, required=False)
    campaign_name = forms.CharField(label='Кампания', max_length=255, required=False)
    count = forms.IntegerField(
        label='Количество кодов',
        min_value=1,
        max_value=500,
        initial=10,
        help_text='За один раз можно создать от 1 до 500 кодов.',
    )
    prefix = forms.CharField(
        label='Префикс',
        max_length=16,
        initial='ZK',
        help_text='Только латинские буквы и цифры, например BALAPAN или ZK.',
    )
    access_days = forms.IntegerField(
        label='Дней прямого доступа',
        min_value=1,
        required=False,
        initial=365,
        help_text='Используется только для режима «Прямой доступ».',
    )
    max_uses = forms.IntegerField(
        label='Максимум использований каждого кода',
        min_value=1,
        required=False,
        initial=1,
        help_text='1 — одноразовый; оставьте пустым для многоразового кода.',
    )
    one_use_per_parent = forms.BooleanField(
        label='Не более одного использования на родителя',
        required=False,
        initial=True,
    )
    valid_until = forms.DateTimeField(
        label='Код действует до',
        required=False,
        widget=forms.DateTimeInput(attrs={'type': 'datetime-local'}),
        help_text='Можно оставить пустым — тогда сам код не имеет даты окончания.',
    )

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['tariff'].queryset = TariffPlan.objects.filter(is_active=True).order_by('position', 'id')
        self.fields['kindergarten'].queryset = Kindergarten.objects.filter(is_active=True).order_by('name', 'id')

    def clean_prefix(self):
        prefix = (self.cleaned_data.get('prefix') or '').strip().upper()
        if not re.fullmatch(r'[A-Z0-9]{2,16}', prefix):
            raise forms.ValidationError('Используйте 2–16 латинских букв и/или цифр без пробелов.')
        return prefix

    def clean(self):
        cleaned = super().clean()
        mode = cleaned.get('mode')
        channel = cleaned.get('channel')
        tariff = cleaned.get('tariff')
        kindergarten = cleaned.get('kindergarten')
        partner_name = (cleaned.get('partner_name') or '').strip()

        if channel == PromoCode.CHANNEL_KINDERGARTEN and not (kindergarten or partner_name):
            self.add_error('kindergarten', 'Для канала «Детский сад» выберите детский сад или укажите партнёра.')

        if mode == PromoCode.MODE_GOOGLE_PLAY:
            cleaned['access_days'] = None
            if tariff is not None and not tariff.google_play_enabled:
                self.add_error('tariff', 'Для режима Google Play выберите тариф с включённой оплатой Google Play.')

        return cleaned


def _generate_unique_promo_codes(prefix, count):
    """Генерирует визуально читаемые коды PREFIX-XXXX-XXXX без 0/O/1/I."""
    result = []
    reserved = set()
    while len(result) < count:
        part1 = ''.join(secrets.choice(_PROMO_ALPHABET) for _ in range(4))
        part2 = ''.join(secrets.choice(_PROMO_ALPHABET) for _ in range(4))
        code = f'{prefix}-{part1}-{part2}'
        if code in reserved or PromoCode.objects.filter(code=code).exists():
            continue
        reserved.add(code)
        result.append(code)
    return result


@admin.register(PromoCode)
class PromoCodeAdmin(admin.ModelAdmin):
    change_list_template = 'admin/account/promocode/change_list.html'
    actions = ('export_selected_codes_csv',)

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

    def get_urls(self):
        urls = super().get_urls()
        custom_urls = [
            path(
                'generate/',
                self.admin_site.admin_view(self.generate_codes_view),
                name='account_promocode_generate',
            ),
        ]
        return custom_urls + urls

    def generate_codes_view(self, request):
        if not self.has_add_permission(request):
            from django.core.exceptions import PermissionDenied
            raise PermissionDenied

        if request.method == 'POST':
            form = PromoCodeBatchGenerationForm(request.POST)
            if form.is_valid():
                data = form.cleaned_data
                codes = _generate_unique_promo_codes(data['prefix'], data['count'])
                objects = [
                    PromoCode(
                        code=code,
                        mode=data['mode'],
                        channel=data['channel'],
                        kindergarten=data.get('kindergarten'),
                        partner_name=(data.get('partner_name') or '').strip(),
                        campaign_name=(data.get('campaign_name') or '').strip(),
                        manager_name=(data.get('manager_name') or '').strip(),
                        tariff=data['tariff'],
                        access_days=data.get('access_days'),
                        is_active=True,
                        valid_until=data.get('valid_until'),
                        max_uses=data.get('max_uses'),
                        one_use_per_parent=data.get('one_use_per_parent', True),
                    )
                    for code in codes
                ]
                with transaction.atomic():
                    PromoCode.objects.bulk_create(objects)

                response = HttpResponse(content_type='text/csv; charset=utf-8')
                response['Content-Disposition'] = 'attachment; filename="zenvia_promo_codes.csv"'
                response.write('\ufeff')
                writer = csv.writer(response, delimiter=';')
                writer.writerow([
                    'Промокод', 'Менеджер', 'Детский сад', 'Партнёр / блогер',
                    'Кампания', 'Режим', 'Канал', 'Тариф', 'Дней доступа',
                    'Макс. использований', 'Действует до',
                ])
                kindergarten_name = data['kindergarten'].name if data.get('kindergarten') else ''
                tariff_title = str(data['tariff'])
                mode_label = dict(PromoCode.MODE_CHOICES).get(data['mode'], data['mode'])
                channel_label = dict(PromoCode.CHANNEL_CHOICES).get(data['channel'], data['channel'])
                for code in codes:
                    writer.writerow([
                        code,
                        data.get('manager_name') or '',
                        kindergarten_name,
                        data.get('partner_name') or '',
                        data.get('campaign_name') or '',
                        mode_label,
                        channel_label,
                        tariff_title,
                        data.get('access_days') or '',
                        data.get('max_uses') or 'Без лимита',
                        data.get('valid_until') or '',
                    ])
                return response
        else:
            form = PromoCodeBatchGenerationForm()

        context = {
            **self.admin_site.each_context(request),
            'title': 'Сгенерировать промокоды',
            'opts': self.model._meta,
            'form': form,
            'changelist_url': reverse('admin:account_promocode_changelist'),
        }
        return TemplateResponse(
            request,
            'admin/account/promocode/generate_codes.html',
            context,
        )

    @admin.action(description='Скачать выбранные промокоды CSV')
    def export_selected_codes_csv(self, request, queryset):
        response = HttpResponse(content_type='text/csv; charset=utf-8')
        response['Content-Disposition'] = 'attachment; filename="zenvia_selected_promo_codes.csv"'
        response.write('\ufeff')
        writer = csv.writer(response, delimiter=';')
        writer.writerow([
            'Промокод', 'Режим', 'Канал', 'Менеджер', 'Детский сад',
            'Партнёр / блогер', 'Кампания', 'Тариф', 'Использований',
            'Макс. использований', 'Активен',
        ])
        for obj in queryset.select_related('kindergarten', 'tariff'):
            writer.writerow([
                obj.code,
                obj.get_mode_display(),
                obj.get_channel_display(),
                obj.manager_name,
                obj.kindergarten.name if obj.kindergarten_id else '',
                obj.partner_name,
                obj.campaign_name,
                str(obj.tariff),
                obj.usages.count(),
                obj.max_uses if obj.max_uses is not None else 'Без лимита',
                'Да' if obj.is_active else 'Нет',
            ])
        return response

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
