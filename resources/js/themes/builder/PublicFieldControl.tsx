import { useEffect, useState } from 'react';
import { useTranslation } from '../../i18n';

export const publicFields = [
  ['item.title', 'Content title'],
  ['item.excerpt', 'Content summary'],
  ['item.url', 'Content link'],
  ['item.image', 'Content image'],
  ['item.image_alt', 'Image description'],
  ['item.category', 'Category'],
  ['item.publishedLabel', 'Publication date'],
  ['item.updatedLabel', 'Last updated date'],
  ['item.readMinutes', 'Reading time'],
  ['site.site_name', 'Site name'],
  ['site.description', 'Site description'],
  ['site.publisher_name', 'Publisher name'],
  ['site.about_site', 'About the site'],
  ['collection.name', 'Collection name'],
  ['collection.description', 'Collection description'],
  ['collection.publicBase', 'Collection link'],
  ['page.count', 'Total content count'],
  ['page.resultCount', 'Current result count'],
] as const;

export default function PublicFieldControl({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  const { t } = useTranslation();
  const isCustom = Boolean(value) && !publicFields.some(([path]) => path === value);
  const [custom, setCustom] = useState(isCustom);
  useEffect(() => {
    if (value) setCustom(isCustom);
  }, [value]);
  return (
    <>
      <label>
        {t(label)}
        <select
          value={custom ? '$custom' : value}
          onChange={(event) => {
            const next = event.target.value;
            setCustom(next === '$custom');
            if (next !== '$custom') onChange(next);
          }}
        >
          <option value="">{t('No connection')}</option>
          <optgroup label={t('Content')}>
            {publicFields
              .filter(([path]) => path.startsWith('item.'))
              .map(([path, name]) => (
                <option key={path} value={path}>
                  {t(name)}
                </option>
              ))}
          </optgroup>
          <optgroup label={t('Site and page')}>
            {publicFields
              .filter(([path]) => !path.startsWith('item.'))
              .map(([path, name]) => (
                <option key={path} value={path}>
                  {t(name)}
                </option>
              ))}
          </optgroup>
          <option value="$custom">{t('Another public field')}</option>
        </select>
      </label>
      {custom && (
        <label>
          {t('Public field path')}
          <input
            value={value}
            placeholder="item.fields.custom_field"
            maxLength={120}
            onChange={(event) => onChange(event.target.value)}
          />
        </label>
      )}
    </>
  );
}
