from datetime import timedelta
from django.test import TestCase
from django.core import mail
from django.utils import timezone
from rest_framework.test import APIClient

from legal_documents.models import LegalAcceptance, LegalDocumentVersion
from word_learning.models import (
    Concept,
    Language,
    ProfileAchievement,
    Achievement,
    Topic,
    WordProgress,
)

from .models import (
    Avatar,
    ChildProfile,
    Kindergarten,
    PromoCode,
    PromoCodeUsage,
    Subscription,
    TariffPlan,
    User,
    AccountDeletionVerification,
)


class AccountDeletionTests(TestCase):
    def setUp(self):
        self.password = 'ParentPass123!'
        self.user = User.objects.create_user(
            username='parent@example.com',
            email='parent@example.com',
            first_name='Parent',
            password=self.password,
        )
        self.language = Language.objects.create(
            title='Русский',
            code='ru',
            icon='icons/archives/ru.zip',
        )
        self.avatar = Avatar.objects.create(
            title='Dragon',
            image='profile_icons/dragon.png',
        )
        self.child = ChildProfile.objects.create(
            parent=self.user,
            name='Kid',
            base_language=self.language,
            icon=self.avatar,
            total_xp=25,
        )
        self.topic = Topic.objects.create(
            difficulty='Easy',
            is_active=True,
            icon='icons/topics/animals.png',
        )
        self.concept = Concept.objects.create(
            topic=self.topic,
            image='words/images/cat.png',
            difficulty='Easy',
            is_active=True,
        )
        self.progress = WordProgress.objects.create(
            profile=self.child,
            concept=self.concept,
            language=self.language,
            mastery=2,
        )
        self.achievement = Achievement.objects.create(
            title='First',
            description='First achievement',
            icon='achievements/icons/first.png',
            condition_type='words_learned',
            condition_value=1,
        )
        ProfileAchievement.objects.create(
            profile=self.child,
            achievement=self.achievement,
        )

        self.tariff = TariffPlan.objects.create(
            code='test',
            title='Test',
            price='1000.00',
            duration_days=30,
            max_children=1,
            is_active=True,
            is_public=False,
        )
        self.subscription = Subscription.objects.create(
            parent=self.user,
            tariff=self.tariff,
            status=Subscription.STATUS_ACTIVE,
            starts_at=timezone.now(),
        )
        self.kindergarten = Kindergarten.objects.create(name='Test Kindergarten')
        self.promo = PromoCode.objects.create(
            code='TESTCODE',
            kindergarten=self.kindergarten,
            tariff=self.tariff,
        )
        PromoCodeUsage.objects.create(
            promo_code=self.promo,
            parent=self.user,
            subscription=self.subscription,
        )

        self.legal_document = LegalDocumentVersion.objects.create(
            document_type=LegalDocumentVersion.TYPE_TERMS,
            version='test-1',
            language='ru',
            title='Test terms',
            source_file='legal_documents/test.docx',
            source_sha256='0' * 64,
            extracted_html='<p>test</p>',
            extracted_text='test',
            status=LegalDocumentVersion.STATUS_DRAFT,
        )
        LegalAcceptance.objects.create(
            user=self.user,
            document=self.legal_document,
        )

        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_wrong_password_does_not_delete_account(self):
        response = self.client.post(
            '/api/account/delete-account/',
            {'password': 'wrong-password', 'confirm_deletion': True},
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertTrue(User.objects.filter(pk=self.user.pk).exists())
        self.assertTrue(ChildProfile.objects.filter(pk=self.child.pk).exists())

    def test_confirmation_is_required(self):
        response = self.client.post(
            '/api/account/delete-account/',
            {'password': self.password, 'confirm_deletion': False},
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertTrue(User.objects.filter(pk=self.user.pk).exists())

    def test_delete_account_cascades_personal_data_only(self):
        user_id = self.user.pk
        child_id = self.child.pk
        subscription_id = self.subscription.pk
        progress_id = self.progress.pk

        response = self.client.post(
            '/api/account/delete-account/',
            {'password': self.password, 'confirm_deletion': True},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertFalse(User.objects.filter(pk=user_id).exists())
        self.assertFalse(ChildProfile.objects.filter(pk=child_id).exists())
        self.assertFalse(WordProgress.objects.filter(pk=progress_id).exists())
        self.assertFalse(Subscription.objects.filter(pk=subscription_id).exists())
        self.assertFalse(PromoCodeUsage.objects.filter(parent_id=user_id).exists())
        self.assertFalse(LegalAcceptance.objects.filter(user_id=user_id).exists())

        # Общие справочники и утверждаемые документы аккаунту не принадлежат.
        self.assertTrue(TariffPlan.objects.filter(pk=self.tariff.pk).exists())
        self.assertTrue(PromoCode.objects.filter(pk=self.promo.pk).exists())
        self.assertTrue(Language.objects.filter(pk=self.language.pk).exists())
        self.assertTrue(Avatar.objects.filter(pk=self.avatar.pk).exists())
        self.assertTrue(
            LegalDocumentVersion.objects.filter(pk=self.legal_document.pk).exists()
        )


class TrialSubscriptionTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='trial@example.com',
            email='trial@example.com',
            first_name='Trial Parent',
            password='ParentPass123!',
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_trial_can_be_started_once(self):
        response = self.client.post('/api/account/subscriptions/start-trial/')

        self.assertEqual(response.status_code, 201)
        subscription = Subscription.objects.get(parent=self.user)
        self.assertEqual(subscription.payment_provider, 'trial')
        self.assertEqual(subscription.status, Subscription.STATUS_ACTIVE)
        self.assertTrue(subscription.is_current)
        self.assertFalse(subscription.auto_renew)
        self.assertEqual(subscription.tariff.code, 'trial-7-days')
        self.assertEqual(subscription.tariff.price, 0)

        second = self.client.post('/api/account/subscriptions/start-trial/')
        self.assertEqual(second.status_code, 400)
        self.assertEqual(
            Subscription.objects.filter(
                parent=self.user,
                payment_provider='trial',
            ).count(),
            1,
        )

    def test_dashboard_reports_trial_state(self):
        before = self.client.get('/api/account/dashboard/')
        self.assertEqual(before.status_code, 200)
        self.assertTrue(before.data['trial']['eligible'])
        self.assertFalse(before.data['trial']['used'])

        self.client.post('/api/account/subscriptions/start-trial/')
        after = self.client.get('/api/account/dashboard/')
        self.assertEqual(after.status_code, 200)
        self.assertTrue(after.data['trial']['active'])
        self.assertTrue(after.data['trial']['used'])
        self.assertFalse(after.data['trial']['eligible'])
        self.assertGreaterEqual(after.data['trial']['days_remaining'], 1)

    def test_active_subscription_blocks_trial(self):
        tariff = TariffPlan.objects.create(
            code='paid-test',
            title='Paid',
            price='1000.00',
            duration_days=30,
            max_children=1,
            is_active=True,
            is_public=True,
        )
        Subscription.objects.create(
            parent=self.user,
            tariff=tariff,
            status=Subscription.STATUS_ACTIVE,
            starts_at=timezone.now(),
            ends_at=timezone.now() + timedelta(days=30),
        )

        response = self.client.post('/api/account/subscriptions/start-trial/')
        self.assertEqual(response.status_code, 400)

class SubscriptionAutoRenewTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='renew@example.com',
            email='renew@example.com',
            first_name='Renew Parent',
            password='ParentPass123!',
        )
        self.other_user = User.objects.create_user(
            username='other-renew@example.com',
            email='other-renew@example.com',
            first_name='Other Parent',
            password='ParentPass123!',
        )
        self.tariff = TariffPlan.objects.create(
            code='renew-test',
            title='Renew Test',
            price='2990.00',
            duration_days=30,
            max_children=2,
            is_active=True,
            is_public=True,
        )
        self.ends_at = timezone.now() + timedelta(days=30)
        self.subscription = Subscription.objects.create(
            parent=self.user,
            tariff=self.tariff,
            status=Subscription.STATUS_ACTIVE,
            starts_at=timezone.now(),
            ends_at=self.ends_at,
            auto_renew=True,
            payment_provider='fake',
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_disable_auto_renew_keeps_current_period_active(self):
        response = self.client.post(
            f'/api/account/subscriptions/{self.subscription.pk}/disable-auto-renew/'
        )

        self.assertEqual(response.status_code, 200)
        self.subscription.refresh_from_db()
        self.assertFalse(self.subscription.auto_renew)
        self.assertEqual(self.subscription.status, Subscription.STATUS_ACTIVE)
        self.assertEqual(self.subscription.ends_at, self.ends_at)
        self.assertTrue(self.subscription.is_current)
        self.assertFalse(response.data['auto_renew'])

    def test_disable_auto_renew_is_idempotent(self):
        self.subscription.auto_renew = False
        self.subscription.save(update_fields=['auto_renew'])

        response = self.client.post(
            f'/api/account/subscriptions/{self.subscription.pk}/disable-auto-renew/'
        )

        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data['auto_renew'])

    def test_parent_cannot_change_another_parents_subscription(self):
        other_subscription = Subscription.objects.create(
            parent=self.other_user,
            tariff=self.tariff,
            status=Subscription.STATUS_ACTIVE,
            starts_at=timezone.now(),
            ends_at=timezone.now() + timedelta(days=30),
            auto_renew=True,
        )

        response = self.client.post(
            f'/api/account/subscriptions/{other_subscription.pk}/disable-auto-renew/'
        )

        self.assertEqual(response.status_code, 404)
        other_subscription.refresh_from_db()
        self.assertTrue(other_subscription.auto_renew)



class AccountDeletionWebPageTests(TestCase):
    def test_delete_account_page_is_public(self):
        response = self.client.get('/delete-account/')
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Удаление аккаунта')
        self.assertContains(response, 'api/account/delete-account/')
        self.assertNotContains(response, 'user_id')

class PublicAccountDeletionCodeTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='web-delete@example.com',
            email='web-delete@example.com',
            first_name='Web Parent',
            password='ParentPass123!',
        )
        self.client = APIClient()

    def _request_code(self):
        return self.client.post(
            '/api/account/delete-account/request-code/',
            {'email': self.user.email},
            format='json',
        )

    def _extract_code(self):
        import re
        match = re.search(r'\b(\d{6})\b', mail.outbox[-1].body)
        self.assertIsNotNone(match)
        return match.group(1)

    def test_request_code_sends_email_and_stores_only_hash(self):
        response = self._request_code()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(mail.outbox), 1)
        self.assertEqual(mail.outbox[0].to, [self.user.email])

        code = self._extract_code()
        verification = AccountDeletionVerification.objects.get(user=self.user)
        self.assertNotEqual(verification.code_hash, code)
        self.assertGreater(verification.expires_at, timezone.now())

    def test_unknown_email_returns_same_generic_success(self):
        response = self.client.post(
            '/api/account/delete-account/request-code/',
            {'email': 'missing@example.com'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(mail.outbox), 0)
        self.assertIn('Если аккаунт с таким email существует', response.data['detail'])

    def test_correct_code_deletes_account(self):
        self._request_code()
        code = self._extract_code()

        response = self.client.post(
            '/api/account/delete-account/confirm-code/',
            {'email': self.user.email, 'code': code},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertFalse(User.objects.filter(pk=self.user.pk).exists())

    def test_wrong_code_does_not_delete_account(self):
        self._request_code()
        response = self.client.post(
            '/api/account/delete-account/confirm-code/',
            {'email': self.user.email, 'code': '000000'},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertTrue(User.objects.filter(pk=self.user.pk).exists())
        verification = AccountDeletionVerification.objects.get(user=self.user)
        self.assertEqual(verification.attempts, 1)

