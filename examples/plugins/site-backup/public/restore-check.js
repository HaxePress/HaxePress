// Uploads a backup in chunks and rehearses its restore without changing the
// site. The server renders the card; this module shows the file's header,
// the result and errors.
import { readBackupHeader, uploadBackup } from './backup.js';

export function mount(element, props, messages) {
  const t = (key, values = {}) =>
    (messages[key] || key).replace(/\{(\w+)\}/g, (match, name) =>
      name in values ? String(values[name]) : match,
    );
  const section = element.querySelector('[data-restore-check]');
  const form = section?.querySelector('form');
  const input = form?.querySelector('input[type="file"]');
  const submit = form?.querySelector('button[type="submit"]');
  if (!section || !form || !input || !submit) return;
  const error = section.querySelector('[data-restore-error]');
  const version = section.querySelector('[data-backup-version]');
  const encrypted = section.querySelector('[data-backup-encrypted]');
  const passed = section.querySelector('[data-restore-passed]');
  const checksum = section.querySelector('[data-restore-checksum]');
  let busy = false;

  function showError(message) {
    const text = error?.querySelector('span');
    if (!error || !text) return;
    text.textContent = message ? t(message) : '';
    error.hidden = !message;
  }

  function showResult(md5) {
    if (passed) passed.hidden = !md5;
    if (checksum) {
      checksum.querySelector('code').textContent = md5 ? `MD5 ${md5}` : '';
      checksum.hidden = !md5;
    }
  }

  function setBusy(value) {
    busy = value;
    section.setAttribute('aria-busy', String(value));
    input.disabled = value;
    submit.disabled = value || !input.files?.length;
    submit.textContent = t(value ? 'Verifying backup…' : 'Verify backup');
  }

  input.addEventListener('change', async () => {
    const file = input.files?.[0] || null;
    showError('');
    showResult('');
    submit.disabled = !file || busy;
    if (version) version.hidden = true;
    if (encrypted) encrypted.hidden = true;
    if (!file) return;
    const header = await readBackupHeader(file).catch(() => null);
    if (!header || input.files?.[0] !== file) return;
    if (version) {
      version.textContent = t('Backup created by HaxePress {version}', {
        version: header.cmsVersion,
      });
      version.hidden = false;
    }
    if (encrypted) encrypted.hidden = !header.encrypted;
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const file = input.files?.[0];
    if (!file || busy) return;
    showResult('');
    if (!file.size || file.size > props.uploadLimit) {
      showError('Choose a backup within the upload size limit.');
      return;
    }
    showError('');
    setBusy(true);
    try {
      const result = await uploadBackup('/admin/backups/verify', file, props.csrfToken);
      if (!result.verified) throw new Error('The backup could not be verified.');
      showResult(result.md5);
    } catch (failure) {
      showError(failure instanceof Error ? failure.message : 'The backup could not be verified.');
    } finally {
      setBusy(false);
    }
  });
}
