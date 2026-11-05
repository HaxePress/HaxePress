import { useForm, usePage } from '@inertiajs/react';
import { useEffect, useState, type ReactNode } from 'react';
import ContentPicker from '../../components/ContentPicker';
import MediaPicker from '../../components/MediaPicker';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Alert from '../../components/Alert';
import Icon from '../../components/Icon';
import { defaultSite, errorText, type SharedProps } from '../../types';
import { useTranslation } from '../../i18n';
import { uploadManagedImage } from '../../media';

export default function Settings({ notice }: { notice: string }) {
  const { locales, t } = useTranslation();
  const { site = defaultSite, csrfToken, errors, mediaRules } = usePage<SharedProps>().props;
  const settings = useForm({
    site_name: site.site_name,
    site_logo: site.site_logo,
    publisher_name: site.publisher_name,
    description: site.description,
    about_site: site.about_site,
    locale: site.locale,
    home_mode: site.home_mode,
    home_type: site.home_type,
    home_page: site.home_page,
    home_size: site.home_size,
    home_template: site.home_template,
  });
  const [logoPicker, setLogoPicker] = useState(false);
  const [logoUploading, setLogoUploading] = useState(false);
  const [logoError, setLogoError] = useState('');
  async function uploadLogo(file?: File) {
    if (!file || logoUploading) return;
    setLogoUploading(true);
    setLogoError('');
    try {
      const image = await uploadManagedImage(file, csrfToken, mediaRules);
      settings.setData('site_logo', image.url);
    } catch (failure) {
      setLogoError(failure instanceof Error ? failure.message : 'The image could not be uploaded.');
    } finally {
      setLogoUploading(false);
    }
  }
  const [collectionError, setCollectionError] = useState('');
  const [collections, setCollections] = useState<{ key: string; name: string }[]>([]);
  useEffect(() => {
    const abort = new AbortController();
    void fetch('/admin/content-types/options?public=1', { signal: abort.signal })
      .then((response) =>
        response.ok
          ? response.json()
          : Promise.reject(new Error('Collections could not be loaded.')),
      )
      .then((data) => setCollections(data.types))
      .catch((failure) => {
        if (!abort.signal.aborted)
          setCollectionError(
            failure instanceof Error ? failure.message : 'Collections could not be loaded.',
          );
      });
    return () => abort.abort();
  }, []);
  const password = useForm({ current_password: '', new_password: '', confirm_password: '' });
  return (
    <>
      <PageHead title={t('Settings')} admin />
      <div className="admin-page-heading">
        <div>
          <h1>{t('Settings')}</h1>
        </div>
      </div>
      <Alert message={notice} />
      <Alert error message={collectionError ? t(collectionError) : ''} />
      <div className="settings-grid">
        <section className="admin-card settings-card">
          <h2>{t('Site details')}</h2>
          <Alert error message={errorText(settings.errors) || errorText(errors?.settings)} />
          <Alert error message={logoError ? t(logoError) : ''} />
          <form
            action="/admin/settings"
            method="post"
            onSubmit={(e) => {
              e.preventDefault();
              settings.transform((data) => ({ ...data, _token: csrfToken }));
              settings.post('/admin/settings', { preserveScroll: true });
            }}
          >
            <input type="hidden" name="_token" value={csrfToken || ''} />
            <input type="hidden" name="site_logo" value={settings.data.site_logo} />
            <fieldset className="site-logo-field">
              <legend>{t('Site logo')}</legend>
              <div className="site-logo-preview">
                {settings.data.site_logo ? (
                  <img src={settings.data.site_logo} alt={t('Site logo preview')} />
                ) : (
                  <span>{settings.data.site_name || t('Site name')}</span>
                )}
              </div>
              <div className="site-logo-actions">
                <label className="button button-outline package-upload-button">
                  <Icon name="upload" />
                  {logoUploading ? t('Uploading…') : t('Upload logo')}
                  <input
                    type="file"
                    accept={mediaRules?.mimeTypes.join(',')}
                    disabled={logoUploading || settings.processing}
                    onChange={(event) => {
                      const file = event.target.files?.[0];
                      event.target.value = '';
                      void uploadLogo(file);
                    }}
                  />
                </label>
                <button
                  className="button button-outline"
                  type="button"
                  disabled={logoUploading || settings.processing}
                  onClick={() => setLogoPicker(true)}
                >
                  {t('Choose from library')}
                </button>
                {settings.data.site_logo && (
                  <button
                    className="button button-outline"
                    type="button"
                    disabled={logoUploading || settings.processing}
                    onClick={() => settings.setData('site_logo', '')}
                  >
                    {t('Remove logo')}
                  </button>
                )}
              </div>
              <p className="field-help">
                {t('PNG, WebP, JPEG or GIF. Up to 5 MB. Transparent backgrounds are supported.')}
              </p>
              <p className="field-help">
                {t('Without a logo, your theme displays the site name in its own font.')}
              </p>
              {logoUploading && <p role="status">{t('Uploading image…')}</p>}
            </fieldset>
            <label htmlFor="site-name">{t('Site name')}</label>
            <input
              id="site-name"
              name="site_name"
              value={settings.data.site_name}
              onChange={(e) => settings.setData('site_name', e.target.value)}
              required
              maxLength={100}
            />
            <label htmlFor="publisher-name">{t('Publisher name')}</label>
            <input
              id="publisher-name"
              name="publisher_name"
              value={settings.data.publisher_name}
              onChange={(e) => settings.setData('publisher_name', e.target.value)}
              maxLength={100}
            />
            <p className="field-help">
              {t('Optional. A person, team or organization behind the site.')}
            </p>
            <label htmlFor="site-description">{t('Site description')}</label>
            <textarea
              id="site-description"
              name="description"
              rows={3}
              maxLength={500}
              value={settings.data.description}
              onChange={(e) => settings.setData('description', e.target.value)}
            />
            <label htmlFor="about-site">{t('About this site')}</label>
            <textarea
              id="about-site"
              name="about_site"
              rows={4}
              maxLength={1500}
              value={settings.data.about_site}
              onChange={(e) => settings.setData('about_site', e.target.value)}
            />
            <label htmlFor="site-language">{t('Default language')}</label>
            <select
              id="site-language"
              name="locale"
              value={settings.data.locale}
              onChange={(event) => settings.setData('locale', event.target.value)}
            >
              {locales.map((choice) => (
                <option key={choice.code} value={choice.code}>
                  {choice.name}
                </option>
              ))}
            </select>
            <p className="field-help">
              {t(
                'Visitors can choose their own language. Content keeps the language it was written in.',
              )}
            </p>
            <h2 className="settings-subheading">{t('Homepage')}</h2>
            <label htmlFor="home-mode">{t('Homepage display')}</label>
            <select
              id="home-mode"
              value={settings.data.home_mode}
              onChange={(event) => settings.setData('home_mode', event.target.value)}
            >
              <option value="collection">{t('Latest content from a collection')}</option>
              <option value="page">{t('A published content item')}</option>
            </select>
            <label htmlFor="home-type">{t('Primary collection')}</label>
            <select
              id="home-type"
              value={settings.data.home_type}
              onChange={(event) => settings.setData('home_type', event.target.value)}
            >
              {!collections.some((type) => type.key === settings.data.home_type) && (
                <option value={settings.data.home_type}>{settings.data.home_type}</option>
              )}
              {collections.map((type) => (
                <option key={type.key} value={type.key}>
                  {t(type.name)}
                </option>
              ))}
            </select>
            {settings.data.home_mode === 'page' ? (
              <>
                <label htmlFor="home-page">{t('Homepage content')}</label>
                <ContentPicker
                  id="home-page"
                  value={settings.data.home_page}
                  onChange={(value) => settings.setData('home_page', value)}
                  required
                />
              </>
            ) : (
              <>
                <label htmlFor="home-size">{t('Homepage content count')}</label>
                <input
                  id="home-size"
                  type="number"
                  min={1}
                  max={24}
                  value={settings.data.home_size}
                  onChange={(event) => settings.setData('home_size', event.target.value)}
                />
                <label htmlFor="home-template">{t('Homepage template')}</label>
                <input
                  id="home-template"
                  maxLength={80}
                  value={settings.data.home_template}
                  onChange={(event) => settings.setData('home_template', event.target.value)}
                />
              </>
            )}
            <button
              className="button"
              type="submit"
              disabled={settings.processing || logoUploading}
            >
              <Icon name="check" />
              {settings.processing ? t('Saving…') : t('Save your changes')}
            </button>
          </form>
        </section>
        <section className="admin-card settings-card password-card">
          <div className="login-icon">
            <Icon name="lock" />
          </div>
          <h2>{t('Account password')}</h2>
          <Alert error message={errorText(password.errors) || errorText(errors?.password)} />
          <form
            action="/admin/password"
            method="post"
            onSubmit={(e) => {
              e.preventDefault();
              password.transform((data) => ({ ...data, _token: csrfToken }));
              password.post('/admin/password', {
                preserveScroll: true,
                onSuccess: () => password.reset(),
              });
            }}
          >
            <input type="hidden" name="_token" value={csrfToken || ''} />
            <label htmlFor="current-password">{t('Current password')}</label>
            <input
              id="current-password"
              name="current_password"
              type="password"
              autoComplete="current-password"
              value={password.data.current_password}
              onChange={(e) => password.setData('current_password', e.target.value)}
              required
            />
            <label htmlFor="new-password">{t('New password')}</label>
            <input
              id="new-password"
              name="new_password"
              type="password"
              autoComplete="new-password"
              minLength={12}
              maxLength={72}
              value={password.data.new_password}
              onChange={(e) => password.setData('new_password', e.target.value)}
              required
            />
            <p className="field-help">{t('At least 12 characters.')}</p>
            <label htmlFor="confirm-password">{t('Confirm new password')}</label>
            <input
              id="confirm-password"
              name="confirm_password"
              type="password"
              autoComplete="new-password"
              minLength={12}
              maxLength={72}
              value={password.data.confirm_password}
              onChange={(e) => password.setData('confirm_password', e.target.value)}
              required
            />
            <button className="button button-outline" type="submit" disabled={password.processing}>
              {password.processing ? t('Updating…') : t('Update password')}
            </button>
          </form>
        </section>
      </div>
      <MediaPicker
        idPrefix="site-logo-"
        open={logoPicker}
        onClose={() => setLogoPicker(false)}
        onPick={(image) => settings.setData('site_logo', image.url)}
      />
    </>
  );
}
Settings.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
