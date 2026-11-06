import { useState } from 'react';
import type { ContentFieldDefinition, CustomFieldValue, CustomFieldValues } from '../content';
import { useTranslation } from '../i18n';
import { uploadManagedImage, type MediaRules } from '../media';
import MediaPicker from './MediaPicker';
import Icon from './Icon';

export default function CustomFieldsEditor({
  definitions,
  values,
  publishing,
  onChange,
  onBusyChange,
  csrfToken,
  mediaRules,
}: {
  definitions: ContentFieldDefinition[];
  values: CustomFieldValues;
  publishing: boolean;
  onChange: (key: string, value: CustomFieldValue) => void;
  onBusyChange: (busy: boolean) => void;
  csrfToken: string | null;
  mediaRules?: MediaRules;
}) {
  const { t } = useTranslation();
  const [libraryField, setLibraryField] = useState<string | null>(null);
  const [uploading, setUploading] = useState<string | null>(null);
  const [error, setError] = useState('');

  async function upload(key: string, file?: File) {
    if (!file || uploading) return;
    setUploading(key);
    setError('');
    onBusyChange(true);
    try {
      const result = await uploadManagedImage(file, csrfToken, mediaRules);
      onChange(key, result.url);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'The image could not be uploaded.');
    } finally {
      setUploading(null);
      onBusyChange(false);
    }
  }

  if (!definitions.length) return null;
  return (
    <section className="custom-fields-editor" aria-labelledby="custom-fields-heading">
      <h2 id="custom-fields-heading">{t('Custom fields')}</h2>
      {error && (
        <p className="upload-status error" role="alert">
          {t(error)}
        </p>
      )}
      {definitions.map((field) => {
        const id = `custom-field-${field.key}`;
        const value = values[field.key] ?? null;
        const required = publishing && field.required;
        return (
          <div className="custom-field-control" key={field.key}>
            <label htmlFor={id}>
              {field.label} {required && <span aria-label={t('Required')}>*</span>}
              {!field.publicVisible && <small>{t('Private field')}</small>}
            </label>
            {field.kind === 'boolean' ? (
              <label className="checkbox-label">
                <input
                  id={id}
                  type="checkbox"
                  checked={value === true}
                  onChange={(event) => onChange(field.key, event.target.checked)}
                />
                <span>{t('Enabled')}</span>
              </label>
            ) : field.kind === 'textarea' ? (
              <textarea
                id={id}
                rows={4}
                maxLength={4000}
                required={required}
                value={value === null ? '' : String(value)}
                onChange={(event) => onChange(field.key, event.target.value)}
              />
            ) : field.kind === 'select' ? (
              <select
                id={id}
                required={required}
                value={value === null ? '' : String(value)}
                onChange={(event) => onChange(field.key, event.target.value)}
              >
                <option value="">{t('Choose an option')}</option>
                {field.options.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            ) : field.kind === 'image' ? (
              <div className="custom-field-image">
                {typeof value === 'string' &&
                  mediaRules &&
                  new RegExp(mediaRules.imagePattern).test(value) && (
                    <img src={value} alt={field.label} />
                  )}
                <div className="custom-field-image-actions">
                  <button
                    id={id}
                    className="button button-outline"
                    type="button"
                    onClick={() => setLibraryField(field.key)}
                  >
                    <Icon name="image" /> {t('Choose from library')}
                  </button>
                  <label className="button button-outline">
                    <Icon name="upload" />{' '}
                    {uploading === field.key ? t('Uploading image…') : t('Upload image')}
                    <input
                      type="file"
                      accept={mediaRules?.mimeTypes.join(',')}
                      disabled={Boolean(uploading)}
                      hidden
                      onChange={(event) => {
                        void upload(field.key, event.target.files?.[0]);
                        event.target.value = '';
                      }}
                    />
                  </label>
                  {value !== null && (
                    <button
                      className="button button-outline"
                      type="button"
                      onClick={() => onChange(field.key, null)}
                    >
                      {t('Remove image')}
                    </button>
                  )}
                </div>
              </div>
            ) : (
              <input
                id={id}
                type={field.kind === 'number' ? 'number' : field.kind === 'date' ? 'date' : 'text'}
                step={field.kind === 'number' ? 'any' : undefined}
                maxLength={240}
                required={required}
                value={value === null ? '' : String(value)}
                onChange={(event) => onChange(field.key, event.target.value)}
              />
            )}
            {field.help && (
              <p className="field-help" id={`${id}-help`}>
                {field.help}
              </p>
            )}
          </div>
        );
      })}
      <MediaPicker
        idPrefix="custom-fields-"
        open={libraryField !== null}
        onClose={() => setLibraryField(null)}
        onPick={(image) => {
          if (libraryField) onChange(libraryField, image.url);
        }}
      />
    </section>
  );
}
