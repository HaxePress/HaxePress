import * as z from 'zod/v4';

export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
export const encodedImage = z
  .string()
  .min(4)
  .max(Math.ceil(MAX_IMAGE_BYTES / 3) * 4);
export const attachedFile = z.object({
  download_url: z.string().max(4096),
  file_id: z.string().min(1).max(256),
  mime_type: z.string().max(128).optional(),
  file_name: z.string().max(180).optional(),
});
export const fileInputMetadata = { 'openai/fileParams': ['file'] };

export async function readBody(response: Response, limit: number): Promise<Buffer<ArrayBuffer>> {
  const reader = response.body?.getReader();
  if (!reader) return Buffer.alloc(0);
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const next = await reader.read();
    if (next.done) break;
    total += next.value.length;
    if (total > limit) {
      await reader.cancel();
      throw new Error('The CMS response exceeds its size limit.');
    }
    chunks.push(next.value);
  }
  return Buffer.concat(chunks);
}

export async function imageInput(
  base64: string | undefined,
  file: z.output<typeof attachedFile> | undefined,
  name: string | undefined,
  signal?: AbortSignal,
) {
  if (!file) {
    if (!base64 || !/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) {
      throw new Error('Supply an attached image or canonical Base64 image data.');
    }
    const bytes = Buffer.from(base64, 'base64');
    if (!bytes.length || bytes.length > MAX_IMAGE_BYTES || bytes.toString('base64') !== base64) {
      throw new Error('Supply an image under 5 MB as canonical Base64.');
    }
    return { bytes, name };
  }
  if (base64) throw new Error('Choose one source for the image.');
  const url = new URL(file.download_url);
  if (
    url.protocol !== 'https:' ||
    !url.hostname.endsWith('.oaiusercontent.com') ||
    url.port ||
    url.username ||
    url.password ||
    url.hash
  ) {
    throw new Error('Choose a ChatGPT attachment or supply canonical Base64 image data.');
  }
  const response = await fetch(url, {
    redirect: 'error',
    signal: signal
      ? AbortSignal.any([signal, AbortSignal.timeout(10000)])
      : AbortSignal.timeout(10000),
  });
  if (!response.ok || Number(response.headers.get('content-length')) > MAX_IMAGE_BYTES) {
    await response.body?.cancel();
    throw new Error('Choose an available image attachment under 5 MB.');
  }
  const bytes = await readBody(response, MAX_IMAGE_BYTES);
  if (!bytes.length) throw new Error('The image attachment was empty.');
  return { bytes, name: name ?? file.file_name };
}
