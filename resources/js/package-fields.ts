// Keeps the server-rendered package setting controls (PackageSettingField)
// in step: the optional color toggle enables its inputs, and the color
// picker and its hex text field follow each other. The hex field carries
// the submitted value; changes are reported with an `input` event on it.

const hexColor = /^#[0-9a-f]{6}$/i;

function changed(field: HTMLInputElement) {
  field.dispatchEvent(new Event('input', { bubbles: true }));
}

function colorControl(setting: HTMLElement) {
  const picker = setting.querySelector<HTMLInputElement>('[data-color-picker]');
  const text = setting.querySelector<HTMLInputElement>('[data-color-text]');
  const toggle = setting.querySelector<HTMLInputElement>('[data-color-toggle]');
  if (!picker || !text) return;
  picker.addEventListener('input', () => {
    text.value = picker.value;
    changed(text);
  });
  text.addEventListener('input', () => {
    if (hexColor.test(text.value)) picker.value = text.value;
  });
  toggle?.addEventListener('change', () => {
    picker.disabled = !toggle.checked;
    text.disabled = !toggle.checked;
    text.value = toggle.checked ? picker.value : '';
    changed(text);
  });
}

/** Sets a setting's controls to a value, as if the author had chosen it. */
export function setPackageField(form: HTMLFormElement, key: string, value: string) {
  const fields = Array.from(form.elements).filter(
    (element): element is HTMLInputElement =>
      element instanceof HTMLElement && (element as HTMLInputElement).name === key,
  );
  for (const field of fields) {
    if (field.type === 'hidden') continue;
    if (field.type === 'checkbox') field.checked = value === field.value;
    else field.value = value;
    if (field.matches('[data-color-text]')) {
      const setting = field.closest<HTMLElement>('.extension-setting');
      const picker = setting?.querySelector<HTMLInputElement>('[data-color-picker]');
      const toggle = setting?.querySelector<HTMLInputElement>('[data-color-toggle]');
      const enabled = value !== '' || !toggle;
      if (toggle) toggle.checked = enabled;
      field.disabled = !enabled;
      if (picker) {
        picker.disabled = !enabled;
        if (hexColor.test(value)) picker.value = value;
      }
    }
  }
}

/** The values the form would submit for these setting keys; disabled fields send "". */
export function packageFieldValues(form: HTMLFormElement, keys: string[]): Record<string, string> {
  const data = new FormData(form);
  const values: Record<string, string> = {};
  for (const key of keys) {
    const entries = data.getAll(key);
    const last = entries[entries.length - 1];
    values[key] = typeof last === 'string' ? last : '';
  }
  return values;
}

export function enhancePackageFields(root: ParentNode) {
  for (const setting of root.querySelectorAll<HTMLElement>('.extension-setting')) {
    colorControl(setting);
  }
}
