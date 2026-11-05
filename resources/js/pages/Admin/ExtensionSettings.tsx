import { useTranslation } from '../../i18n';
import { Link, useForm, usePage } from '@inertiajs/react';
import type { ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Alert from '../../components/Alert';
import PackageSettingField from '../../components/PackageSettingField';
import { errorText, type ExtensionField, type SharedProps } from '../../types';

export default function ExtensionSettings({
  kind,
  packageInfo,
  fields,
  values,
  secrets,
  notice,
}: {
  kind: 'theme' | 'plugin';
  packageInfo: { id: string; name: string; version: string };
  fields: ExtensionField[];
  values: Record<string, string>;
  secrets: Record<string, boolean>;
  notice: string;
}) {
  const { t } = useTranslation(packageInfo.id);
  const { csrfToken, errors } = usePage<SharedProps>().props;
  const base = '/admin/' + (kind === 'theme' ? 'themes' : 'plugins');
  const form = useForm<Record<string, string>>(values);
  return (
    <>
      <PageHead title={t('{name} settings', { name: t(packageInfo.name) })} admin />
      <div className="admin-page-heading">
        <div>
          <Link href={base} className="back-link">
            {t('Back to')} {kind === 'theme' ? t('themes') : t('plugins')}
          </Link>
          <h1>{t(packageInfo.name)}</h1>
          <p>
            {t('Settings for version')} {packageInfo.version}.
          </p>
        </div>
      </div>
      <Alert message={notice} />
      <Alert error message={errorText(form.errors) || errorText(errors.package)} />
      <form
        className="admin-card settings-card extension-settings"
        onSubmit={(event) => {
          event.preventDefault();
          form.transform((data) => ({ ...data, _token: csrfToken }));
          form.post(base + '/' + packageInfo.id + '/settings', { preserveScroll: true });
        }}
      >
        {fields.map((field) => (
          <PackageSettingField
            key={field.key}
            packageId={packageInfo.id}
            field={field}
            value={form.data[field.key] || ''}
            onChange={(value) => form.setData(field.key, value)}
            secretSaved={secrets[field.key]}
            clearSecret={form.data['clear_' + field.key] === '1'}
            onClearSecret={(clear) => form.setData('clear_' + field.key, clear ? '1' : '0')}
          />
        ))}
        <button className="button" disabled={form.processing}>
          {form.processing ? t('Saving…') : t('Save settings')}
        </button>
      </form>
    </>
  );
}
ExtensionSettings.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
