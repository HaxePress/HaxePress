import { Link, router, useForm, usePage } from '@inertiajs/react';
import { useEffect, useState, type ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Alert from '../../components/Alert';
import Icon from '../../components/Icon';
import ContentPicker from '../../components/ContentPicker';
import CollectionPicker from '../../components/CollectionPicker';
import ConfirmDialog from '../../components/ConfirmDialog';
import { errorText, type NavigationLink, type SharedProps } from '../../types';
import { useTranslation } from '../../i18n';

interface MenuItem extends NavigationLink {
  position: number;
  content_id: number;
  collection_key: string;
}
interface Region {
  key: string;
  name: string;
  max_links: number;
  enabled: number;
  system: number;
}

export default function Navigation({
  links,
  location,
  regions,
  region,
  limit,
  notice,
}: {
  links: MenuItem[];
  location: string;
  regions: Region[];
  region: Region;
  limit: number;
  notice: string;
}) {
  const { t } = useTranslation();
  const { csrfToken, errors } = usePage<SharedProps>().props;
  const empty = {
    id: '',
    label: '',
    url: '',
    position: String(links.length),
    content_id: '0',
    collection_key: '',
    new_tab: false,
  };
  const form = useForm(empty);
  const regionForm = useForm({ key: '', name: '', max_links: '12', enabled: true });
  const [mode, setMode] = useState<'url' | 'content' | 'collection'>('url');
  const [pending, setPending] = useState<MenuItem | null>(null);
  const [busy, setBusy] = useState(false);
  const [regionQuery, setRegionQuery] = useState('');
  const [regionChoices, setRegionChoices] = useState(regions);
  const [regionError, setRegionError] = useState('');
  useEffect(() => {
    form.setData(empty);
    setMode('url');
    setRegionChoices(regions);
  }, [location]);
  useEffect(() => {
    if (!regionQuery) {
      setRegionChoices(regions);
      return;
    }
    const abort = new AbortController();
    const timer = setTimeout(async () => {
      try {
        const response = await fetch(
          `/admin/navigation/regions?q=${encodeURIComponent(regionQuery)}&selected=${encodeURIComponent(location)}`,
          { signal: abort.signal },
        );
        if (!response.ok) throw new Error('Navigation regions could not be loaded.');
        setRegionChoices((await response.json()).regions);
        setRegionError('');
      } catch (failure) {
        if (!abort.signal.aborted)
          setRegionError(
            failure instanceof Error ? failure.message : 'Navigation regions could not be loaded.',
          );
      }
    }, 200);
    return () => {
      clearTimeout(timer);
      abort.abort();
    };
  }, [regionQuery, regions, location]);
  return (
    <>
      <PageHead title={t('Navigation')} admin />
      <div className="admin-page-heading">
        <div>
          <h1>{t('Navigation')}</h1>
        </div>
      </div>
      <Alert message={notice} />
      <Alert
        error
        message={errorText(form.errors) || errorText(errors.navigation) || regionError}
      />
      <section className="admin-card navigation-region-picker">
        <label htmlFor="region-search">{t('Search navigation regions')}</label>
        <input
          id="region-search"
          type="search"
          value={regionQuery}
          maxLength={100}
          onChange={(event) => setRegionQuery(event.target.value)}
        />
        <label htmlFor="region-choice">{t('Navigation region')}</label>
        <select
          id="region-choice"
          value={location}
          onChange={(event) => router.get('/admin/navigation', { location: event.target.value })}
        >
          {regionChoices.map((choice) => (
            <option key={choice.key} value={choice.key}>
              {t(choice.name)}
            </option>
          ))}
        </select>
      </section>
      <div className="categories-grid">
        <section className="admin-card category-collection">
          <div className="admin-card-heading">
            <div>
              <h2>
                {t(region.name)}{' '}
                <span className="count-badge">
                  {links.length}/{limit}
                </span>
              </h2>
              <p>
                {t('Managed content and collection links follow their current public address.')}
              </p>
            </div>
          </div>
          {links.length ? (
            <ol className="category-list menu-link-list">
              {links.map((link) => (
                <li key={link.id} className={form.data.id === String(link.id) ? 'editing' : ''}>
                  <span className="menu-position">{link.position}</span>
                  <div className="category-details">
                    <strong>{link.label}</strong>
                    <span>
                      {link.content_id > 0
                        ? t('Linked content')
                        : link.collection_key
                          ? t('Linked collection')
                          : link.url}
                    </span>
                  </div>
                  <div className="category-actions">
                    <button
                      className="icon-button"
                      aria-label={t('Edit {title}', { title: link.label })}
                      onClick={() => {
                        form.setData({
                          id: String(link.id),
                          label: link.label,
                          url: link.url,
                          position: String(link.position),
                          content_id: String(link.content_id),
                          collection_key: link.collection_key,
                          new_tab: link.new_tab === 1,
                        });
                        setMode(
                          link.content_id > 0
                            ? 'content'
                            : link.collection_key
                              ? 'collection'
                              : 'url',
                        );
                      }}
                    >
                      <Icon name="edit" />
                    </button>
                    <button
                      className="icon-button danger"
                      aria-label={t('Remove {title}', { title: link.label })}
                      onClick={() => setPending(link)}
                    >
                      <Icon name="trash" />
                    </button>
                  </div>
                </li>
              ))}
            </ol>
          ) : (
            <div className="empty-state">
              <Icon name="menu" />
              <h2>{t('Make a path.')}</h2>
              <p>{t('Add your first link to this menu.')}</p>
            </div>
          )}
        </section>
        <section className="admin-card settings-card category-form">
          <h2>{form.data.id ? t('Edit link') : t('Add a link')}</h2>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              form.transform((data) => ({
                ...data,
                location,
                content_id: mode === 'content' ? data.content_id : '0',
                collection_key: mode === 'collection' ? data.collection_key : '',
                new_tab: data.new_tab ? '1' : '0',
                _token: csrfToken,
              }));
              form.post('/admin/navigation/save', { preserveState: 'errors' });
            }}
          >
            <label htmlFor="menu-label">{t('Link label')}</label>
            <input
              id="menu-label"
              required
              maxLength={80}
              value={form.data.label}
              onChange={(event) => form.setData('label', event.target.value)}
            />
            <label htmlFor="menu-source">{t('Link target')}</label>
            <select
              id="menu-source"
              value={mode}
              onChange={(event) => setMode(event.target.value as typeof mode)}
            >
              <option value="url">{t('Website address')}</option>
              <option value="content">{t('Published content')}</option>
              <option value="collection">{t('Collection archive')}</option>
            </select>
            {mode === 'content' ? (
              <ContentPicker
                id="menu-content"
                value={form.data.content_id}
                onChange={(value) => form.setData('content_id', value)}
                required
              />
            ) : mode === 'collection' ? (
              <CollectionPicker
                id="menu-collection"
                value={form.data.collection_key}
                onChange={(value) => form.setData('collection_key', value)}
                archives
              />
            ) : (
              <>
                <label htmlFor="menu-url">{t('Website address')}</label>
                <input
                  id="menu-url"
                  required
                  maxLength={1000}
                  value={form.data.url}
                  onChange={(event) => form.setData('url', event.target.value)}
                  placeholder="/about"
                />
              </>
            )}
            <label htmlFor="menu-position">{t('Position')}</label>
            <input
              id="menu-position"
              type="number"
              min={0}
              max={9999}
              value={form.data.position}
              onChange={(event) => form.setData('position', event.target.value)}
            />
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={form.data.new_tab}
                onChange={(event) => form.setData('new_tab', event.target.checked)}
              />
              <span>{t('Open in a new tab')}</span>
            </label>
            <button className="button" disabled={form.processing} type="submit">
              <Icon name="check" /> {t('Save link')}
            </button>
          </form>
        </section>
      </div>
      <section className="admin-card settings-card navigation-region-settings">
        <h2>{t('Navigation region settings')}</h2>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            regionForm.transform((values) => ({
              ...values,
              enabled: values.enabled ? '1' : '0',
              _token: csrfToken,
            }));
            regionForm.post('/admin/navigation/regions/save', { preserveState: 'errors' });
          }}
        >
          <div className="structure-field-grid">
            <div>
              <label htmlFor="region-key">{t('Stable key')}</label>
              <input
                id="region-key"
                required
                maxLength={40}
                pattern="[a-z][a-z0-9_-]{0,39}"
                value={regionForm.data.key}
                onChange={(event) => regionForm.setData('key', event.target.value)}
              />
            </div>
            <div>
              <label htmlFor="region-name">{t('Region name')}</label>
              <input
                id="region-name"
                required
                maxLength={100}
                value={regionForm.data.name}
                onChange={(event) => regionForm.setData('name', event.target.value)}
              />
            </div>
            <div>
              <label htmlFor="region-limit">{t('Maximum links')}</label>
              <input
                id="region-limit"
                type="number"
                min={1}
                max={50}
                value={regionForm.data.max_links}
                onChange={(event) => regionForm.setData('max_links', event.target.value)}
              />
            </div>
          </div>
          <label className="checkbox-label">
            <input
              type="checkbox"
              checked={regionForm.data.enabled}
              onChange={(event) => regionForm.setData('enabled', event.target.checked)}
            />
            <span>{t('Region enabled')}</span>
          </label>
          <div className="editor-actions">
            <button type="submit" className="button" disabled={regionForm.processing}>
              {t('Save region')}
            </button>
            <button
              type="button"
              className="button button-outline"
              onClick={() =>
                regionForm.setData({
                  key: region.key,
                  name: region.name,
                  max_links: String(region.max_links),
                  enabled: region.enabled === 1,
                })
              }
            >
              {t('Edit current region')}
            </button>
            <button
              type="button"
              className="button button-outline"
              onClick={() =>
                regionForm.setData({ key: '', name: '', max_links: '12', enabled: true })
              }
            >
              {t('New region')}
            </button>
          </div>
        </form>
      </section>
      <ConfirmDialog
        open={pending !== null}
        message={t('Remove this navigation link?')}
        busy={busy}
        onCancel={() => setPending(null)}
        onConfirm={() => {
          if (!pending) return;
          router.post(
            `/admin/navigation/${pending.id}/delete`,
            { _token: csrfToken },
            {
              onStart: () => setBusy(true),
              onFinish: () => {
                setBusy(false);
                setPending(null);
              },
            },
          );
        }}
      />
    </>
  );
}
Navigation.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
