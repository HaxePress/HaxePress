// Replaces the loading state of a theme card with a captured preview image.
import { themePreviewImage } from '../themes/thumbnail-cache';

export function mount(
  element: HTMLElement,
  props: { source: string },
  messages: Record<string, string>,
) {
  const viewport = element.querySelector<HTMLElement>('.theme-thumbnail-viewport');
  if (!viewport) return;
  const controller = new AbortController();
  let imageUrl: string | null = null;

  async function load(target: HTMLElement) {
    try {
      const captured = await themePreviewImage(props.source, controller.signal);
      if (controller.signal.aborted) return;
      imageUrl = URL.createObjectURL(captured);
      const image = document.createElement('img');
      image.src = imageUrl;
      image.width = 1280;
      image.height = 800;
      image.alt = '';
      image.loading = 'lazy';
      image.setAttribute('aria-hidden', 'true');
      target.replaceChildren(image);
      target.dataset.previewState = 'ready';
    } catch {
      if (controller.signal.aborted) return;
      const status = target.querySelector('.theme-thumbnail-status');
      if (status) status.textContent = messages['Preview unavailable'] || 'Preview unavailable';
      target.dataset.previewState = 'error';
    }
  }

  const observer = new IntersectionObserver(
    (entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        observer.disconnect();
        void load(viewport);
      }
    },
    { rootMargin: '200px' },
  );
  observer.observe(viewport);
  return () => {
    observer.disconnect();
    controller.abort();
    if (imageUrl) URL.revokeObjectURL(imageUrl);
  };
}
