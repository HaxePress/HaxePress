import { useTranslation } from '../i18n';
import type { ExtensionField } from '../types';

export default function PackageSettingField({
  packageId,
  field,
  value,
  onChange,
  secretSaved = false,
  clearSecret = false,
  onClearSecret,
}: {
  packageId: string;
  field: ExtensionField;
  value: string;
  onChange: (value: string) => void;
  secretSaved?: boolean;
  clearSecret?: boolean;
  onClearSecret?: (clear: boolean) => void;
}) {
  const { t } = useTranslation(packageId);
  const id = `setting-${field.key}`;
  const colorEnabled = field.required || value !== '';
  return (
    <div className="extension-setting">
      <label htmlFor={id}>
        {t(field.label)}
        {field.required ? ' *' : ''}
      </label>
      {field.kind === 'color' ? (
        <>
          {!field.required && (
            <label className="checkbox-label optional-color-toggle">
              <input
                type="checkbox"
                checked={colorEnabled}
                onChange={(event) =>
                  onChange(event.target.checked ? field.defaultValue || '#2457a6' : '')
                }
              />
              {t('Use custom color')}
            </label>
          )}
          <div className="setting-color-control">
            <input
              id={id}
              type="color"
              value={/^#[0-9a-f]{6}$/i.test(value) ? value : '#2457a6'}
              disabled={!colorEnabled}
              onChange={(event) => onChange(event.target.value)}
            />
            <input
              aria-label={t('{name} hex value', { name: t(field.label) })}
              type="text"
              value={value}
              disabled={!colorEnabled}
              pattern="#[0-9a-fA-F]{6}"
              maxLength={7}
              placeholder="#2457a6"
              required={field.required}
              onChange={(event) => onChange(event.target.value)}
            />
          </div>
        </>
      ) : field.kind === 'textarea' ? (
        <textarea
          id={id}
          rows={5}
          maxLength={2000}
          required={field.required}
          value={value}
          onChange={(event) => onChange(event.target.value)}
        />
      ) : field.kind === 'select' ? (
        <select
          id={id}
          value={value}
          required={field.required}
          onChange={(event) => onChange(event.target.value)}
        >
          {field.options.map((option) => (
            <option key={option.value} value={option.value}>
              {t(option.label)}
            </option>
          ))}
        </select>
      ) : field.kind === 'boolean' ? (
        <label className="checkbox-label">
          <input
            id={id}
            type="checkbox"
            checked={value === 'true'}
            onChange={(event) => onChange(event.target.checked ? 'true' : 'false')}
          />
          {t('Enabled')}
        </label>
      ) : (
        <input
          id={id}
          type={field.kind === 'secret' ? 'password' : field.kind === 'number' ? 'number' : 'text'}
          value={value}
          required={field.required && !secretSaved}
          min={field.kind === 'number' ? field.minimum : undefined}
          max={field.kind === 'number' ? field.maximum : undefined}
          step={field.kind === 'number' ? 'any' : undefined}
          maxLength={field.kind === 'secret' ? 2000 : 240}
          placeholder={secretSaved ? t('Saved value. Enter a replacement.') : undefined}
          autoComplete={field.kind === 'secret' ? 'new-password' : undefined}
          onChange={(event) => onChange(event.target.value)}
        />
      )}
      {field.help && <p className="field-help">{t(field.help)}</p>}
      {field.kind === 'secret' && secretSaved && onClearSecret && (
        <label className="checkbox-label">
          <input
            type="checkbox"
            checked={clearSecret}
            onChange={(event) => onClearSecret(event.target.checked)}
          />
          {t('Clear saved value')}
        </label>
      )}
    </div>
  );
}
