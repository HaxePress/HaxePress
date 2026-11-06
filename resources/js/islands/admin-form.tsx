// Enhances a server-rendered admin form, which also works without it:
// - `data-show-when="select-id=value"` shows an element, and enables its
//   fields, while the select has that value;
// - `.content-picker[data-picker-url]` loads its options from that address
//   when it is shown and while its search field is typed in;
// - `input[data-slug-from="source-id"]` follows the source field until it is
//   edited, and `[data-slug-preview="slug-id"]` shows the resulting path;
// - `[data-describes="select-id"]` shows the `data-text-<value>` text of the
//   selected value, or `data-text`.

type Message = string | { one: string; other: string };
type Catalogue = Record<string, Message>;

const catalogues = new Map<string, Promise<Catalogue>>();

/** The CMS catalogue, loaded once and only when option names need translating. */
function catalogue(url: string): Promise<Catalogue> {
  let pending = catalogues.get(url);
  if (!pending) {
    pending = fetch(url, { credentials: 'same-origin' })
      .then((response) => (response.ok ? response.json() : {}))
      .catch(() => ({}));
    catalogues.set(url, pending);
  }
  return pending;
}

function translate(messages: Catalogue, key: string): string {
  const message = Object.hasOwn(messages, key) ? messages[key] : key;
  return typeof message === 'string' ? message : message.other;
}

function condition(element: HTMLElement): [string, string] {
  const rule = element.dataset.showWhen || '';
  const separator = rule.indexOf('=');
  return [rule.slice(0, separator), rule.slice(separator + 1)];
}

function fieldsOf(element: HTMLElement): HTMLInputElement[] {
  const selector = 'input, select, textarea';
  const nested = Array.from(element.querySelectorAll<HTMLInputElement>(selector));
  return element.matches(selector) ? [element as HTMLInputElement] : nested;
}

function dependentFields(root: HTMLElement, shown: (element: HTMLElement) => void) {
  const groups = new Map<HTMLSelectElement, HTMLElement[]>();
  for (const element of root.querySelectorAll<HTMLElement>('[data-show-when]')) {
    const [id] = condition(element);
    const select = document.getElementById(id);
    if (!(select instanceof HTMLSelectElement)) continue;
    groups.set(select, [...(groups.get(select) || []), element]);
  }
  for (const [select, elements] of groups) {
    const update = () => {
      for (const element of elements) {
        const [, value] = condition(element);
        const visible = select.value === value;
        element.hidden = !visible;
        for (const field of fieldsOf(element)) field.disabled = !visible;
        if (visible) shown(element);
      }
    };
    select.addEventListener('change', update);
    update();
  }
}

/** Returns a function that loads the first options when the picker is first shown. */
function picker(container: HTMLElement, translations: string): () => void {
  const search = container.querySelector<HTMLInputElement>('input[type="search"]');
  const select = container.querySelector('select');
  const address = container.dataset.pickerUrl;
  if (!search || !select || !address) return () => {};
  const itemsKey = container.dataset.pickerItems || 'items';
  const valueKey = container.dataset.pickerValue || 'id';
  const labelKey = container.dataset.pickerLabel || 'name';
  const translated = container.hasAttribute('data-picker-translate');
  let timer = 0;
  let pending: AbortController | null = null;
  let loaded = false;
  let alert: HTMLElement | null = null;

  function showError(message: string) {
    if (!alert) {
      alert = document.createElement('p');
      alert.className = 'field-help';
      alert.setAttribute('role', 'alert');
      container.append(alert);
    }
    alert.textContent = message;
  }

  async function load() {
    pending?.abort();
    const controller = new AbortController();
    pending = controller;
    const url = new URL(address!, window.location.href);
    url.searchParams.set('q', search!.value);
    url.searchParams.set('selected', select!.value);
    try {
      const response = await fetch(url, {
        credentials: 'same-origin',
        headers: { Accept: 'application/json' },
        signal: controller.signal,
      });
      if (!response.ok) throw new Error('The options could not be loaded.');
      const data = await response.json();
      const rows: Record<string, unknown>[] = Array.isArray(data[itemsKey]) ? data[itemsKey] : [];
      const messages = translated ? await catalogue(translations) : null;
      if (controller.signal.aborted) return;
      const selected = select!.value;
      const options = rows.map((row) => {
        const option = document.createElement('option');
        const label = String(row[labelKey] ?? '');
        option.value = String(row[valueKey] ?? '');
        option.textContent = messages ? translate(messages, label) : label;
        return option;
      });
      const placeholder = select!.options[0];
      select!.replaceChildren(...(placeholder ? [placeholder] : []), ...options);
      select!.value = selected;
      if (select!.selectedIndex < 0) select!.selectedIndex = 0;
      alert?.remove();
      alert = null;
    } catch {
      if (!controller.signal.aborted) showError(container.dataset.pickerError || '');
    }
  }

  search.addEventListener('input', () => {
    window.clearTimeout(timer);
    timer = window.setTimeout(() => void load(), 200);
  });
  return () => {
    if (loaded) return;
    loaded = true;
    void load();
  };
}

function slugify(text: string): string {
  return text
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

function slugs(root: HTMLElement) {
  for (const slug of root.querySelectorAll<HTMLInputElement>('input[data-slug-from]')) {
    const source = document.getElementById(slug.dataset.slugFrom || '');
    if (!(source instanceof HTMLInputElement)) continue;
    const previews = root.querySelectorAll<HTMLElement>(
      `[data-slug-preview="${CSS.escape(slug.id)}"]`,
    );
    let custom = slug.value !== '';
    const preview = () => {
      for (const element of previews) {
        const prefix = element.dataset.slugPrefix || '';
        const path = slug.value || element.dataset.slugEmpty || '';
        element.textContent = `${prefix}${path}`;
      }
    };
    source.addEventListener('input', () => {
      if (custom) return;
      slug.value = slugify(source.value);
      preview();
    });
    slug.addEventListener('input', () => {
      custom = true;
      preview();
    });
  }
}

function descriptions(root: HTMLElement) {
  for (const help of root.querySelectorAll<HTMLElement>('[data-describes]')) {
    const select = document.getElementById(help.dataset.describes || '');
    if (!(select instanceof HTMLSelectElement)) continue;
    select.addEventListener('change', () => {
      const value = select.value;
      const key = `text${value.charAt(0).toUpperCase()}${value.slice(1)}`;
      help.textContent = help.dataset[key] ?? help.dataset.text ?? '';
    });
  }
}

export function mount(element: HTMLElement, props: { translations: string }) {
  const pickers = new Map<HTMLElement, () => void>();
  for (const container of element.querySelectorAll<HTMLElement>(
    '.content-picker[data-picker-url]',
  )) {
    pickers.set(container, picker(container, props.translations));
  }
  dependentFields(element, (shown) => pickers.get(shown)?.());
  for (const [container, activate] of pickers) {
    if (!container.hidden) activate();
  }
  slugs(element);
  descriptions(element);
}
