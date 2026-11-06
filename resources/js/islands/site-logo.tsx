import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import Alert from '../components/Alert';
import Icon from '../components/Icon';
import MediaPicker from '../components/MediaPicker';
import { useTranslation } from '../i18n';
import { uploadManagedImage, type MediaRules } from '../media';
import { mountReact, type IslandContext } from '../island-react';

interface SiteLogoProps {
  csrfToken: string;
  logo: string;
  siteName: string;
  mediaRules: MediaRules;
}

/**
 * The site logo field of the settings form: upload, library choice and
 * removal. Its value is posted with the form in the hidden `site_logo` field.
 */
function SiteLogoField({
  csrfToken,
  logo: initialLogo,
  siteName: initialSiteName,
  mediaRules,
  form,
  alertHost,
  dialogHost,
}: SiteLogoProps & {
  form: HTMLFormElement | null;
  alertHost: HTMLElement;
  dialogHost: HTMLElement;
}) {
  const { t } = useTranslation();
  const [logo, setLogo] = useState(initialLogo);
  const [siteName, setSiteName] = useState(initialSiteName);
  const [picker, setPicker] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    // Without a logo the preview shows the site name as it is typed.
    const input = document.getElementById('site-name');
    if (!(input instanceof HTMLInputElement)) return;
    const update = () => setSiteName(input.value);
    input.addEventListener('input', update);
    return () => input.removeEventListener('input', update);
  }, []);

  useEffect(() => {
    const submit = form?.querySelector<HTMLButtonElement>('button[type="submit"]');
    if (submit) submit.disabled = uploading;
  }, [form, uploading]);

  async function upload(file?: File) {
    if (!file || uploading) return;
    setUploading(true);
    setError('');
    try {
      const image = await uploadManagedImage(file, csrfToken, mediaRules);
      setLogo(image.url);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'The image could not be uploaded.');
    } finally {
      setUploading(false);
    }
  }

  return (
    <>
      <input type="hidden" name="site_logo" value={logo} />
      <fieldset className="site-logo-field">
        <legend>{t('Site logo')}</legend>
        <div className="site-logo-preview">
          {logo ? (
            <img src={logo} alt={t('Site logo preview')} />
          ) : (
            <span>{siteName || t('Site name')}</span>
          )}
        </div>
        <div className="site-logo-actions">
          <label className="button button-outline package-upload-button">
            <Icon name="upload" />
            {uploading ? t('Uploading…') : t('Upload logo')}
            <input
              type="file"
              accept={mediaRules.mimeTypes.join(',')}
              disabled={uploading}
              onChange={(event) => {
                const file = event.target.files?.[0];
                event.target.value = '';
                void upload(file);
              }}
            />
          </label>
          <button
            className="button button-outline"
            type="button"
            disabled={uploading}
            onClick={() => setPicker(true)}
          >
            {t('Choose from library')}
          </button>
          {logo && (
            <button
              className="button button-outline"
              type="button"
              disabled={uploading}
              onClick={() => setLogo('')}
            >
              {t('Remove logo')}
            </button>
          )}
        </div>
        <p className="field-help">
          {t('PNG, JPEG or GIF. Up to 5 MB. Transparent backgrounds are supported.')}
        </p>
        <p className="field-help">
          {t('Without a logo, your theme displays the site name in its own font.')}
        </p>
        {uploading && <p role="status">{t('Uploading image…')}</p>}
      </fieldset>
      {createPortal(<Alert error message={error ? t(error) : ''} />, alertHost)}
      {createPortal(
        <MediaPicker
          idPrefix="site-logo-"
          open={picker}
          onClose={() => setPicker(false)}
          onPick={(image) => setLogo(image.url)}
        />,
        dialogHost,
      )}
    </>
  );
}

/** A box-less container for content rendered outside the island. */
function host(): HTMLElement {
  const element = document.createElement('div');
  element.style.display = 'contents';
  return element;
}

export function mount(element: HTMLElement, props: IslandContext & SiteLogoProps) {
  const form = element.closest('form');
  // The upload error is shown above the form, and the library dialog sits
  // outside it so that its search field cannot submit the settings.
  const alertHost = host();
  const dialogHost = host();
  if (form) form.before(alertHost);
  else element.before(alertHost);
  (document.getElementById('main') || document.body).append(dialogHost);
  return mountReact(
    element,
    props,
    <SiteLogoField {...props} form={form} alertHost={alertHost} dialogHost={dialogHost} />,
  );
}
