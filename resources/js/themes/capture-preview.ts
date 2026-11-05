import { useEffect } from 'react';

const viewportWidth = 1280;
const viewportHeight = 800;

async function waitForStylesheet(source: string): Promise<void> {
  const href = new URL(source, location.href).href;
  const loaded = () =>
    Array.from(document.styleSheets).some((sheet) => {
      if (sheet.href !== href) return false;
      try {
        return sheet.cssRules.length > 0;
      } catch {
        return false;
      }
    });
  if (loaded()) return;
  await new Promise<void>((resolve, reject) => {
    const finish = (error?: Error) => {
      clearTimeout(timeout);
      observer.disconnect();
      document.removeEventListener('load', check, true);
      if (error) reject(error);
      else resolve();
    };
    const check = () => {
      if (loaded()) finish();
    };
    const observer = new MutationObserver(check);
    const timeout = window.setTimeout(
      () => finish(new Error('Theme stylesheet timed out.')),
      10000,
    );
    observer.observe(document.head, { childList: true, subtree: true });
    document.addEventListener('load', check, true);
    check();
  });
}

/** Run in the temporary preview frame so renderer resources die with that frame. */
async function captureThemePreview(stylesheet?: string): Promise<void> {
  const captureId = new URLSearchParams(location.search).get('thumbnailCapture');
  if (
    !captureId ||
    window.parent === window ||
    !window.frameElement?.classList.contains('theme-thumbnail-capture-frame')
  ) {
    return;
  }
  try {
    if (!document.querySelector('[data-cms-site]')) throw new Error('Preview unavailable.');
    if (stylesheet) await waitForStylesheet(stylesheet);
    if (document.readyState !== 'complete') {
      await new Promise<void>((resolve) =>
        window.addEventListener('load', () => resolve(), { once: true }),
      );
    }
    await document.fonts.ready;
    const visibleImages = Array.from(document.images).filter((image) => {
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
    const image = await toBlob(document.body, {
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
        width: viewportWidth + 'px',
        height: viewportHeight + 'px',
        overflow: 'hidden',
      },
    });
    if (!image || image.type !== 'image/png') throw new Error('Preview capture failed.');
    window.parent.postMessage(
      { type: 'haxepress:theme-preview', captureId, image },
      location.origin,
    );
  } catch {
    window.parent.postMessage(
      { type: 'haxepress:theme-preview', captureId, error: true },
      location.origin,
    );
  }
}
/** Mount after the page so capture starts after React and Inertia Head have committed. */
export function ThemePreviewCapture({ stylesheet }: { stylesheet?: string }) {
  useEffect(() => {
    if (!new URLSearchParams(location.search).has('thumbnailCapture')) return;
    const capture = () => void captureThemePreview(stylesheet);
    if ('requestIdleCallback' in window) {
      const task = window.requestIdleCallback(capture, { timeout: 2000 });
      return () => window.cancelIdleCallback(task);
    }
    const task = setTimeout(capture, 0);
    return () => clearTimeout(task);
  }, [stylesheet]);
  return null;
}
