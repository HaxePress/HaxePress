import { useState } from 'react';
import Alert from '../components/Alert';
import BackupFileInfo from '../components/BackupFileInfo';
import { backupFileTypes, backupsPath, uploadBackup } from '../backup';
import { useTranslation } from '../i18n';
import { mountReact, type IslandContext } from '../island-react';

interface Props {
  uploadLimit: number;
  csrfToken: string;
}

/** Uploads a backup in chunks and rehearses its restore without changing the site. */
function RestoreCheck({ uploadLimit, csrfToken }: Props) {
  const { t } = useTranslation();
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [checksum, setChecksum] = useState('');

  async function verify() {
    if (!file || busy) return;
    setChecksum('');
    if (!file.size || file.size > uploadLimit) {
      setError('Choose a backup within the upload size limit.');
      return;
    }
    setError('');
    setBusy(true);
    try {
      const result = await uploadBackup<{ verified: boolean; md5: string }>(
        `${backupsPath}/verify`,
        file,
        csrfToken,
      );
      if (!result.verified) {
        throw new Error('The backup could not be verified.');
      }
      setChecksum(result.md5);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'The backup could not be verified.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="admin-card settings-card" aria-busy={busy}>
      <h2>{t('Restore a backup')}</h2>
      <p>
        {t('Verify a backup here, then restore it in the installer of a fresh HaxePress site.')}
      </p>
      <Alert error message={error} />
      <form
        onSubmit={(event) => {
          event.preventDefault();
          void verify();
        }}
      >
        <label htmlFor="backup-to-restore">{t('Backup file')}</label>
        <input
          id="backup-to-restore"
          type="file"
          accept={backupFileTypes}
          required
          disabled={busy}
          onChange={(event) => {
            setFile(event.target.files?.[0] || null);
            setChecksum('');
            setError('');
          }}
        />
        <BackupFileInfo file={file} />
        <button className="button button-outline" type="submit" disabled={!file || busy}>
          {t(busy ? 'Verifying backup…' : 'Verify backup')}
        </button>
      </form>
      {checksum && (
        <>
          <Alert message="Restore rehearsal passed." />
          <p className="field-help">
            <code>MD5 {checksum}</code>
          </p>
        </>
      )}
    </section>
  );
}

export function mount(element: HTMLElement, props: IslandContext & Props) {
  return mountReact(
    element,
    props,
    <RestoreCheck uploadLimit={props.uploadLimit} csrfToken={props.csrfToken} />,
  );
}
