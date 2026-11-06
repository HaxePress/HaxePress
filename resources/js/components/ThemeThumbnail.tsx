import { Link, usePage } from '@inertiajs/react';
import { useEffect, useRef, useState } from 'react';
import { useTranslation } from '../i18n';
import { themePreviewImage } from '../themes/thumbnail-cache';
import type { SharedProps } from '../types';
import Icon from './Icon';

export default function ThemeThumbnail({
  id,
  name,
  revision,
}: {
  id: string;
  name: string;
  revision: string;
}) {
  const { t, locale } = useTranslation();
  const page = usePage<SharedProps & { themePreviewRevision: string }>();
  const viewport = useRef<HTMLDivElement>(null);
  const [image, setImage] = useState<string | null>(null);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const preview = `/admin/themes/${id}/preview`;
  const parameters = new URLSearchParams({
    revision,
    lang: locale,
    snapshot: page.props.themePreviewRevision,
    assets: page.version || '',
    actor: String(page.props.auth?.admin?.id || ''),
  });
  const source = `${preview}/frame?${parameters}`;

  useEffect(() => {
    const element = viewport.current;
    if (!element) return;
    const controller = new AbortController();
    let imageUrl: string | null = null;
    setImage(null);
    setStatus('loading');
    async function load() {
      try {
        const captured = await themePreviewImage(source, controller.signal);
        if (controller.signal.aborted) return;
        imageUrl = URL.createObjectURL(captured);
        setImage(imageUrl);
        setStatus('ready');
      } catch {
        if (!controller.signal.aborted) setStatus('error');
      }
    }
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          observer.disconnect();
          void load();
        }
      },
      { rootMargin: '200px' },
    );
    observer.observe(element);
    return () => {
      observer.disconnect();
      controller.abort();
      if (imageUrl) URL.revokeObjectURL(imageUrl);
    };
  }, [source]);

  return (
    <Link className="theme-thumbnail" href={preview} aria-label={t('Preview {name}', { name })}>
      <div
        ref={viewport}
        className="theme-thumbnail-viewport"
        data-theme-preview={id}
        data-preview-state={status}
      >
        {image ? (
          <img src={image} width={1280} height={800} alt="" loading="lazy" aria-hidden="true" />
        ) : (
          <span className="theme-thumbnail-status" role="status">
            {status === 'error' ? t('Preview unavailable') : t('Loading preview…')}
          </span>
        )}
      </div>
      <span className="theme-thumbnail-open" aria-hidden="true">
        <Icon name="eye" /> {t('Preview')}
      </span>
    </Link>
  );
}
