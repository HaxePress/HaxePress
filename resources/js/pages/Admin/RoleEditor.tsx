import { Link, router, useForm, usePage } from '@inertiajs/react';
import { useEffect, useState, type ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Alert from '../../components/Alert';
import Icon from '../../components/Icon';
import { errorText, hasCapability, type SharedProps } from '../../types';
import type { RoleDefinition } from './Roles';
import { useTranslation } from '../../i18n';

interface CapabilityChoice {
  key: string;
  name: string;
  group_name: string;
  owner: string;
}

export default function RoleEditor({
  definition,
  grants,
  choices,
  isNew,
  notice,
}: {
  definition: RoleDefinition | null;
  grants: string[];
  choices: CapabilityChoice[];
  isNew: boolean;
  notice: string;
}) {
  const { t } = useTranslation();
  const { csrfToken, errors, auth } = usePage<SharedProps>().props;
  const protectedOwner = definition?.key === 'owner';
  const form = useForm({
    key: definition?.key || '',
    name: definition?.name || '',
    description: definition?.description || '',
    enabled: definition?.enabled !== 0,
    capabilities: grants,
  });
  const [query, setQuery] = useState('');
  const [available, setAvailable] = useState(choices);
  const [lookupError, setLookupError] = useState('');
  useEffect(() => {
    if (!query) {
      setAvailable(choices);
      return;
    }
    const abort = new AbortController();
    const timer = setTimeout(async () => {
      try {
        const response = await fetch(`/admin/roles/capabilities?q=${encodeURIComponent(query)}`, {
          signal: abort.signal,
        });
        if (!response.ok) throw new Error('Capabilities could not be loaded.');
        setAvailable((await response.json()).choices);
        setLookupError('');
      } catch (failure) {
        if (!abort.signal.aborted)
          setLookupError(
            failure instanceof Error ? failure.message : 'Capabilities could not be loaded.',
          );
      }
    }, 200);
    return () => {
      clearTimeout(timer);
      abort.abort();
    };
  }, [query, choices]);
  const path = isNew ? '/admin/roles/create' : `/admin/roles/${definition?.key}/save`;
  return (
    <>
      <PageHead title={isNew ? t('New role') : t('Edit role')} admin />
      <form
        action={path}
        method="post"
        onSubmit={(event) => {
          event.preventDefault();
          form.transform((values) => ({
            ...values,
            capabilities: JSON.stringify(values.capabilities),
            enabled: values.enabled ? '1' : '0',
            _token: csrfToken,
          }));
          form.post(path, { preserveState: 'errors' });
        }}
      >
        <div className="admin-page-heading">
          <div>
            <Link className="back-link" href="/admin/roles">
              <Icon name="arrow-left" /> {t('Roles')}
            </Link>
            <h1>{isNew ? t('New role') : t(definition?.name || 'Role')}</h1>
          </div>
          <button type="submit" className="button" disabled={form.processing}>
            <Icon name="check" /> {form.processing ? t('Saving…') : t('Save role')}
          </button>
        </div>
        <Alert error message={errorText(form.errors) || errorText(errors?.role) || lookupError} />
        <Alert message={notice === 'saved' ? t('The role has been saved.') : ''} />
        <div className="settings-grid">
          <section className="admin-card settings-card">
            <h2>{t('Role details')}</h2>
            <label htmlFor="role-name">{t('Role name')}</label>
            <input
              id="role-name"
              value={form.data.name}
              required
              maxLength={100}
              onChange={(event) => form.setData('name', event.target.value)}
            />
            <label htmlFor="role-key">{t('Stable key')}</label>
            <input
              id="role-key"
              value={form.data.key}
              required
              readOnly={!isNew}
              pattern="[a-z][a-z0-9_]{0,31}"
              maxLength={32}
              onChange={(event) => form.setData('key', event.target.value)}
            />
            <label htmlFor="role-description">{t('Description')}</label>
            <textarea
              id="role-description"
              rows={4}
              maxLength={500}
              value={form.data.description}
              onChange={(event) => form.setData('description', event.target.value)}
            />
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={form.data.enabled}
                disabled={protectedOwner}
                onChange={(event) => form.setData('enabled', event.target.checked)}
              />
              <span>{t('Role enabled')}</span>
            </label>
            <p className="field-help">
              {t('Disabled roles cannot sign in or keep using an existing administration session.')}
            </p>
            {!isNew && !definition?.system && !definition?.owner && (
              <button
                type="button"
                className="button button-outline danger"
                onClick={() => {
                  if (window.confirm(t('Remove this unused role?')))
                    router.post(`/admin/roles/${definition?.key}/delete`, {
                      _token: csrfToken,
                    });
                }}
              >
                {t('Remove role')}
              </button>
            )}
          </section>
          <section className="admin-card settings-card">
            <h2>{t('Capabilities')}</h2>
            {protectedOwner ? (
              <p>{t('The protected owner role always retains every capability.')}</p>
            ) : (
              <>
                <label htmlFor="capability-search">{t('Search capabilities')}</label>
                <input
                  id="capability-search"
                  value={query}
                  type="search"
                  maxLength={100}
                  onChange={(event) => setQuery(event.target.value)}
                  placeholder={t('Search capabilities')}
                />
                <p className="field-help">
                  {t('Selected capabilities: {count}', { count: form.data.capabilities.length })}
                </p>
                {available.map((choice) => (
                  <label className="checkbox-label capability-choice" key={choice.key}>
                    <input
                      type="checkbox"
                      checked={form.data.capabilities.includes(choice.key)}
                      disabled={!hasCapability(auth?.admin.capabilities || [], choice.key)}
                      onChange={(event) =>
                        form.setData(
                          'capabilities',
                          event.target.checked
                            ? [...form.data.capabilities, choice.key]
                            : form.data.capabilities.filter((key) => key !== choice.key),
                        )
                      }
                    />
                    <span>
                      <strong>{t(choice.name)}</strong>
                      <small>
                        {t(choice.group_name)} · {choice.key}
                      </small>
                    </span>
                  </label>
                ))}
              </>
            )}
          </section>
        </div>
      </form>
    </>
  );
}
RoleEditor.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
