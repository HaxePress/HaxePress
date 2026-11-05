import { useState } from 'react';
import Icon from '../../components/Icon';
import { useTranslation } from '../../i18n';

export default function DesignMarkupImport({
  disabled,
  onImport,
}: {
  disabled: boolean;
  onImport: (html: string) => Promise<boolean>;
}) {
  const { t } = useTranslation();
  const [html, setHtml] = useState('');
  const [open, setOpen] = useState(false);
  return (
    <details
      className="studio-control-group studio-import-panel"
      open={open}
      onToggle={(event) => setOpen(event.currentTarget.open)}
    >
      <summary>
        <Icon name="code" />
        {t('Import HTML')}
      </summary>
      <p className="studio-help">
        {t(
          'HTML becomes editable elements. Scripts are omitted; images must use the media library.',
        )}
      </p>
      <label>
        {t('HTML markup')}
        <textarea
          className="studio-code-editor"
          rows={12}
          maxLength={200000}
          value={html}
          disabled={disabled}
          spellCheck={false}
          onChange={(event) => setHtml(event.target.value)}
        />
      </label>
      <button
        type="button"
        className="button"
        disabled={disabled || !html.trim()}
        onClick={async () => {
          if (await onImport(html)) {
            setHtml('');
            setOpen(false);
          }
        }}
      >
        {t(disabled ? 'Importing…' : 'Import layout')}
      </button>
    </details>
  );
}
