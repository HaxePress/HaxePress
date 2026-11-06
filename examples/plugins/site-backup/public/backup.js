// Shared by the backups page and the installation step: the backup file
// header and the chunked upload the server verifies or restores.

export async function readBackupHeader(file) {
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

async function backupResponse(response) {
  const result = await response.json().catch(() => null);
  if (!response.ok || !result) {
    throw new Error(result?.error || 'The backup upload could not be completed.');
  }
  return result;
}

/** Uploads `file` to `${action}/uploads` in chunks, then posts `action` with the upload. */
export async function uploadBackup(action, file, csrfToken, options) {
  const uploads = `${action}/uploads`;
  const headers = {
    Accept: 'application/json',
    'X-CSRF-TOKEN': csrfToken || '',
  };
  const jsonHeaders = { ...headers, 'Content-Type': 'application/json' };
  const ticket = await backupResponse(
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
      const result = await backupResponse(
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
    return await backupResponse(
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
