import { useTranslation } from '../i18n';
import { useEffect, useState } from 'react';
import type { Tag } from '../types';

export default function TagPicker({
  value,
  onChange,
}: {
  value: Tag[];
  onChange: (tags: Tag[]) => void;
}) {
  const { t } = useTranslation();
  const [search, setSearch] = useState('');
  const [options, setOptions] = useState<Tag[]>([]);
  const [error, setError] = useState('');
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    const controller = new AbortController();
    const timeout = setTimeout(async () => {
      try {
        const response = await fetch('/admin/tags/options?q=' + encodeURIComponent(search), {
          signal: controller.signal,
          headers: { Accept: 'application/json' },
        });
        if (!response.ok) throw new Error('Tags could not be loaded.');
        const data: { tags: Tag[] } = await response.json();
        setOptions(data.tags);
        setError('');
      } catch (failure) {
        if (!(failure instanceof Error) || failure.name !== 'AbortError') {
          setError('Tags could not be loaded. Try searching again.');
        }
      }
    }, 200);
    return () => {
      clearTimeout(timeout);
      controller.abort();
    };
  }, [search, open]);

  const available = options.filter((option) => !value.some((tag) => tag.id === option.id));
  function add(tag: Tag) {
    if (value.length >= 10) return;
    onChange([...value, tag]);
    setSearch('');
  }

  return (
    <div className="tag-picker">
      <label htmlFor="tag-search">{t('Tags')}</label>
      {value.length > 0 && (
        <ul className="tag-chips" aria-label={t('Selected tags')}>
          {value.map((tag) => (
            <li key={tag.id}>
              {tag.name}
              <button
                type="button"
                aria-label={'Remove ' + tag.name}
                onClick={() => onChange(value.filter((item) => item.id !== tag.id))}
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      )}
      <input
        id="tag-search"
        type="search"
        value={search}
        maxLength={80}
        placeholder={t('Find a tag…')}
        disabled={value.length >= 10}
        onFocus={() => setOpen(true)}
        onChange={(event) => {
          setSearch(event.target.value);
          setOpen(true);
        }}
        onKeyDown={(event) => {
          if (event.key === 'Escape') setOpen(false);
          if (event.key === 'Enter') {
            event.preventDefault();
            if (available.length > 0) add(available[0]);
          }
        }}
        aria-expanded={open}
        aria-controls="tag-options"
      />
      {open && value.length < 10 && (
        <div className="tag-options" id="tag-options">
          {available.map((tag) => (
            <button key={tag.id} type="button" onClick={() => add(tag)}>
              {tag.name}
            </button>
          ))}
          {available.length === 0 && (
            <p>{t('No matching tags. Create tags in the Tags section.')}</p>
          )}
          <button className="tag-picker-close" type="button" onClick={() => setOpen(false)}>
            {t('Close suggestions')}
          </button>
        </div>
      )}
      {error && (
        <p className="field-error" role="alert">
          {t(error)}
        </p>
      )}
      <p className="field-help">{t('Choose up to 10 tags to connect related content.')}</p>
    </div>
  );
}
