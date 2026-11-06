import { useEffect, useRef, useState } from 'react';
import type useDesignSaving from './useDesignSaving';
import type { DesignSnapshot } from './useDesignSaving';
import { ThemeDesignerConnection } from './ThemeDesignerConnection';
import { installBrowserTools } from './browser-tools';

export interface RemoteDesign extends DesignSnapshot {
  version: number;
  publishedVersion: number;
  enabled: boolean;
}

export default function useThemeAiSync({
  id,
  snapshot,
  saving,
  blocked,
  onLoad,
  getEditorContext,
}: {
  id: string;
  snapshot: DesignSnapshot;
  saving: ReturnType<typeof useDesignSaving>;
  blocked: boolean;
  onLoad: (snapshot: RemoteDesign) => void;
  getEditorContext: () => { scope: string; selection: unknown };
}) {
  const [available, setAvailable] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [remoteVersion, setRemoteVersion] = useState(saving.version);
  const [connection, setConnection] = useState<ThemeDesignerConnection | null>(null);
  const [, refreshConnection] = useState(0);
  const latest = useRef({ snapshot, saving, onLoad, blocked, getEditorContext });
  latest.current = { snapshot, saving, onLoad, blocked, getEditorContext };
  const identity = useRef(id);
  identity.current = id;
  const inFlight = useRef(false);
  const alive = useRef(true);

  async function load(force = false) {
    if (inFlight.current) return;
    inFlight.current = true;
    setLoading(true);
    setError('');
    const before = JSON.stringify(latest.current.snapshot);
    try {
      const response = await fetch(`/admin/themes/${id}/design/snapshot`, {
        headers: { Accept: 'application/json' },
        signal: AbortSignal.timeout(15000),
      });
      if (!response.ok || !response.headers.get('content-type')?.includes('application/json'))
        throw new Error();
      const result = await response.json();
      if (!alive.current || identity.current !== id) return;
      const current = latest.current;
      if (
        current.saving.saving ||
        current.saving.publishing ||
        current.blocked ||
        (!force && (current.saving.dirty || JSON.stringify(current.snapshot) !== before))
      ) {
        setAvailable(true);
        return;
      }
      const next: RemoteDesign = result.theme;
      const nextSnapshot = { name: next.name, document: next.document };
      if (current.saving.adopt(nextSnapshot, next.version, next.publishedVersion, next.enabled)) {
        current.onLoad(next);
        setRemoteVersion(next.version);
        setAvailable(false);
      }
    } catch {
      if (alive.current && identity.current === id)
        setError('The latest design could not be loaded.');
    } finally {
      inFlight.current = false;
      if (alive.current && identity.current === id) setLoading(false);
    }
  }

  useEffect(() => {
    alive.current = true;
    const socket = new ThemeDesignerConnection(id);
    setConnection(socket);
    const disposeTools = installBrowserTools(
      socket,
      () => ({
        themeId: id,
        version: latest.current.saving.version,
        dirty: latest.current.saving.dirty,
        ...latest.current.getEditorContext(),
      }),
      () => {
        const current = latest.current;
        return (
          !current.saving.dirty &&
          !current.saving.saving &&
          !current.saving.publishing &&
          !current.blocked
        );
      },
    );
    const unsubscribe = socket.subscribe((event) => {
      if (!alive.current || identity.current !== id) return;
      refreshConnection((revision) => revision + 1);
      if (event.type === 'design_changed') {
        setRemoteVersion((version) => Math.max(version, event.change.version));
      }
      if (event.type === 'state' && socket.status === 'connected') {
        // One bounded status read after reconnect catches changes missed while offline.
        void fetch(`/admin/themes/${id}/design/status`, {
          headers: { Accept: 'application/json' },
        })
          .then(async (response) => {
            if (!response.ok || !response.headers.get('content-type')?.includes('application/json'))
              return;
            const result = await response.json();
            if (alive.current && identity.current === id)
              setRemoteVersion((version) => Math.max(version, result.version));
          })
          .catch(() => {});
      }
    });
    void socket.ready().catch(() => {});
    return () => {
      alive.current = false;
      unsubscribe();
      disposeTools();
      void socket.close();
    };
  }, [id]);

  useEffect(() => {
    if (remoteVersion <= saving.version) {
      setAvailable(false);
      return;
    }
    if (saving.dirty || saving.saving || saving.publishing || blocked) {
      setAvailable(true);
    } else if (!loading && !error) {
      void load();
    }
  }, [
    remoteVersion,
    saving.version,
    saving.dirty,
    saving.saving,
    saving.publishing,
    blocked,
    loading,
  ]);

  return {
    available,
    error,
    loading,
    load,
    connection,
    status: connection?.status || 'connecting',
    presence: connection?.presence || { browsers: 0, llms: 0 },
    permissions: connection?.permissions || { read: false, edit: false, media: false },
  };
}
