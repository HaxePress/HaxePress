import { useEffect, useState } from 'react';
import { useTranslation } from '../i18n';

export default function CollectionPicker({
  id,
  value,
  onChange,
  archives = false,
}: {
  id: string;
  value: string;
  onChange: (value: string) => void;
  archives?: boolean;
}) {
  const { t } = useTranslation();
  const [query, setQuery] = useState('');
  const [choices, setChoices] = useState<{ key: string; name: string }[]>([]);
  const [error, setError] = useState('');
  useEffect(() => {
    const abort = new AbortController();
    const timer = setTimeout(async () => {
      try {
        const search = encodeURIComponent(query);
        const selected = encodeURIComponent(value);
        const archiveParam = archives ? '&archives=1' : '';
        const filters = `public=1&q=${search}&selected=${selected}${archiveParam}`;
        const response = await fetch(`/admin/content-types/options?${filters}`, {
          signal: abort.signal,
        });
        if (!response.ok) throw new Error('Collections could not be loaded.');
        setChoices((await response.json()).types);
        setError('');
      } catch (failure) {
        if (!abort.signal.aborted)
          setError(failure instanceof Error ? failure.message : 'Collections could not be loaded.');
      }
    }, 200);
    return () => {
      clearTimeout(timer);
      abort.abort();
    };
  }, [query, value, archives]);
  return (
    <div className="content-picker">
      <label className="sr-only" htmlFor={`${id}-search`}>
        {t('Search collections')}
      </label>
      <input
        id={`${id}-search`}
        type="search"
        maxLength={100}
        value={query}
        placeholder={t('Search collections')}
        onChange={(event) => setQuery(event.target.value)}
      />
      <select id={id} value={value} onChange={(event) => onChange(event.target.value)} required>
        <option value="">{t('Choose a collection')}</option>
        {choices.map((choice) => (
          <option key={choice.key} value={choice.key}>
            {t(choice.name)}
          </option>
        ))}
      </select>
      {error && (
        <p className="field-help" role="alert">
          {t(error)}
        </p>
      )}
    </div>
  );
}
