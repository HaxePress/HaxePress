// Shares the current page with the system share sheet, or copies its link.
export function mount(
  element: HTMLElement,
  props: { title: string; toast: boolean },
  messages: Record<string, string>,
) {
  const button = element.querySelector('button');
  if (!button) return;
  let status: HTMLElement | null = null;
  let timer = 0;
  function show(text: string) {
    if (!status) {
      // Themes show either a toast for the page or a status line next to the button.
      status = document.createElement(props.toast ? 'div' : 'p');
      if (props.toast) status.className = 'toast';
      status.setAttribute('role', 'status');
      status.setAttribute('aria-live', 'polite');
      (props.toast ? document.getElementById('main') || document.body : element).append(status);
    }
    status.textContent = text;
    window.clearTimeout(timer);
    timer = window.setTimeout(() => {
      status?.remove();
      status = null;
    }, 4000);
  }
  button.addEventListener('click', async () => {
    const url = window.location.href;
    try {
      if (navigator.share) await navigator.share({ title: props.title, url });
      else {
        await navigator.clipboard.writeText(url);
        show(messages['Link copied to clipboard.'] || 'Link copied to clipboard.');
      }
    } catch (error) {
      if (!(error instanceof Error) || error.name !== 'AbortError') {
        const template = messages['Copy this link: {url}'] || 'Copy this link: {url}';
        show(template.replace('{url}', url));
      }
    }
  });
}
