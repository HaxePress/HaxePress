import { useEffect, useState } from 'react';
import Icon from '../../components/Icon';
import { useTranslation } from '../../i18n';

export default function ColorControl({
  label,
  value,
  onChange,
  optional = false,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  optional?: boolean;
}) {
  const { t } = useTranslation();
  const [text, setText] = useState(value);
  useEffect(() => setText(value), [value]);
  return (
    <label className="studio-color-field">
      <span>{t(label)}</span>
      <span>
        <input
          type="color"
          aria-label={t(label)}
          value={value || '#ffffff'}
          onChange={(event) => onChange(event.target.value)}
        />
        <input
          type="text"
          aria-label={t('{field} hex', { field: t(label) })}
          placeholder={t('Inherit')}
          maxLength={7}
          value={text}
          spellCheck={false}
          onChange={(event) => {
            const next = event.target.value;
            setText(next);
            if (/^#[0-9a-f]{6}$/i.test(next) || (optional && next === '')) onChange(next);
          }}
          onBlur={() => setText(value)}
        />
        {optional && value && (
          <button
            type="button"
            className="icon-button"
            aria-label={t('Reset {field}', { field: t(label) })}
            onClick={() => onChange('')}
          >
            <Icon name="x" />
          </button>
        )}
      </span>
    </label>
  );
}
