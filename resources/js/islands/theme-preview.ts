// The theme preview page: device sizes, the customizer panel and live
// customization. Unsaved values travel to the server-rendered preview frame
// in its `preview_settings` query; the frame's new page replaces the old one
// in place, so the preview keeps its scroll position and does not flash.
import { enhancePackageFields, packageFieldValues, setPackageField } from '../package-fields';

interface ThemePreviewProps {
  saved: Record<string, string>;
}

type Messages = Record<string, string>;

const draftParameter = 'preview_settings';

function sameValues(left: Record<string, string>, right: Record<string, string>): boolean {
  return Object.keys(right).every((key) => left[key] === right[key]);
}

/** Changed values the preview can show; the server ignores values over 2000 characters. */
function changes(values: Record<string, string>, saved: Record<string, string>) {
  const draft: Record<string, string> = {};
  for (const key of Object.keys(saved)) {
    const value = values[key];
    if (value !== saved[key] && value.length <= 2000) draft[key] = value;
  }
  return draft;
}

function viewports(element: HTMLElement, frame: HTMLIFrameElement | null) {
  const buttons = Array.from(element.querySelectorAll<HTMLButtonElement>('[data-viewport]'));
  const viewport = element.querySelector<HTMLElement>('.theme-preview-viewport');
  const canvas = element.querySelector<HTMLElement>('.theme-preview-canvas');
  for (const button of buttons) {
    button.addEventListener('click', () => {
      const width = button.dataset.width || '100%';
      for (const other of buttons) other.setAttribute('aria-pressed', String(other === button));
      if (viewport) viewport.dataset.device = button.dataset.viewport;
      if (canvas) canvas.style.minWidth = width;
      if (frame) frame.style.width = width;
    });
  }
}

/** Loads the frame's current page with the draft and puts it in place of the old one. */
async function refresh(frame: HTMLIFrameElement, draft: Record<string, string>) {
  const view = frame.contentWindow;
  const document = frame.contentDocument;
  if (!view || !document) return;
  const target = new URL(view.location.href);
  if (Object.keys(draft).length) target.searchParams.set(draftParameter, JSON.stringify(draft));
  else target.searchParams.delete(draftParameter);
  try {
    const response = await fetch(target, {
      credentials: 'same-origin',
      headers: { Accept: 'text/html' },
    });
    const type = response.headers.get('Content-Type') || '';
    // A missing page is a page too: the preview shows the theme's own not-found design.
    if (!type.includes('text/html')) throw new Error(response.statusText);
    const page = new DOMParser().parseFromString(await response.text(), 'text/html');
    if (frame.contentDocument !== document) return;
    const scroll = view.scrollY;
    document.head.replaceWith(document.adoptNode(page.head));
    document.body.replaceWith(document.adoptNode(page.body));
    view.history.replaceState(view.history.state, '', target.href);
    view.scrollTo(0, scroll);
    const runtime = (view as Window & { Wellout?: { mountIslands(root: ParentNode): void } })
      .Wellout;
    runtime?.mountIslands(document);
  } catch {
    view.location.replace(target.href);
  }
}

export function mount(element: HTMLElement, props: ThemePreviewProps, messages: Messages) {
  const text = (key: string) => messages[key] || key;
  const frame = element.querySelector<HTMLIFrameElement>('.theme-preview-frame');
  const workspace = element.querySelector<HTMLElement>('.theme-preview-workspace');
  const panel = element.querySelector<HTMLElement>('#theme-customizer-panel');
  const toggle = element.querySelector<HTMLButtonElement>('[data-customizer-toggle]');
  const form = element.querySelector<HTMLFormElement>('[data-theme-customizer]');
  const status = element.querySelector<HTMLElement>('[data-customizer-status]');
  const save = element.querySelector<HTMLButtonElement>('[data-customizer-save]');
  const discard = element.querySelector<HTMLButtonElement>('[data-customizer-discard]');
  const activate = element.querySelector<HTMLButtonElement>('[data-theme-activate]');
  const keys = Object.keys(props.saved);
  let ready = false;
  let shown: Record<string, string> = {};
  let timer = 0;

  viewports(element, frame);

  function open(visible: boolean) {
    if (!panel) return;
    panel.hidden = !visible;
    workspace?.classList.toggle('has-customizer', visible);
    toggle?.setAttribute('aria-expanded', String(visible));
  }
  toggle?.addEventListener('click', () => open(Boolean(panel?.hidden)));
  element.querySelector('[data-customizer-close]')?.addEventListener('click', () => open(false));

  function values() {
    return form ? packageFieldValues(form, keys) : props.saved;
  }

  function update() {
    const dirty = !sameValues(values(), props.saved);
    if (status) {
      status.textContent = !ready
        ? text('Loading preview…')
        : dirty
          ? text('Unsaved changes')
          : text('All changes saved');
    }
    if (save) save.disabled = !dirty;
    if (discard) discard.disabled = !dirty;
    if (activate) {
      activate.disabled = dirty;
      if (dirty) activate.title = text('Save or discard changes before activating.');
      else activate.removeAttribute('title');
    }
  }

  function preview() {
    window.clearTimeout(timer);
    timer = window.setTimeout(() => {
      const draft = changes(values(), props.saved);
      if (!frame || !ready || JSON.stringify(draft) === JSON.stringify(shown)) return;
      shown = draft;
      void refresh(frame, draft);
    }, 250);
  }

  if (form) {
    enhancePackageFields(form);
    form.addEventListener('input', () => {
      update();
      preview();
    });
    form.addEventListener('change', () => {
      update();
      preview();
    });
    discard?.addEventListener('click', () => {
      for (const key of keys) setPackageField(form, key, props.saved[key]);
      update();
      preview();
    });
  }

  function loaded() {
    const view = frame?.contentWindow;
    if (!view) return;
    ready = true;
    const query = new URL(view.location.href).searchParams.get(draftParameter);
    try {
      shown = query ? JSON.parse(query) : {};
    } catch {
      shown = {};
    }
    update();
    preview();
  }
  frame?.addEventListener('load', loaded);
  if (
    frame?.contentDocument?.readyState === 'complete' &&
    frame.contentWindow?.location.href !== 'about:blank'
  ) {
    loaded();
  }
  update();
}
