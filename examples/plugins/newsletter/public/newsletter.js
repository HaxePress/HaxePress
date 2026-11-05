export function activate({ slot, settings, t }) {
  const outlet = slot('site.before-footer');
  if (!outlet) return;
  const section = document.createElement('section');
  section.className = 'cms-newsletter wrap';
  section.id = 'newsletter';
  const copy = document.createElement('div');
  const title = document.createElement('h2');
  title.id = 'newsletter-heading';
  title.textContent = t(settings.title || 'Newsletter');
  section.setAttribute('aria-labelledby', title.id);
  copy.append(title);
  const form = document.createElement('form');
  form.action = '/subscribe';
  form.method = 'post';
  const inputLabel = document.createElement('label');
  inputLabel.className = 'sr-only';
  inputLabel.htmlFor = 'newsletter-email';
  inputLabel.textContent = t('Email address');
  const input = document.createElement('input');
  input.id = inputLabel.htmlFor;
  input.name = 'email';
  input.type = 'email';
  input.required = true;
  input.maxLength = 254;
  input.placeholder = t('Your email address');
  input.autocomplete = 'email';
  const button = document.createElement('button');
  button.className = 'button';
  button.type = 'submit';
  button.textContent = t('Subscribe');
  const status = document.createElement('p');
  status.className = 'cms-newsletter-status';
  status.setAttribute('aria-live', 'polite');
  const field = document.createElement('div');
  field.className = 'cms-newsletter-field';
  field.append(inputLabel, input, button);
  form.append(field, status);
  section.append(copy, form);
  outlet.append(section);
  if (window.location.hash === '#newsletter') section.scrollIntoView();
  const controller = new AbortController();
  async function subscribe(event) {
    event.preventDefault();
    button.disabled = true;
    status.textContent = t('Subscribing…');
    status.classList.remove('error');
    try {
      const response = await fetch(form.action, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({ email: input.value }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || t('Please try again in a moment.'));
      status.textContent = result.message;
      input.value = '';
    } catch (error) {
      if (!controller.signal.aborted) {
        status.classList.add('error');
        status.textContent = error instanceof Error ? t(error.message) : t('Could not subscribe.');
      }
    } finally {
      button.disabled = false;
    }
  }
  form.addEventListener('submit', subscribe);
  return () => {
    controller.abort();
    form.removeEventListener('submit', subscribe);
    section.remove();
  };
}
