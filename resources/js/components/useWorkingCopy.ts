import { router } from '@inertiajs/react';
import { useEffect, useRef, useState } from 'react';

export default function useWorkingCopy<T extends { id: string }>({
  data,
  enabled,
  base,
  draftKey,
  initialVersion,
  csrfToken,
}: {
  data: T;
  enabled: boolean;
  base: string;
  draftKey: string;
  initialVersion: number;
  csrfToken: string | null;
}) {
  const signature = JSON.stringify(data);
  const [saved, setSaved] = useState(signature);
  const [message, setMessage] = useState('');
  const version = useRef(initialVersion);
  useEffect(() => {
    if (!enabled || signature === saved) return;
    const controller = new AbortController();
    setMessage('Working copy will be saved…');
    const timeout = setTimeout(async () => {
      setMessage('Saving working copy…');
      version.current++;
      const values = new URLSearchParams();
      for (const [key, value] of Object.entries(data))
        values.set(key, typeof value === 'boolean' ? (value ? '1' : '0') : value);
      values.set('draft_key', draftKey);
      values.set('draft_version', String(version.current));
      try {
        const response = await fetch(`${base}/working-copy`, {
          method: 'POST',
          body: values,
          signal: controller.signal,
          headers: { 'X-CSRF-TOKEN': csrfToken || '', Accept: 'application/json' },
        });
        const result = await response.json();
        if (!response.ok) throw new Error(result.error || 'Your working copy could not be saved.');
        setSaved(signature);
        setMessage('Working copy saved');
        if (!data.id) {
          const url = new URL(window.location.href);
          if (url.searchParams.get('draft') !== result.key) {
            url.searchParams.set('draft', result.key);
            router.replace({
              url: `${url.pathname}${url.search}`,
              preserveState: true,
              preserveScroll: true,
            });
          }
        }
      } catch (failure) {
        if (!(failure instanceof Error) || failure.name !== 'AbortError')
          setMessage(
            failure instanceof Error ? failure.message : 'Working copy could not be saved.',
          );
      }
    }, 1800);
    return () => {
      clearTimeout(timeout);
      controller.abort();
    };
  }, [signature, enabled, base, draftKey, csrfToken, saved]);
  return { message, protected: signature === saved };
}
