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

const viewportWidth = 1280;
const viewportHeight = 800;

/**
 * Captures the first screen of a loaded, same-origin preview frame. The frame's
 * load event has already waited for its stylesheets and images; fonts and
 * lazily loaded images in view are awaited here.
 */
async function captureDocument(page: Document): Promise<Blob> {
  if (!page.querySelector('[data-cms-site]')) throw new Error('Theme preview is unavailable.');
  await page.fonts.ready;
  const visibleImages = Array.from(page.images).filter((image) => {
    const bounds = image.getBoundingClientRect();
    return bounds.top < viewportHeight && bounds.bottom > 0;
  });
  await Promise.all(
    visibleImages.map(async (image) => {
      image.loading = 'eager';
      await image.decode().catch(() => undefined);
    }),
  );
  const { toBlob } = await import('html-to-image');
  const image = await toBlob(page.body, {
    width: viewportWidth,
    height: viewportHeight,
    canvasWidth: viewportWidth,
    canvasHeight: viewportHeight,
    pixelRatio: 1,
    includeQueryParams: true,
    fetchRequestInit: { credentials: 'same-origin' },
    filter: (node) => !['SCRIPT', 'NOSCRIPT', 'IFRAME'].includes(node.nodeName),
    style: {
      margin: '0',
      width: `${viewportWidth}px`,
      height: `${viewportHeight}px`,
      overflow: 'hidden',
    },
  });
  if (!image || image.type !== 'image/png' || image.size === 0) {
    throw new Error('Theme preview could not be captured.');
  }
  return image;
}

/** Renders one preview in a temporary frame, which is removed as soon as its PNG is ready. */
function capturePreview(source: string, signal: AbortSignal): Promise<Blob> {
  return new Promise((resolve, reject) => {
    if (signal.aborted) {
      reject(aborted());
      return;
    }
    const frame = document.createElement('iframe');
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
      frame.remove();
      if (image) resolve(image);
      else reject(error);
    };
    const cancel = () => finish(undefined, aborted());
    const timeout = window.setTimeout(
      () => finish(undefined, new Error('Theme preview timed out.')),
      captureTimeout,
    );
    signal.addEventListener('abort', cancel, { once: true });
    frame.addEventListener('error', () =>
      finish(undefined, new Error('Theme preview could not be loaded.')),
    );
    frame.addEventListener(
      'load',
      () => {
        const page = frame.contentDocument;
        if (!page) {
          finish(undefined, new Error('Theme preview is unavailable.'));
          return;
        }
        captureDocument(page).then(
          (image) => finish(image),
          (error: unknown) => finish(undefined, error),
        );
      },
      { once: true },
    );
    frame.src = new URL(source, location.origin).href;
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
