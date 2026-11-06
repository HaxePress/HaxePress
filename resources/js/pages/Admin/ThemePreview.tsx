import { Link, router, useForm, usePage } from '@inertiajs/react';
import { useEffect, useRef, useState } from 'react';
import PageHead from '../../components/PageHead';
import Icon from '../../components/Icon';
import Alert from '../../components/Alert';
import PackageSettingField from '../../components/PackageSettingField';
import { useTranslation } from '../../i18n';
import { customizationMessages, type ThemeCustomization } from '../../themes/customization';
import { errorText, type SharedProps } from '../../types';

const viewports = [
  { id: 'desktop', label: 'Desktop', width: '100%' },
  { id: 'tablet', label: 'Tablet', width: '768px' },
  { id: 'mobile', label: 'Mobile', width: '390px' },
] as const;

export default function ThemePreview({
  preview,
  notice,
}: {
  preview: { id: string; name: string; url: string; customization?: ThemeCustomization | null };
  notice: string;
}) {
  const { t } = useTranslation(preview.id);
  const { csrfToken, errors } = usePage<SharedProps>().props;
  const [activating, setActivating] = useState(false);
  const [viewport, setViewport] = useState<(typeof viewports)[number]>(viewports[0]);
  const [customizing, setCustomizing] = useState(false);
  const [ready, setReady] = useState(false);
  const frame = useRef<HTMLIFrameElement>(null);
  const customization = preview.customization;
  const form = useForm<Record<string, string>>(customization?.values || {});
  const draft = useRef(form.data);
  const savedValues = JSON.stringify(customization?.values || {});
  const session = customization?.session;

  function sendValues(values: Record<string, string>) {
    if (!session) return;
    frame.current?.contentWindow?.postMessage(
      { type: customizationMessages.update, themeId: preview.id, session, values },
      location.origin,
    );
  }

  useEffect(() => {
    const values = JSON.parse(savedValues) as Record<string, string>;
    form.setDefaults(values);
    form.setData(values);
  }, [savedValues]);

  useEffect(() => {
    setReady(false);
    const receive = (event: MessageEvent) => {
      if (event.origin !== location.origin || event.source !== frame.current?.contentWindow) return;
      const message = event.data;
      if (
        message?.type !== customizationMessages.ready ||
        message.themeId !== preview.id ||
        message.session !== session
      )
        return;
      setReady(true);
      sendValues(draft.current);
    };
    window.addEventListener('message', receive);
    if (session) {
      frame.current?.contentWindow?.postMessage(
        { type: customizationMessages.request, themeId: preview.id, session },
        location.origin,
      );
    }
    return () => window.removeEventListener('message', receive);
  }, [preview.id, session]);

  useEffect(() => {
    draft.current = form.data;
    if (ready) sendValues(form.data);
  }, [form.data, ready, session]);

  return (
    <div className="theme-preview-shell">
      <PageHead title={t('Theme preview')} admin />
      <aside className="theme-preview-banner" aria-label={t('Theme preview')}>
        <span>
          {t('Previewing')} <strong>{t(preview.name)}</strong>
        </span>
        <div className="theme-preview-devices" role="group" aria-label={t('Preview size')}>
          {viewports.map((option) => (
            <button
              type="button"
              className="theme-preview-device"
              key={option.id}
              aria-pressed={viewport.id === option.id}
              onClick={() => setViewport(option)}
            >
              <Icon name={option.id} />
              <span>{t(option.label)}</span>
            </button>
          ))}
        </div>
        <div className="theme-preview-actions">
          {customization && (
            <button
              type="button"
              className="theme-preview-device"
              aria-expanded={customizing}
              aria-controls="theme-customizer-panel"
              onClick={() => setCustomizing((open) => !open)}
            >
              <Icon name="palette" />
              <span>{t('Customize')}</span>
            </button>
          )}
          <Link href="/admin/themes">{t('Back to themes')}</Link>
          <button
            className="button"
            disabled={activating || form.processing || form.isDirty}
            title={form.isDirty ? t('Save or discard changes before activating.') : undefined}
            onClick={() =>
              router.post(
                `/admin/themes/${preview.id}/enable`,
                { _token: csrfToken },
                { onStart: () => setActivating(true), onFinish: () => setActivating(false) },
              )
            }
          >
            {t('Activate theme')}
          </button>
        </div>
      </aside>
      <div
        className={`theme-preview-workspace${customizing && customization ? ' has-customizer' : ''}`}
      >
        {customizing && customization && (
          <aside
            id="theme-customizer-panel"
            className="theme-customizer-panel"
            aria-label={t('Theme customization')}
          >
            <form
              className="theme-customizer-form"
              onSubmit={(event) => {
                event.preventDefault();
                form.transform((values) => ({
                  ...values,
                  _context: 'preview',
                  _token: csrfToken || '',
                }));
                form.post(`/admin/themes/${preview.id}/settings`, { preserveScroll: true });
              }}
            >
              <header className="theme-customizer-heading">
                <div>
                  <h2>{t('Customize theme')}</h2>
                  <p>{t(preview.name)}</p>
                </div>
                <button
                  type="button"
                  className="icon-button"
                  aria-label={t('Close customization')}
                  onClick={() => setCustomizing(false)}
                >
                  <Icon name="x" />
                </button>
              </header>
              <div className="theme-customizer-messages">
                <Alert message={notice} />
                <Alert error message={errorText(form.errors) || errorText(errors.package)} />
              </div>
              <fieldset className="theme-customizer-fields" disabled={form.processing}>
                {customization.fields.map((field) => (
                  <PackageSettingField
                    key={field.key}
                    packageId={preview.id}
                    field={field}
                    value={form.data[field.key] || ''}
                    onChange={(value) => form.setData(field.key, value)}
                  />
                ))}
              </fieldset>
              <footer className="theme-customizer-footer">
                <p role="status">
                  {!ready
                    ? t('Loading preview…')
                    : form.isDirty
                      ? t('Unsaved changes')
                      : t('All changes saved')}
                </p>
                <button
                  type="submit"
                  className="button"
                  disabled={form.processing || !form.isDirty}
                >
                  {form.processing ? t('Saving…') : t('Save changes')}
                </button>
                <button
                  type="button"
                  className="button button-outline"
                  disabled={form.processing || !form.isDirty}
                  onClick={() => {
                    form.resetAndClearErrors();
                  }}
                >
                  {t('Discard changes')}
                </button>
              </footer>
            </form>
          </aside>
        )}
        <main className="theme-preview-viewport" data-device={viewport.id}>
          <div className="theme-preview-canvas" style={{ minWidth: viewport.width }}>
            <iframe
              ref={frame}
              className="theme-preview-frame"
              src={preview.url}
              title={t('{name} preview', { name: t(preview.name) })}
              style={{ width: viewport.width }}
              onLoad={() => {
                if (session)
                  frame.current?.contentWindow?.postMessage(
                    { type: customizationMessages.request, themeId: preview.id, session },
                    location.origin,
                  );
              }}
            />
          </div>
        </main>
      </div>
    </div>
  );
}
