import { useState, type ChangeEvent } from 'react';
import { createPortal } from 'react-dom';
import Alert from '../components/Alert';
import Icon from '../components/Icon';
import { useTranslation } from '../i18n';
import { mountReact, type IslandContext } from '../island-react';

interface Props {
  /** `/admin/plugins` or `/admin/themes`. */
  base: string;
  label: string;
  uploadLimit: number;
  disabled: boolean;
  csrfToken: string;
}

/**
 * The upload button of the extensions page. The server inspects the ZIP and
 * stages it; the page then shows the staged package with `?inspect=<key>`.
 */
function PackageUpload({ base, label, uploadLimit, disabled, csrfToken }: Props) {
  const { t } = useTranslation();
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState('');

  async function upload(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    setUploadError('');
    if (file.size > uploadLimit || !file.name.toLowerCase().endsWith('.zip')) {
      setUploadError(
        `Choose a ZIP package smaller than ${Math.floor(uploadLimit / 1024 / 1024)} MB.`,
      );
      return;
    }
    setUploading(true);
    try {
      const response = await fetch(`${base}/upload`, {
        method: 'POST',
        body: file,
        headers: {
          'Content-Type': 'application/zip',
          'X-CSRF-TOKEN': csrfToken,
          Accept: 'application/json',
        },
      });
      if (!response.headers.get('content-type')?.includes('application/json'))
        throw new Error('Reload this page and sign in again before uploading.');
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'The package could not be inspected.');
      window.location.assign(`${base}?inspect=${encodeURIComponent(result.key)}`);
    } catch (error) {
      setUploadError(error instanceof Error ? error.message : 'The package could not be uploaded.');
      setUploading(false);
    }
  }

  const errorTarget = document.getElementById('package-upload-error');
  return (
    <>
      <label className="button package-upload-button">
        <Icon name="upload" />
        {uploading ? t('Inspecting package…') : t(label)}
        <input
          type="file"
          accept=".zip,application/zip"
          disabled={uploading || disabled}
          onChange={upload}
        />
      </label>
      {errorTarget && createPortal(<Alert error message={uploadError} />, errorTarget)}
    </>
  );
}

export function mount(element: HTMLElement, props: IslandContext & Props) {
  return mountReact(element, props, <PackageUpload {...props} />);
}
