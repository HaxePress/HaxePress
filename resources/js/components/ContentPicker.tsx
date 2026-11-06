import { useEffect, useState } from 'react';
import { useTranslation } from '../i18n';

interface ContentChoice {
  id: number;
  title: string;
  url: string;
  content_type: string;
}

export default function ContentPicker({
  id,
  value,
  onChange,
  required = false,
}: {
  id: string;
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
}) {
  const { t } = useTranslation();
  const [query, setQuery] = useState('');
  const [choices, setChoices] = useState<ContentChoice[]>([]);
  const [error, setError] = useState('');
  useEffect(() => {
    const abort = new AbortController();
    const timer = setTimeout(async () => {
      try {
        const response = await fetch(
          `/admin/content-options?q=${encodeURIComponent(query)}&selected=${encodeURIComponent(value)}`,
          { signal: abort.signal },
        );
        if (!response.ok) throw new Error('Published content could not be loaded.');
        setChoices((await response.json()).items);
        setError('');
      } catch (failure) {
        if (!abort.signal.aborted)
          setError(
            failure instanceof Error ? failure.message : 'Published content could not be loaded.',
          );
      }
    }, 200);
    return () => {
      clearTimeout(timer);
      abort.abort();
    };
  }, [query, value]);
  return (
    <div className="content-picker">
      <label className="sr-only" htmlFor={`${id}-search`}>
        {t('Search published content')}
      </label>
      <input
        id={`${id}-search`}
        type="search"
        value={query}
        maxLength={100}
        placeholder={t('Search published content')}
        onChange={(event) => setQuery(event.target.value)}
      />
      <select
        id={id}
        value={value}
        required={required}
        onChange={(event) => onChange(event.target.value)}
      >
        <option value="0">{t('Choose published content')}</option>
        {choices.map((choice) => (
          <option key={choice.id} value={choice.id}>
            {choice.title}
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
