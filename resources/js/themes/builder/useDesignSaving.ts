import { useEffect, useRef, useState } from 'react';
import type { ThemeDocument } from './types';

export interface DesignSnapshot {
  name: string;
  document: ThemeDocument;
}
export default function useDesignSaving({
  id,
  csrfToken,
  snapshot,
  initialVersion,
  initialPublishedVersion,
  initialActive,
  autoSave,
}: {
  id: string;
  csrfToken: string | null;
  snapshot: DesignSnapshot;
  initialVersion: number;
  initialPublishedVersion: number;
  initialActive: boolean;
  autoSave: boolean;
}) {
  const [version, setVersion] = useState(initialVersion);
  const [publishedVersion, setPublishedVersion] = useState(initialPublishedVersion);
  const [active, setActive] = useState(initialActive);
  const [saved, setSaved] = useState(JSON.stringify(snapshot));
  const [saving, setSaving] = useState(false);
  const [publishing, setPublishing] = useState(false);
  const [paused, setPaused] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const current = useRef(snapshot);
  current.current = snapshot;
  const currentVersion = useRef(version);
  const savedValue = useRef(saved);
  const write = useRef<Promise<boolean> | null>(null);
  const manual = useRef(false);
  const serialized = JSON.stringify(snapshot);
  const dirty = serialized !== saved;

  async function save(action: 'save' | 'publish' | 'launch', automatic = false): Promise<boolean> {
    if (automatic && manual.current) return false;
    if (!automatic) {
      if (manual.current) return false;
      manual.current = true;
      setPublishing(true);
    }

    if (write.current) {
      const previous = await write.current;
      if (!previous) {
        if (!automatic) {
          manual.current = false;
          setPublishing(false);
        }
        return false;
      }
      if (automatic) return true;
    }
    const next = current.current;
    const encoded = JSON.stringify(next);
    if (action === 'save' && encoded === savedValue.current) {
      if (!automatic) {
        manual.current = false;
        setPublishing(false);
      }
      return true;
    }
    setSaving(true);
    setError('');
    if (!automatic) setNotice('');
    const operation = (async () => {
      try {
        const response = await fetch(`/admin/themes/${id}/design`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-TOKEN': csrfToken || '',
            Accept: 'application/json',
          },
          body: JSON.stringify({
            name: next.name,
            design: JSON.stringify(next.document),
            version: String(currentVersion.current),
            action,
          }),
        });
        if (
          response.redirected ||
          !response.headers.get('content-type')?.includes('application/json')
        )
          throw new Error('Your session expired. Reload the page and sign in again.');
        const result = await response.json();
        if (typeof result.version === 'number') {
          currentVersion.current = result.version;
          setVersion(result.version);
          setPublishedVersion(result.publishedVersion);
          savedValue.current = encoded;
          setSaved(encoded);
        }
        if (typeof result.active === 'boolean') setActive(result.active);
        if (!response.ok) throw new Error(result.error || 'The design could not be saved.');
        setPaused(false);
        if (!automatic) setNotice(result.notice);
        return true;
      } catch (failure) {
        setError(failure instanceof Error ? failure.message : 'The design could not be saved.');
        setPaused(true);
        return false;
      } finally {
        setSaving(false);
        if (!automatic) {
          manual.current = false;
          setPublishing(false);
        }
        write.current = null;
      }
    })();
    write.current = operation;
    return operation;
  }
  useEffect(() => setNotice(''), [serialized]);
  useEffect(() => {
    if (!autoSave || !dirty || saving || publishing || paused || snapshot.name.trim().length < 2)
      return;
    const timer = setTimeout(() => void save('save', true), 1200);
    return () => clearTimeout(timer);
  }, [autoSave, serialized, dirty, saving, publishing, paused]);
  return {
    version,
    publishedVersion,
    active,
    dirty,
    saving,
    publishing,
    error,
    notice,
    adopt: (
      next: DesignSnapshot,
      nextVersion: number,
      nextPublishedVersion: number,
      nextActive: boolean,
    ) => {
      if (write.current || manual.current) return false;
      const encoded = JSON.stringify(next);
      current.current = next;
      currentVersion.current = nextVersion;
      savedValue.current = encoded;
      setVersion(nextVersion);
      setPublishedVersion(nextPublishedVersion);
      setActive(nextActive);
      setSaved(encoded);
      setError('');
      setNotice('');
      setPaused(false);
      return true;
    },
    save,
    retry: () => {
      setPaused(false);
      return save('save');
    },
  };
}
