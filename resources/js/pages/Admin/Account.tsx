import { useTranslation } from '../../i18n';
import { useForm, usePage } from '@inertiajs/react';
import type { ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Alert from '../../components/Alert';
import PasswordForm from '../../components/PasswordForm';
import { errorText, type SharedProps } from '../../types';

export default function Account({
  member,
  notice,
}: {
  member: { name: string; email: string; role: string };
  notice: string;
}) {
  const { t } = useTranslation();
  const { csrfToken, errors } = usePage<SharedProps>().props;
  const form = useForm({ name: member.name });
  return (
    <>
      <PageHead title={t('Your account')} admin />
      <div className="admin-page-heading">
        <div>
          <h1>{t('Your account')}</h1>
        </div>
      </div>
      <Alert message={notice} />
      <Alert error message={errorText(errors.account)} />
      <div className="settings-grid">
        <section className="admin-card settings-card">
          <h2>{t('Profile')}</h2>
          <p>
            {member.email} ·{' '}
            <span className="role-label">
              {t(`${member.role.charAt(0).toUpperCase()}${member.role.slice(1)}`)}
            </span>
          </p>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              form.transform((data) => ({ ...data, _token: csrfToken }));
              form.post('/admin/account', { preserveScroll: true });
            }}
          >
            <label htmlFor="account-name">{t('Display name')}</label>
            <input
              id="account-name"
              required
              maxLength={100}
              value={form.data.name}
              onChange={(event) => form.setData('name', event.target.value)}
            />
            <button className="button" disabled={form.processing}>
              {form.processing ? t('Saving…') : t('Save profile')}
            </button>
          </form>
        </section>
        <section className="admin-card settings-card">
          <h2>{t('Password')}</h2>
          <p>{t('Use a different password from your other accounts.')}</p>
          <PasswordForm returnTo="account" />
        </section>
      </div>
    </>
  );
}
Account.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
