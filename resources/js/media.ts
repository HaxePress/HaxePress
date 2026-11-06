export interface MediaRules {
  uploadUrl: string;
  maxBytes: number;
  mimeTypes: string[];
  extensions: string[];
  imagePattern: string;
}

async function sha256(file: Blob): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer());
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function uploadError(response: Response): Promise<never> {
  if (response.status === 419) {
    throw new Error('Your session expired. Reload the page and sign in again.');
  }
  if (response.redirected) throw new Error('Sign in again before uploading an image.');
  if (response.headers.get('content-type')?.includes('application/json')) {
    const data = await response.json();
    if (typeof data.error === 'string') throw new Error(data.error);
  }
  throw new Error('The image could not be uploaded. Please try again.');
}

export async function uploadManagedImage(file: File, csrfToken: string | null, rules?: MediaRules) {
  if (!rules) throw new Error('Reload the page before uploading an image.');
  if (!file.size) throw new Error('Choose a non-empty image.');
  if (file.size > rules.maxBytes) {
    throw new Error(`Choose an image smaller than ${rules.maxBytes / 1024 / 1024} MB.`);
  }
  const extension = file.name.split('.').pop()?.toLowerCase() || '';
  if (!rules.mimeTypes.includes(file.type) && !rules.extensions.includes(extension)) {
    throw new Error('Choose a JPEG, PNG or GIF image.');
  }
  if (!globalThis.crypto?.subtle) {
    throw new Error('Use HTTPS or localhost to verify image uploads.');
  }
  const originalHash = await sha256(file);
  const staged = await fetch(rules.uploadUrl, {
    method: 'POST',
    credentials: 'same-origin',
    headers: {
      'Content-Type': file.type || 'application/octet-stream',
      'X-CSRF-TOKEN': csrfToken || '',
      'X-File-Name': encodeURIComponent(file.name.slice(0, 180)),
      Accept: 'image/*, application/json',
    },
    body: file,
  });
  if (staged.redirected || staged.status !== 202) await uploadError(staged);
  const id = staged.headers.get('X-Upload-Id');
  const image = await staged.blob();
  if (!id || !rules.mimeTypes.includes(image.type) || image.size !== file.size) {
    throw new Error('The server returned an invalid image upload.');
  }
  const uploadedHash = await sha256(image);
  if (originalHash !== uploadedHash) {
    throw new Error('The uploaded image does not match the selected file.');
  }
  const preview = new Image();
  const objectUrl = URL.createObjectURL(image);
  try {
    preview.src = objectUrl;
    await preview.decode();
  } catch {
    throw new Error('The uploaded image could not be displayed.');
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
  const { naturalWidth: width, naturalHeight: height } = preview;
  if (width < 1 || height < 1 || width > 10000 || height > 10000 || width * height > 20000000) {
    throw new Error('Choose an image under 20 megapixels and 10,000 pixels per dimension.');
  }
  const response = await fetch(`${rules.uploadUrl}/verify`, {
    method: 'POST',
    credentials: 'same-origin',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-TOKEN': csrfToken || '',
      Accept: 'application/json',
    },
    body: JSON.stringify({ id, sha256: uploadedHash, width, height }),
  });
  if (response.redirected || response.status !== 201) await uploadError(response);
  if (!response.headers.get('content-type')?.includes('application/json')) {
    throw new Error('The server returned an invalid image confirmation.');
  }
  const data = await response.json();
  if (typeof data.url !== 'string' || !new RegExp(rules.imagePattern).test(data.url)) {
    throw new Error('The upload returned an invalid image address.');
  }
  const description =
    file.name
      .replace(/\.[^.]+$/, '')
      .replace(/[_-]+/g, ' ')
      .replace(/[\[\]\\\r\n]/g, ' ')
      .trim()
      .slice(0, 120) || 'Image description';
  return { url: data.url as string, description };
}
