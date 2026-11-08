// Reorders the columns in a content list's column settings: drag a row by
// its handle, or focus the handle and use the arrow keys (Home and End move
// a column to either end). The hidden `order` field carries the new order
// when the form is saved; screen readers hear where the column went.

const MOVED = 'Moved {column} to position {position} of {count}.';

export function mount(
  element: HTMLElement,
  _props: Record<string, never>,
  messages: Record<string, string>,
) {
  const list = element.querySelector<HTMLElement>('[data-column-list]');
  const order = element.querySelector<HTMLInputElement>('input[name="order"]');
  const status = element.querySelector<HTMLElement>('[data-column-status]');
  if (!list || !order) return;
  const columns = list;
  const field = order;

  function rows() {
    return Array.from(columns.querySelectorAll<HTMLElement>('[data-column-key]'));
  }

  function sync() {
    const current = rows();
    field.value = current.map((row) => row.dataset.columnKey ?? '').join(',');
    current.forEach((row, index) => {
      const visible = row.querySelector<HTMLInputElement>('input[type="checkbox"]');
      if (visible) visible.name = `visible_${index}`;
    });
  }

  function announce(row: HTMLElement) {
    if (!status) return;
    const current = rows();
    status.textContent = (messages[MOVED] || MOVED)
      .replace('{column}', row.dataset.columnLabel ?? '')
      .replace('{position}', String(current.indexOf(row) + 1))
      .replace('{count}', String(current.length));
  }

  function rowOf(target: EventTarget | null) {
    const handle = target instanceof Element ? target.closest('[data-column-handle]') : null;
    return handle ? handle.closest<HTMLElement>('[data-column-key]') : null;
  }

  function keydown(event: KeyboardEvent) {
    const row = rowOf(event.target);
    if (!row) return;
    const previous = row.previousElementSibling;
    const next = row.nextElementSibling;
    if (event.key === 'ArrowUp' && previous) columns.insertBefore(row, previous);
    else if (event.key === 'ArrowDown' && next) columns.insertBefore(next, row);
    else if (event.key === 'Home' && previous) columns.prepend(row);
    else if (event.key === 'End' && next) columns.append(row);
    else return;
    event.preventDefault();
    row.querySelector<HTMLElement>('[data-column-handle]')?.focus();
    sync();
    announce(row);
  }

  let dragging: HTMLElement | null = null;
  let pointer = -1;

  function pointerdown(event: PointerEvent) {
    const row = rowOf(event.target);
    if (!row || event.button !== 0) return;
    dragging = row;
    pointer = event.pointerId;
    (event.target as Element).setPointerCapture(event.pointerId);
    row.classList.add('dragging');
    columns.classList.add('is-sorting');
    event.preventDefault();
  }

  function pointermove(event: PointerEvent) {
    const row = dragging;
    if (!row || event.pointerId !== pointer) return;
    // The row goes before the first other row whose middle is below the pointer.
    const before = rows().find((other) => {
      if (other === row) return false;
      const box = other.getBoundingClientRect();
      return event.clientY < box.top + box.height / 2;
    });
    if (before) {
      if (row.nextElementSibling !== before) columns.insertBefore(row, before);
    } else if (columns.lastElementChild !== row) {
      columns.append(row);
    }
  }

  function pointerup(event: PointerEvent) {
    const row = dragging;
    if (!row || event.pointerId !== pointer) return;
    dragging = null;
    pointer = -1;
    row.classList.remove('dragging');
    columns.classList.remove('is-sorting');
    sync();
    announce(row);
  }

  columns.addEventListener('keydown', keydown);
  columns.addEventListener('pointerdown', pointerdown);
  columns.addEventListener('pointermove', pointermove);
  columns.addEventListener('pointerup', pointerup);
  columns.addEventListener('pointercancel', pointerup);
  sync();
  return () => {
    columns.removeEventListener('keydown', keydown);
    columns.removeEventListener('pointerdown', pointerdown);
    columns.removeEventListener('pointermove', pointermove);
    columns.removeEventListener('pointerup', pointerup);
    columns.removeEventListener('pointercancel', pointerup);
  };
}
