// The media library heading with its verified image upload, and the page alerts below it.
import { useState, type ChangeEvent } from 'react';
import Alert from '../components/Alert';
import Icon from '../components/Icon';
import { useTranslation } from '../i18n';
import { mountReact, type IslandContext } from '../island-react';
import { uploadManagedImage, type MediaRules } from '../media';

interface MediaUploadProps {
  csrfToken: string;
  rules: MediaRules;
  notice: string;
  error: string;
}

/** Shows the library again without a notice that no longer applies. */
function showLibrary() {
  const url = new URL(window.location.href);
  url.searchParams.delete('notice');
  window.location.assign(url.href);
}

function MediaUpload({ csrfToken, rules, notice, error: pageError }: MediaUploadProps) {
  const { t } = useTranslation();
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState('');

  async function upload(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    setUploading(true);
    setError('');
    try {
      await uploadManagedImage(file, csrfToken, rules);
      showLibrary();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Upload failed.');
      setUploading(false);
    }
  }

  return (
    <>
      <div className="admin-page-heading">
        <div>
          <h1>{t('Media library')}</h1>
        </div>
        <label className="button package-upload-button">
          <Icon name="upload" />
          {uploading ? t('Uploading…') : t('Upload image')}
          <input
            type="file"
            accept={rules.mimeTypes.join(',')}
            disabled={uploading}
            onChange={upload}
          />
        </label>
      </div>
      <Alert message={notice} />
      <Alert error message={error || pageError} />
    </>
  );
}

export function mount(element: HTMLElement, props: IslandContext & MediaUploadProps) {
  return mountReact(
    element,
    props,
    <MediaUpload
      csrfToken={props.csrfToken}
      rules={props.rules}
      notice={props.notice}
      error={props.error}
    />,
  );
}
