// Sends each `datetime-local` field of its form marked `data-epoch-field="name"`
// as epoch milliseconds in the hidden field `name`, using the browser's time zone.
export function mount(element: HTMLElement) {
  const form = element.closest('form');
  if (!form) return;
  const update = () => {
    for (const input of form.querySelectorAll<HTMLInputElement>('input[data-epoch-field]')) {
      const target = form.elements.namedItem(input.dataset.epochField || '');
      if (!(target instanceof HTMLInputElement)) continue;
      const epoch = input.value ? new Date(input.value).getTime() : NaN;
      target.value = Number.isFinite(epoch) ? String(epoch) : '';
    }
  };
  form.addEventListener('submit', update);
  return () => form.removeEventListener('submit', update);
}
