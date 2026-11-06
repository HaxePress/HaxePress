/**
 * Submits a real POST form with the given fields, so the browser follows the
 * handler's redirect like any other form submission.
 */
export function postForm(action: string, fields: Record<string, string>) {
  const form = document.createElement('form');
  form.method = 'post';
  form.action = action;
  form.hidden = true;
  for (const [name, value] of Object.entries(fields)) {
    const input = document.createElement('input');
    input.type = 'hidden';
    input.name = name;
    input.value = value;
    form.append(input);
  }
  document.body.append(form);
  form.submit();
}
