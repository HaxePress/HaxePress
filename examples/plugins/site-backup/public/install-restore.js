// Restores a HaxePress backup from the installation page. The upload goes in
// chunks; the server-rendered form shows the backup header and errors.
import { readBackupHeader, uploadBackup } from './backup.js';

export function mount(element, props) {
  const form = element.querySelector('form');
  const input = form?.querySelector('input[type="file"]');
  const submit = form?.querySelector('button[type="submit"]');
  const section = element.closest('.setup-content');
  if (!form || !input || !submit || !section) return;
  const version = form.querySelector('[data-backup-version]');
  const encrypted = form.querySelector('[data-backup-encrypted]');
  const appKey = form.querySelector('[data-backup-key]');
  const skip = form.querySelector('[data-skip-damaged]');
  const error = section.querySelector('[data-setup-error]');
  const label = submit.textContent || '';
  let busy = false;

  function showError(message) {
    const text = error?.querySelector('span');
    if (!error || !text) return;
    text.textContent = message;
    error.hidden = message === '';
  }

  function setBusy(value) {
    busy = value;
    section.setAttribute('aria-busy', String(value));
    for (const fieldset of section.querySelectorAll('fieldset')) fieldset.disabled = value;
    for (const button of section.querySelectorAll('form button')) {
      if (!button.closest('fieldset')) button.disabled = value;
    }
    submit.textContent = value ? 'Verifying and restoring…' : label;
    submit.disabled = value || !input.files?.length;
  }

  input.addEventListener('change', async () => {
    const file = input.files?.[0] || null;
    submit.disabled = !file || busy;
    for (const element of [version, encrypted, appKey]) if (element) element.hidden = true;
    if (!file) return;
    const header = await readBackupHeader(file).catch(() => null);
    if (!header || input.files?.[0] !== file) return;
    if (version) {
      version.textContent = `Backup created by HaxePress ${header.cmsVersion}`;
      version.hidden = false;
    }
    if (encrypted) encrypted.hidden = !header.encrypted;
    if (appKey) appKey.hidden = !header.encrypted;
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const backup = input.files?.[0];
    if (!backup || busy) return;
    if (!backup.size || backup.size > props.restoreLimit) {
      showError('Choose a backup within the upload size limit.');
      return;
    }
    setBusy(true);
    showError('');
    try {
      const options = new URLSearchParams();
      if (skip?.checked) options.set('skip_damaged_content', '1');
      if (props.useVerifiedDatabase) options.set('use_verified_database', '1');
      const result = await uploadBackup('/admin/install/restore', backup, props.csrfToken, options);
      if (!result.restored) throw new Error('The backup could not be restored.');
      if (result.skippedContent?.length) {
        showSkipped(section, result.skippedContent);
        return;
      }
      window.location.replace('/admin/login');
    } catch (failure) {
      showError(failure instanceof Error ? failure.message : 'The backup could not be restored.');
      setBusy(false);
    }
  });
}

/** The restored site skipped damaged content items: list them before signing in. */
function showSkipped(section, skipped) {
  const heading = document.createElement('div');
  heading.className = 'setup-page-heading';
  heading.setAttribute('role', 'status');
  const title = document.createElement('h1');
  title.textContent = 'Backup restored';
  const count = document.createElement('p');
  count.textContent = `Skipped ${skipped.length} damaged content ${skipped.length === 1 ? 'item' : 'items'}.`;
  const identifiers = document.createElement('p');
  const more = skipped.length > 25 ? ` and ${skipped.length - 25} more` : '';
  identifiers.textContent = `Content IDs ${skipped.slice(0, 25).join(', ')}${more}`;
  heading.append(title, count, identifiers);
  const link = document.createElement('a');
  link.className = 'button';
  link.href = '/admin/login';
  link.textContent = 'Continue to sign in';
  section.replaceChildren(heading, link);
  section.setAttribute('aria-busy', 'false');
}
