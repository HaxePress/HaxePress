import { useEffect, useState } from 'react';

export default function CategoryInput({
  id,
  name = 'category',
  value,
  onChange,
  initialOptions = [],
  required = false,
  disabled = false,
  placeholder = 'Type to find a category…',
}: {
  id: string;
  name?: string;
  value: string;
  onChange: (value: string) => void;
  initialOptions?: string[];
  required?: boolean;
  disabled?: boolean;
  placeholder?: string;
}) {
  const [options, setOptions] = useState(initialOptions);
  useEffect(() => {
    if (disabled) return;
    const controller = new AbortController();
    const timer = setTimeout(async () => {
      try {
        const parameters = new URLSearchParams({ q: value.trim() });
        const response = await fetch('/categories/options?' + parameters, {
          signal: controller.signal,
          headers: { Accept: 'application/json' },
        });
        if (!response.ok) return;
        const data: { categories: string[] } = await response.json();
        setOptions(data.categories);
      } catch (error) {
        if (!(error instanceof DOMException && error.name === 'AbortError'))
          setOptions(initialOptions);
      }
    }, 200);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [value, disabled]);
  return (
    <>
      <input
        id={id}
        name={name}
        list={id + '-options'}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        autoComplete="off"
        maxLength={80}
        required={required}
        disabled={disabled}
        placeholder={placeholder}
      />
      <datalist id={id + '-options'}>
        {options.map((option) => (
          <option key={option} value={option} />
        ))}
      </datalist>
    </>
  );
}
