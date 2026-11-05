import { useTranslation } from '../i18n';
import { useForm, usePage } from '@inertiajs/react';
import Alert from './Alert';
import { errorText, type SharedProps } from '../types';

export default function PasswordForm({
  returnTo = 'settings',
}: {
  returnTo?: 'settings' | 'account';
}) {
  const { t } = useTranslation();
  const { csrfToken, errors } = usePage<SharedProps>().props;
  const form = useForm({ current_password: '', new_password: '', confirm_password: '' });
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        form.transform((data) => ({ ...data, _token: csrfToken, return_to: returnTo }));
        form.post('/admin/password', { preserveScroll: true, onSuccess: () => form.reset() });
      }}
    >
      <Alert error message={errorText(form.errors) || errorText(errors.password)} />
      <label htmlFor="current-password">{t('Current password')}</label>
      <input
        id="current-password"
        type="password"
        autoComplete="current-password"
        required
        value={form.data.current_password}
        onChange={(event) => form.setData('current_password', event.target.value)}
      />
      <label htmlFor="new-password">{t('New password')}</label>
      <input
        id="new-password"
        type="password"
        autoComplete="new-password"
        required
        minLength={12}
        maxLength={72}
        value={form.data.new_password}
        onChange={(event) => form.setData('new_password', event.target.value)}
      />
      <p className="field-help">
        {t('Use at least 12 characters, up to 72 bytes. Other signed-in sessions will expire.')}
      </p>
      <label htmlFor="confirm-password">{t('Confirm new password')}</label>
      <input
        id="confirm-password"
        type="password"
        autoComplete="new-password"
        required
        minLength={12}
        maxLength={72}
        value={form.data.confirm_password}
        onChange={(event) => form.setData('confirm_password', event.target.value)}
      />
      <button className="button button-outline" disabled={form.processing}>
        {form.processing ? t('Updating…') : t('Update password')}
      </button>
    </form>
  );
}
