import type { ContentFieldDefinition, CustomFieldValues } from '../content';
import { useTranslation } from '../i18n';

export default function FieldValues({
  definitions = [],
  values = {},
}: {
  definitions?: ContentFieldDefinition[];
  values?: CustomFieldValues;
}) {
  const { t } = useTranslation();
  const fields = definitions.filter(
    (field) => field.publicVisible && values[field.key] !== null && values[field.key] !== undefined,
  );
  if (!fields.length) return null;
  return (
    <dl className="content-field-values">
      {fields.map((field) => {
        const value = values[field.key];
        const option =
          field.kind === 'select' ? field.options.find((choice) => choice.value === value) : null;
        return (
          <div key={field.key}>
            <dt>{field.label}</dt>
            <dd>
              {field.kind === 'image' && typeof value === 'string' ? (
                <img src={value} alt={field.label} loading="lazy" />
              ) : field.kind === 'boolean' ? (
                t(value === true ? 'Yes' : 'No')
              ) : (
                option?.label || String(value)
              )}
            </dd>
          </div>
        );
      })}
    </dl>
  );
}
