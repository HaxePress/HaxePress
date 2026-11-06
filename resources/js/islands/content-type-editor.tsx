// Live behaviour of the server-rendered collection editor form, which also works
// without it: the public address follows the key of a new collection, the
// address preview and field legends follow their inputs, choices show for
// choice fields, and list and filter options apply only where they can.

const unlistedKinds = ['textarea', 'image'];

interface ContentTypeEditorProps {
  siteUrl: string;
  creating: boolean;
}

function fieldControl(fieldset: Element, index: string, name: string) {
  return fieldset.querySelector<HTMLInputElement>(`[name="field_${index}_${name}"]`);
}

/** Enables the list and filter options a field's type and visibility allow. */
function updateField(fieldset: Element, index: string) {
  const kind = fieldControl(fieldset, index, 'kind')?.value || 'text';
  const scalar = !unlistedKinds.includes(kind);
  const choices = fieldset.querySelector<HTMLElement>('[data-field-choices]');
  if (choices) choices.hidden = kind !== 'select';
  const inList = fieldControl(fieldset, index, 'inList');
  if (inList) {
    inList.disabled = !scalar;
    if (!scalar) inList.checked = false;
  }
  const publicVisible = fieldControl(fieldset, index, 'publicVisible');
  const filterable = fieldControl(fieldset, index, 'filterable');
  if (filterable) {
    const allowed = scalar && Boolean(publicVisible?.checked);
    filterable.disabled = !allowed;
    if (!allowed) filterable.checked = false;
  }
}

export function mount(
  element: HTMLElement,
  props: ContentTypeEditorProps,
  messages: Record<string, string>,
) {
  const form = element.closest('form');
  if (!form) return;
  const key = form.querySelector<HTMLInputElement>('#type-key');
  const publicPath = form.querySelector<HTMLInputElement>('#type-public-path');
  const preview = form.querySelector<HTMLElement>('[data-public-url]');
  let generatedPath = (key?.value || '').replaceAll('_', '-');

  function showAddress() {
    if (preview && publicPath) preview.textContent = `${props.siteUrl}/${publicPath.value}/{slug}`;
  }

  form.addEventListener('input', (event) => {
    const target = event.target;
    if (!(target instanceof HTMLInputElement)) return;
    if (target === key && props.creating && publicPath) {
      const path = target.value.replaceAll('_', '-');
      if (!publicPath.value || publicPath.value === generatedPath) {
        publicPath.value = path;
        showAddress();
      }
      generatedPath = path;
      return;
    }
    if (target === publicPath) {
      showAddress();
      return;
    }
    if (/^field_\d+_label$/.test(target.name)) {
      const legend = target.closest('fieldset')?.querySelector('legend');
      const text = legend?.firstChild;
      if (text && text.nodeType === Node.TEXT_NODE) {
        text.textContent = `${target.value || messages['New field'] || 'New field'} `;
      }
    }
  });

  form.addEventListener('change', (event) => {
    const target = event.target;
    if (!(target instanceof HTMLInputElement || target instanceof HTMLSelectElement)) return;
    const match = /^field_(\d+)_(kind|publicVisible)$/.exec(target.name);
    const fieldset = target.closest('fieldset');
    if (match && fieldset) updateField(fieldset, match[1]);
  });
}
