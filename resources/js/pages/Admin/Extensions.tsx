import { useTranslation } from '../../i18n';
import { createTranslator } from '../../i18n';
import { Link, router, useForm, usePage } from '@inertiajs/react';
import { useState, type ChangeEvent, type ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Alert from '../../components/Alert';
import ConfirmDialog from '../../components/ConfirmDialog';
import Pagination from '../../components/Pagination';
import Icon from '../../components/Icon';
import ThemeThumbnail from '../../components/ThemeThumbnail';
import { errorText, type ExtensionSummary, type PageLinks, type SharedProps } from '../../types';

interface Inspection {
  key: string;
  installedVersion: string | null;
  serverTarget: 'jvm' | 'cpp' | 'php' | '';
  manifest: {
    name: string;
    version: string;
    author: string;
    description: string;
    serverJar: string;
    serverCppia: string;
    serverPhp: string;
    module: string;
    stylesheet: string;
    layout: string;
  };
}

export default function Extensions({
  kind,
  packages,
  total,
  query,
  pagination,
  notice,
  uploadLimit,
}: {
  kind: 'plugin' | 'theme';
  packages: ExtensionSummary[];
  total: number;
  query: string;
  pagination: PageLinks;
  notice: string;
  uploadLimit: number;
}) {
  const { t } = useTranslation();
  const { csrfToken, errors, i18n } = usePage<SharedProps>().props;
  const base = '/admin/' + (kind === 'theme' ? 'themes' : 'plugins');
  const title = kind === 'theme' ? t('Themes') : t('Plugins');
  const localizedPackages = packages.map((item) => {
    const translate = createTranslator(i18n, item.id);
    return { ...item, name: translate(item.name), description: translate(item.description) };
  });
  const [search, setSearch] = useState(query);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState('');
  const [inspection, setInspection] = useState<Inspection | null>(null);
  const [pending, setPending] = useState<ExtensionSummary | null>(null);
  const [busy, setBusy] = useState(false);
  const form = useForm({ key: '', replace: '0' });
  const serverModuleLabels = {
    jvm: t('Includes a JVM/JAR server module'),
    cpp: t('Includes a C++/CPPIA server module'),
    php: t('Includes a PHP server module'),
    '': t('Frontend package'),
  };

  async function upload(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    setUploadError('');
    if (file.size > uploadLimit || !file.name.toLowerCase().endsWith('.zip')) {
      setUploadError(
        'Choose a ZIP package smaller than ' + Math.floor(uploadLimit / 1024 / 1024) + ' MB.',
      );
      return;
    }
    setUploading(true);
    try {
      const response = await fetch(base + '/upload', {
        method: 'POST',
        body: file,
        headers: {
          'Content-Type': 'application/zip',
          'X-CSRF-TOKEN': csrfToken || '',
          Accept: 'application/json',
        },
      });
      if (!response.headers.get('content-type')?.includes('application/json'))
        throw new Error('Reload this page and sign in again before uploading.');
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'The package could not be inspected.');
      setInspection(result);
      form.setData({ key: result.key, replace: result.installedVersion ? '1' : '0' });
    } catch (error) {
      setUploadError(error instanceof Error ? error.message : 'The package could not be uploaded.');
    } finally {
      setUploading(false);
    }
  }

  function action(item: ExtensionSummary, command: string) {
    router.post(
      base + '/' + item.id + '/' + command,
      { _token: csrfToken },
      { preserveScroll: true, onStart: () => setBusy(true), onFinish: () => setBusy(false) },
    );
  }

  return (
    <>
      <PageHead title={title} admin />
      <div className="admin-page-heading">
        <div>
          <h1>{title}</h1>
        </div>
        <div className="package-actions">
          {kind === 'theme' && (
            <Link className="button button-outline" href="/admin/themes/create">
              <Icon name="plus" />
              {t('Create website design')}
            </Link>
          )}
          <label className="button package-upload-button">
            <Icon name="upload" />
            {uploading
              ? t('Inspecting package…')
              : kind === 'theme'
                ? t('Upload theme')
                : t('Upload plugin')}
            <input
              type="file"
              accept=".zip,application/zip"
              disabled={uploading || form.processing}
              onChange={upload}
            />
          </label>
        </div>
      </div>
      <Alert message={notice} />
      <Alert error message={uploadError || errorText(form.errors) || errorText(errors.package)} />
      {inspection && (
        <section className="admin-card package-inspection">
          <div>
            <p className="small-label">{t('Ready to install')}</p>
            <h2>
              {inspection.manifest.name}{' '}
              <span className="package-version">{inspection.manifest.version}</span>
            </h2>
            <p>{inspection.manifest.description}</p>
            <p className="field-help">
              {t('By')} {inspection.manifest.author || t('the package author')} ·{' '}
              {serverModuleLabels[inspection.serverTarget]}
            </p>
          </div>
          {inspection.installedVersion && (
            <p>
              {inspection.manifest.layout === 'builder' ? (
                t(
                  'This replaces the saved design and its published version. The theme keeps its current active status.',
                )
              ) : (
                <>
                  {t('This will replace installed version')} {inspection.installedVersion}
                  {t('. Existing compatible settings are kept.')}
                </>
              )}
            </p>
          )}
          <div className="package-actions">
            <button
              className="button"
              disabled={form.processing}
              onClick={() => {
                form.transform((values) => ({ ...values, _token: csrfToken }));
                form.post(base + '/install', {
                  onSuccess: () => setInspection(null),
                  preserveScroll: true,
                });
              }}
            >
              {form.processing
                ? t('Installing…')
                : inspection.installedVersion
                  ? t('Replace package')
                  : t('Install package')}
            </button>
            <button
              className="button button-outline"
              disabled={form.processing}
              onClick={async () => {
                await fetch(base + '/discard', {
                  method: 'POST',
                  headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'X-CSRF-TOKEN': csrfToken || '',
                  },
                  body: new URLSearchParams({ key: inspection.key }),
                });
                setInspection(null);
              }}
            >
              {t('Discard upload')}
            </button>
          </div>
        </section>
      )}
      <form
        className="category-search-form extension-search"
        onSubmit={(event) => {
          event.preventDefault();
          router.get(base, { q: search });
        }}
      >
        <label className="sr-only" htmlFor="extension-search">
          {t('Find a package')}
        </label>
        <input
          id="extension-search"
          type="search"
          placeholder={'Find a ' + kind + '…'}
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          maxLength={80}
        />
        <button className="button button-outline">{t('Search')}</button>
      </form>
      <div className="extension-grid">
        {localizedPackages.map((item) => (
          <section
            className={'admin-card extension-card ' + (item.enabled ? 'extension-active' : '')}
            key={item.id}
          >
            {kind === 'theme' && (
              <ThemeThumbnail
                key={item.id + ':' + item.updated_at}
                id={item.id}
                name={item.name}
                revision={item.updated_at}
              />
            )}
            <div className="extension-card-body">
              <div className="extension-card-title">
                <h2>{item.name}</h2>
                <span className={'status-badge ' + (item.enabled ? 'published' : 'draft')}>
                  {item.enabled ? t('Active') : t('Inactive')}
                </span>
              </div>
              <p>{item.description || t('An extension for your site.')}</p>
              <p className="field-help">
                {t('Version')} {item.version} · {item.author || t('Independent author')}
              </p>
              {item.built_in && (
                <p className="built-in-theme-note">
                  <Icon name="lock" /> {t('Built-in theme')}
                </p>
              )}
              {item.last_error && <Alert error message={item.last_error} />}
              {item.restart_required === 1 && (
                <Alert
                  error
                  message={t(
                    'Plugin creation or destruction failed. The server may not function as expected until it is restarted.',
                  )}
                />
              )}
              <div className="package-actions">
                {item.designed && (
                  <>
                    <Link className="button button-outline" href={base + '/' + item.id + '/design'}>
                      <Icon name="edit" />
                      {t('Edit design')}
                    </Link>
                    <a
                      className="button button-outline"
                      href={base + '/' + item.id + '/export'}
                      title={t('Export saved design')}
                    >
                      <Icon name="download" />
                      {t('Export theme')}
                    </a>
                  </>
                )}
                {kind === 'theme' && (
                  <Link className="button button-outline" href={base + '/' + item.id + '/preview'}>
                    {t('Preview')}
                  </Link>
                )}
                {!item.enabled && (
                  <button
                    className="button button-outline"
                    disabled={busy}
                    onClick={() => action(item, 'enable')}
                  >
                    {kind === 'theme' ? t('Activate theme') : t('Activate')}
                  </button>
                )}
                {item.enabled === 1 && kind === 'plugin' && (
                  <button
                    className="button button-outline"
                    disabled={busy}
                    onClick={() => action(item, 'disable')}
                  >
                    {t('Deactivate')}
                  </button>
                )}
                {item.setting_count > 0 && (
                  <Link className="button button-outline" href={base + '/' + item.id + '/settings'}>
                    {t('Settings')}
                  </Link>
                )}
                {!item.built_in && (
                  <button
                    className="icon-button danger"
                    aria-label={'Uninstall ' + item.name}
                    disabled={busy || (kind === 'theme' && item.enabled === 1)}
                    onClick={() => setPending(item)}
                  >
                    <Icon name="trash" />
                  </button>
                )}
              </div>
            </div>
          </section>
        ))}
      </div>
      {packages.length === 0 && (
        <section className="admin-card empty-state">
          <Icon name={kind === 'theme' ? 'layout' : 'grid'} />
          <h2>{query ? t('No packages match this search.') : t('No packages installed')}</h2>
          <p>
            {t('Upload a CMS')} {kind} {t('ZIP to inspect it before installation.')}
          </p>
        </section>
      )}
      <Pagination
        links={pagination}
        count={packages.length}
        noun={kind === 'theme' ? t('themes') : t('plugins')}
      />
      <p className="field-help">
        {total} {t('installed')} {total === 1 ? kind : kind + 's'}
        {t('. ZIP uploads up to')} {Math.floor(uploadLimit / 1024 / 1024)} {t('MB.')}
      </p>
      <ConfirmDialog
        open={pending !== null}
        busy={busy}
        message={
          'Uninstall “' + (pending?.name || '') + '”? Its files and settings will be removed.'
        }
        onCancel={() => setPending(null)}
        onConfirm={() => {
          if (!pending) return;
          const item = pending;
          setPending(null);
          action(item, 'uninstall');
        }}
      />
    </>
  );
}
Extensions.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
