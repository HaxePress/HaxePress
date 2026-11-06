import { useEffect, useState } from 'react';
import { encryptedBackupWarning, readBackupHeader } from '../backup';
import { useTranslation } from '../i18n';
import Alert from './Alert';

export default function BackupFileInfo({
  file,
  installing = false,
}: {
  file: File | null;
  installing?: boolean;
}) {
  const { t } = useTranslation();
  const [header, setHeader] = useState<Awaited<ReturnType<typeof readBackupHeader>>>(null);

  useEffect(() => {
    let active = true;
    setHeader(null);
    if (file) {
      void readBackupHeader(file).then(
        (result) => {
          if (active) setHeader(result);
        },
        () => undefined,
      );
    }
    return () => {
      active = false;
    };
  }, [file]);

  if (!header) return null;
  return (
    <>
      <p className="field-help">
        {t('Backup created by HaxePress {version}', { version: header.cmsVersion })}
      </p>
      {header.encrypted && <Alert error message={encryptedBackupWarning} />}
      {header.encrypted && installing && (
        <p className="field-help">
          {t('Set the original APP_KEY in the target .env before starting HaxePress.')}
        </p>
      )}
    </>
  );
}
