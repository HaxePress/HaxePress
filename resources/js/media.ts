export interface MediaRules {
  uploadUrl: string;
  maxBytes: number;
  mimeTypes: string[];
  extensions: string[];
  imagePattern: string;
}

export async function uploadManagedImage(file: File, csrfToken: string | null, rules?: MediaRules) {
  if (!rules) throw new Error('Reload the page before uploading an image.');
  if (!file.size) throw new Error('Choose a non-empty image.');
  if (file.size > rules.maxBytes) {
    throw new Error(`Choose an image smaller than ${rules.maxBytes / 1024 / 1024} MB.`);
  }
  const extension = file.name.split('.').pop()?.toLowerCase() || '';
  if (!rules.mimeTypes.includes(file.type) && !rules.extensions.includes(extension)) {
    throw new Error('Choose a JPEG, PNG, WebP or GIF image.');
  }
  const response = await fetch(rules.uploadUrl, {
    method: 'POST',
    credentials: 'same-origin',
    headers: {
      'Content-Type': file.type || 'application/octet-stream',
      'X-CSRF-TOKEN': csrfToken || '',
      'X-File-Name': encodeURIComponent(file.name.slice(0, 180)),
      Accept: 'application/json',
    },
    body: file,
  });
  if (response.status === 419) {
    throw new Error('Your session expired. Reload the page and sign in again.');
  }
  if (response.redirected || !response.headers.get('content-type')?.includes('application/json')) {
    throw new Error('Sign in again before uploading an image.');
  }
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error || 'The image could not be uploaded. Please try again.');
  }
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
