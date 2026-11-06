import { router } from '@inertiajs/react';
import { useEffect, useState } from 'react';
import type { PublicCollection } from '../content';
import { useTranslation } from '../i18n';
import { useSiteHref } from '../themes/navigation';
import CategoryInput from './CategoryInput';

export default function ContentFilters({
  collection,
  path,
  query,
  category,
  categories = [],
  tag = '',
  fieldFilters = {},
}: {
  collection: PublicCollection;
  path: string;
  query: string;
  category: string;
  categories?: string[];
  tag?: string;
  fieldFilters?: Record<string, string>;
}) {
  const { t } = useTranslation();
  const siteHref = useSiteHref();
  const [search, setSearch] = useState(query);
  const [selectedCategory, setSelectedCategory] = useState(category);
  const [fields, setFields] = useState(fieldFilters);
  useEffect(() => setSearch(query), [query]);
  useEffect(() => setSelectedCategory(category), [category]);
  useEffect(() => setFields(fieldFilters), [fieldFilters]);
  const filters = collection.fields.filter((field) => field.filterable && field.publicVisible);
  return (
    <form
      className="cms-content-filters"
      action={siteHref(path)}
      method="get"
      onSubmit={(event) => {
        event.preventDefault();
        const values: Record<string, string> = { q: search, type: collection.key };
        if (collection.features.includes('categories')) values.category = selectedCategory;
        if (tag) values.tag = tag;
        for (const field of filters) {
          if (fields[field.key]) values[`field_${field.key}`] = fields[field.key];
        }
        router.get(siteHref(path), values, { preserveState: true });
      }}
    >
      <div>
        <label htmlFor="content-query">{t('Search content')}</label>
        <input
          id="content-query"
          name="q"
          type="search"
          maxLength={120}
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder={t('Find content…')}
        />
      </div>
      {collection.features.includes('categories') && (
        <div>
          <label htmlFor="content-category">{t('Category')}</label>
          <CategoryInput
            id="content-category"
            value={selectedCategory}
            onChange={setSelectedCategory}
            initialOptions={categories}
            placeholder={t('All categories')}
          />
        </div>
      )}
      {filters.map((field) => (
        <div key={field.key}>
          <label htmlFor={`filter-${field.key}`}>{field.label}</label>
          {field.kind === 'select' || field.kind === 'boolean' ? (
            <select
              id={`filter-${field.key}`}
              name={`field_${field.key}`}
              value={fields[field.key] || ''}
              onChange={(event) =>
                setFields((previous) => ({ ...previous, [field.key]: event.target.value }))
              }
            >
              <option value="">{t('Any value')}</option>
              {field.kind === 'boolean' ? (
                <>
                  <option value="true">{t('Yes')}</option>
                  <option value="false">{t('No')}</option>
                </>
              ) : (
                field.options.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))
              )}
            </select>
          ) : (
            <input
              id={`filter-${field.key}`}
              name={`field_${field.key}`}
              type={field.kind === 'number' ? 'number' : field.kind === 'date' ? 'date' : 'text'}
              step={field.kind === 'number' ? 'any' : undefined}
              maxLength={240}
              value={fields[field.key] || ''}
              onChange={(event) =>
                setFields((previous) => ({ ...previous, [field.key]: event.target.value }))
              }
            />
          )}
        </div>
      ))}
      {tag && <input type="hidden" name="tag" value={tag} />}
      <input type="hidden" name="type" value={collection.key} />
      <button className="button" type="submit">
        {t('Search')}
      </button>
    </form>
  );
}
