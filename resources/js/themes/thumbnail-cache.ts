const cacheName = 'haxepress-theme-previews-v2';
const cacheLifetime = 30 * 60 * 1000;
const cacheLimit = 32;
const captureTimeout = 20000;

interface PreviewJob {
  source: string;
  signal: AbortSignal;
  resolve: (image: Blob) => void;
  reject: (error: unknown) => void;
  cancel: () => void;
}

const jobs: PreviewJob[] = [];
let rendering = false;

function aborted(): DOMException {
  return new DOMException('Preview cancelled.', 'AbortError');
}

async function cachedPreview(source: string): Promise<Blob | null> {
  try {
    const cache = await caches.open(cacheName);
    const response = await cache.match(source);
    if (!response) return null;
    const createdAt = Number(response.headers.get('X-Preview-Created'));
    if (
      createdAt + cacheLifetime <= Date.now() ||
      response.headers.get('Content-Type') !== 'image/png'
    ) {
      await cache.delete(source);
      return null;
    }
    return response.blob();
  } catch {
    return null;
  }
}

async function storePreview(source: string, image: Blob): Promise<void> {
  try {
    const cache = await caches.open(cacheName);
    await cache.put(
      source,
      new Response(image, {
        headers: { 'Content-Type': 'image/png', 'X-Preview-Created': String(Date.now()) },
      }),
    );
    const entries = await cache.keys();
    for (const entry of entries.slice(0, Math.max(0, entries.length - cacheLimit))) {
      await cache.delete(entry);
    }
  } catch {
    // A disabled or full cache must not prevent the current preview from displaying.
  }
}

function capturePreview(source: string, signal: AbortSignal): Promise<Blob> {
  return new Promise((resolve, reject) => {
    if (signal.aborted) {
      reject(aborted());
      return;
    }
    const frame = document.createElement('iframe');
    const captureId = crypto.randomUUID();
    frame.className = 'theme-thumbnail-capture-frame';
    frame.title = 'Theme preview capture';
    frame.tabIndex = -1;
    frame.inert = true;
    frame.setAttribute('aria-hidden', 'true');
    let settled = false;
    const finish = (image?: Blob, error?: unknown) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      signal.removeEventListener('abort', cancel);
      window.removeEventListener('message', captured);
      frame.remove();
      if (image) resolve(image);
      else reject(error);
    };
    const cancel = () => finish(undefined, aborted());
    const captured = (event: MessageEvent) => {
      if (event.origin !== location.origin || event.source !== frame.contentWindow) return;
      const result = event.data;
      if (result?.type !== 'haxepress:theme-preview' || result.captureId !== captureId) return;
      if (
        result.image instanceof Blob &&
        result.image.type === 'image/png' &&
        result.image.size > 0
      ) {
        finish(result.image);
      } else {
        finish(undefined, new Error('Theme preview could not be captured.'));
      }
    };
    const timeout = window.setTimeout(
      () => finish(undefined, new Error('Theme preview timed out.')),
      captureTimeout,
    );
    signal.addEventListener('abort', cancel, { once: true });
    window.addEventListener('message', captured);
    frame.addEventListener('error', () =>
      finish(undefined, new Error('Theme preview could not be loaded.')),
    );
    frame.addEventListener(
      'load',
      () => {
        if (!frame.contentDocument?.querySelector('[data-cms-site]')) {
          finish(undefined, new Error('Theme preview is unavailable.'));
        }
      },
      { once: true },
    );
    const url = new URL(source, location.origin);
    url.searchParams.set('thumbnailCapture', captureId);
    frame.src = url.href;
    document.body.appendChild(frame);
  });
}

async function renderQueue(): Promise<void> {
  if (rendering) return;
  rendering = true;
  try {
    let job: PreviewJob | undefined;
    while ((job = jobs.shift())) {
      try {
        if (job.signal.aborted) throw aborted();
        const cached = await cachedPreview(job.source);
        if (job.signal.aborted) throw aborted();
        const image = cached || (await capturePreview(job.source, job.signal));
        if (job.signal.aborted) throw aborted();
        if (!cached) await storePreview(job.source, image);
        job.resolve(image);
      } catch (error) {
        job.reject(error);
      } finally {
        job.signal.removeEventListener('abort', job.cancel);
      }
    }
  } finally {
    rendering = false;
  }
}

export async function themePreviewImage(source: string, signal: AbortSignal): Promise<Blob> {
  const cached = await cachedPreview(source);
  if (signal.aborted) throw aborted();
  if (cached) return cached;
  return new Promise((resolve, reject) => {
    const job: PreviewJob = {
      source,
      signal,
      resolve,
      reject,
      cancel: () => {
        const index = jobs.indexOf(job);
        if (index >= 0) {
          jobs.splice(index, 1);
          reject(aborted());
        }
      },
    };
    signal.addEventListener('abort', job.cancel, { once: true });
    jobs.push(job);
    void renderQueue();
  });
}
