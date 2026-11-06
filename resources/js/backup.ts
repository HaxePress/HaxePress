export const backupFileTypes = '.hxpress';
export const backupsPath = '/admin/backups';
export const encryptedBackupWarning =
  'This file is unusable on projects with a different APP_KEY. If the original APP_KEY is lost, the backup is permanently unrecoverable.';

export const backupSections = [
  ['content', 'Content'],
  ['themes', 'Themes'],
  ['plugins', 'Plugins'],
] as const;

export type BackupSections = Record<(typeof backupSections)[number][0], boolean>;

export async function readBackupHeader(file: File) {
  const bytes = new Uint8Array(await file.slice(0, 80).arrayBuffer());
  const magic = new TextDecoder().decode(bytes.slice(0, 8));
  const length = bytes[11];
  if (
    magic !== 'HXPRESS\0' ||
    bytes[8] !== 2 ||
    bytes[9] !== 1 ||
    bytes[10] > 1 ||
    !length ||
    length > 64 ||
    bytes.length < 16 + length
  ) {
    return null;
  }
  return {
    cmsVersion: new TextDecoder().decode(bytes.slice(12, 12 + length)),
    encrypted: bytes[10] === 1,
  };
}

export async function backupResponse<T>(response: Response): Promise<T> {
  const result = await response.json().catch(() => null);
  if (!response.ok || !result) {
    throw new Error(result?.error || 'The backup upload could not be completed.');
  }
  return result;
}

export async function uploadBackup<T>(
  action: string,
  file: File,
  csrfToken: string | null,
  options?: URLSearchParams,
): Promise<T> {
  const uploads = `${action}/uploads`;
  const headers = {
    Accept: 'application/json',
    'X-CSRF-TOKEN': csrfToken || '',
  };
  const jsonHeaders = { ...headers, 'Content-Type': 'application/json' };
  const ticket = await backupResponse<{ id: string; chunkSize: number }>(
    await fetch(uploads, {
      method: 'POST',
      headers: jsonHeaders,
      body: JSON.stringify({ size: file.size }),
    }),
  );
  if (
    !/^[A-Za-z0-9_-]{32}$/.test(ticket.id) ||
    !Number.isInteger(ticket.chunkSize) ||
    ticket.chunkSize < 1 ||
    ticket.chunkSize > 1024 * 1024
  ) {
    throw new Error('The server returned an invalid backup upload.');
  }

  const staged = `${uploads}/${ticket.id}`;
  try {
    const chunkHeaders = { ...headers, 'Content-Type': 'application/octet-stream' };
    for (let offset = 0, index = 0; offset < file.size; offset += ticket.chunkSize, index++) {
      const chunk = file.slice(offset, offset + ticket.chunkSize);
      const result = await backupResponse<{ received: number }>(
        await fetch(`${staged}/${index}`, {
          method: 'POST',
          headers: chunkHeaders,
          body: chunk,
        }),
      );
      if (result.received !== index) {
        throw new Error('The server returned an invalid backup chunk confirmation.');
      }
    }
    const query = options?.size ? `?${options}` : '';
    return await backupResponse<T>(
      await fetch(`${action}${query}`, {
        method: 'POST',
        headers: jsonHeaders,
        body: JSON.stringify({ upload: ticket.id }),
      }),
    );
  } catch (failure) {
    void fetch(staged, { method: 'DELETE', headers, keepalive: true }).catch(() => undefined);
    throw failure;
  }
}
