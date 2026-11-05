import { useTranslation } from '../i18n';
import { useEffect, useRef } from 'react';
import Icon from './Icon';

export default function ConfirmDialog({
  open,
  message,
  onCancel,
  onConfirm,
  busy = false,
}: {
  open: boolean;
  message: string;
  onCancel: () => void;
  onConfirm: () => void;
  busy?: boolean;
}) {
  const { t } = useTranslation();
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    else if (!open && dialog.open) dialog.close();
  }, [open]);
  return (
    <dialog
      ref={ref}
      className="confirm-dialog"
      onCancel={(e) => {
        e.preventDefault();
        if (!busy) onCancel();
      }}
    >
      <div className="confirm-symbol">
        <Icon name="trash" />
      </div>
      <h2>{t('Just making sure.')}</h2>
      <p>{t(message)}</p>
      <div className="confirm-actions">
        <button className="button button-outline" onClick={onCancel} disabled={busy}>
          {t('Keep it')}
        </button>
        <button className="button button-danger" onClick={onConfirm} disabled={busy}>
          {busy ? t('Deleting…') : t('Delete')}
        </button>
      </div>
    </dialog>
  );
}
