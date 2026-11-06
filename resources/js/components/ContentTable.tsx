import { useTranslation } from '../i18n';
import { Link, router, usePage } from '@inertiajs/react';
import { useState } from 'react';
import { hasCapability, type ContentItem, type SharedProps } from '../types';
import Icon from './Icon';
import ConfirmDialog from './ConfirmDialog';
import type { ContentTypeDefinition } from '../content';

export default function ContentTable({
  items,
  contentType,
  compact = false,
}: {
  items: ContentItem[];
  contentType?: ContentTypeDefinition;
  compact?: boolean;
}) {
  const { t } = useTranslation();
  const base = (item: ContentItem) =>
    item.adminBase || contentType?.adminBase || `/admin/collections/${item.content_type}`;
  const extraColumns = compact ? [] : contentType?.fields.filter((field) => field.inList) || [];
  const showCategory = !compact && Boolean(contentType?.features.includes('categories'));
  const { csrfToken, auth } = usePage<SharedProps>().props;
  const canPublish = hasCapability(auth?.admin.capabilities || [], 'publish');
  const [pending, setPending] = useState<ContentItem | null>(null);
  const [busy, setBusy] = useState(false);
  return (
    <>
      <div className="table-scroll">
        <table className={compact ? 'content-table content-table-compact' : 'content-table'}>
          <thead>
            <tr>
              <th>{contentType ? t(contentType.singular) : t('Content item')}</th>
              <th>{t('Status')}</th>
              {showCategory && <th>{t('Category')}</th>}
              {extraColumns.map((field) => (
                <th key={field.key}>{field.label}</th>
              ))}
              <th>{t('Last updated')}</th>
              <th>
                <span className="sr-only">{t('Actions')}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr key={item.id}>
                <td>
                  <div className="table-content">
                    {item.image ? (
                      <img src={item.image} alt="" loading="lazy" />
                    ) : (
                      <span className="table-image-placeholder" aria-hidden="true">
                        <Icon name="image" />
                      </span>
                    )}
                    <span>
                      <strong>
                        {item.status === 'trash' ? (
                          item.title
                        ) : (
                          <Link href={`${base(item)}/${item.id}/edit`}>{item.title}</Link>
                        )}
                      </strong>
                      <small>
                        {item.url || t('Private content')}
                        {item.featured && (
                          <span className="featured-text">
                            <Icon name="sparkles" /> {t('Featured')}
                          </span>
                        )}
                      </small>
                    </span>
                  </div>
                </td>
                <td>
                  <span className={`status ${item.status}`}>
                    {item.status === 'published'
                      ? t('Published')
                      : item.status === 'scheduled'
                        ? t('Scheduled')
                        : item.status === 'trash'
                          ? t('In trash')
                          : t('Draft')}
                  </span>
                </td>
                {showCategory && <td>{item.category}</td>}
                {extraColumns.map((field) => {
                  const value = item.fields?.[field.key];
                  const text =
                    value === null || value === undefined
                      ? '—'
                      : field.kind === 'boolean'
                        ? t(value ? 'Yes' : 'No')
                        : field.kind === 'select'
                          ? field.options.find((option) => option.value === value)?.label ||
                            String(value)
                          : String(value);
                  return <td key={field.key}>{text}</td>;
                })}
                <td className="table-date">{item.updatedLabel}</td>
                <td>
                  <div className="table-actions">
                    {item.status !== 'trash' && (
                      <Link
                        className="icon-button"
                        href={`${base(item)}/${item.id}/edit`}
                        aria-label={t('Edit {title}', { title: item.title })}
                      >
                        <Icon name="edit" />
                      </Link>
                    )}
                    {item.status === 'published' && item.url && (
                      <Link
                        className="icon-button"
                        href={item.url}
                        aria-label={t('Read {title}', { title: item.title })}
                      >
                        <Icon name="external" />
                      </Link>
                    )}
                    {(canPublish || item.status === 'draft' || item.status === 'trash') && (
                      <button
                        className="icon-button danger"
                        onClick={() => setPending(item)}
                        aria-label={t('Delete {title}', { title: item.title })}
                      >
                        <Icon name="trash" />
                      </button>
                    )}
                    {item.status === 'trash' && (
                      <button
                        className="button button-outline"
                        disabled={busy}
                        onClick={() =>
                          router.post(`${base(item)}/${item.id}/restore`, {
                            _token: csrfToken,
                          })
                        }
                      >
                        {t('Restore')}
                      </button>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ConfirmDialog
        open={pending !== null}
        message={
          pending?.status === 'trash'
            ? t('Delete this content permanently? This action cannot be undone.')
            : t('Move this content to the trash? You can restore it later.')
        }
        busy={busy}
        onCancel={() => setPending(null)}
        onConfirm={() => {
          if (!pending) return;
          router.post(
            `${base(pending)}/${pending.id}${pending.status === 'trash' ? '/permanent-delete' : '/trash'}`,
            { _token: csrfToken },
            {
              onStart: () => setBusy(true),
              onFinish: () => {
                setBusy(false);
                setPending(null);
              },
            },
          );
        }}
      />
    </>
  );
}
