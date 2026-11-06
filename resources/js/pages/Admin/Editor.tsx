import { useTranslation } from '../../i18n';
import { Link, router, useForm, usePage } from '@inertiajs/react';
import {
  useDeferredValue,
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
  type ReactNode,
} from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Alert from '../../components/Alert';
import Markdown, { allowedImage } from '../../components/Markdown';
import Icon from '../../components/Icon';
import CategoryInput from '../../components/CategoryInput';
import TagPicker from '../../components/TagPicker';
import MediaPicker from '../../components/MediaPicker';
import RevisionHistory from '../../components/RevisionHistory';
import useWorkingCopy from '../../components/useWorkingCopy';
import CustomFieldsEditor from '../../components/CustomFieldsEditor';
import FieldValues from '../../components/FieldValues';
import { collectionLabel, readCustomFields, type ContentTypeDefinition } from '../../content';
import { uploadManagedImage } from '../../media';
import { errorText, type ContentItem, type SharedProps, type Tag } from '../../types';

type UploadTarget = 'content' | 'cover';
interface EditorValues {
  id: string;
  title: string;
  slug: string;
  excerpt: string;
  content: string;
  category: string;
  image: string;
  image_alt: string;
  status: ContentItem['status'];
  featured: boolean;
  published_at: string;
  tags: string;
  version: string;
  draft_key: string;
  stay: string;
  seo_title: string;
  seo_description: string;
  scheduled_epoch: string;
  custom_fields: string;
}
interface WorkingCopy {
  key: string;
  data: Partial<EditorValues> & { tagRecords?: Tag[] };
  baseVersion: number;
  version: number;
  updatedAt: string;
}
function localTime(epoch: string) {
  const value = Number(epoch);
  if (!Number.isFinite(value) || value <= 0) return '';
  const date = new Date(value);
  return new Date(value - date.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
}

export default function Editor({
  item,
  isNew,
  hasCategories,
  contentType,
  draftKey = '',
  workingCopy = null,
  canPublish = true,
  notice = '',
}: {
  item: ContentItem;
  isNew: boolean;
  hasCategories: boolean;
  contentType: ContentTypeDefinition;
  draftKey?: string;
  workingCopy?: WorkingCopy | null;
  canPublish?: boolean;
  notice?: string;
}) {
  const { t } = useTranslation();
  const { csrfToken, categories = [], errors, siteUrl, mediaRules } = usePage<SharedProps>().props;
  const base = contentType.adminBase;
  const supports = (feature: string) => contentType.features.includes(feature);
  const label = (key: string) => collectionLabel(contentType, key, t);
  const seed = workingCopy?.data || {};
  const initialTags = seed.tagRecords || item.tags || [];
  const form = useForm<EditorValues>({
    id: String(item.id || ''),
    title: seed.title ?? item.title,
    slug: seed.slug ?? item.slug,
    excerpt: seed.excerpt ?? item.excerpt,
    content: seed.content ?? item.content ?? '',
    category: seed.category ?? item.category,
    image: seed.image ?? item.image,
    image_alt: seed.image_alt ?? item.image_alt,
    status: seed.status ?? item.status,
    featured:
      seed.featured === undefined
        ? item.featured
        : seed.featured === true || String(seed.featured) === '1',
    published_at: String(seed.published_at ?? item.published_at).slice(0, 10),
    tags: initialTags.map((tag) => tag.id).join(','),
    version: String(workingCopy?.baseVersion ?? item.version ?? 1),
    draft_key: draftKey,
    stay: '1',
    seo_title: seed.seo_title ?? item.seo_title ?? '',
    seo_description: seed.seo_description ?? item.seo_description ?? '',
    scheduled_epoch: String(seed.scheduled_epoch ?? item.scheduled_epoch ?? ''),
    custom_fields: JSON.stringify(
      readCustomFields(seed.custom_fields, contentType.fields, item.fields),
    ),
  });
  const [selectedTags, setSelectedTags] = useState(initialTags);
  const [customUploading, setCustomUploading] = useState(false);
  const customValues = readCustomFields(form.data.custom_fields, contentType.fields);
  const [mode, setMode] = useState<'write' | 'split' | 'preview'>('write');
  const preview = mode === 'preview';
  const previewContent = useDeferredValue(form.data.content);
  const [slugEdited, setSlugEdited] = useState(Boolean(form.data.slug));
  const [uploading, setUploading] = useState<UploadTarget | null>(null);
  const [feedback, setFeedback] = useState({ content: '', cover: '' });
  const [uploadError, setUploadError] = useState<UploadTarget | null>(null);
  const [libraryOpen, setLibraryOpen] = useState(false);
  const [conflictResolved, setConflictResolved] = useState(false);
  const canSave = canPublish || !['published', 'scheduled'].includes(item.status);
  const copy = useWorkingCopy({
    data: form.data,
    enabled: form.isDirty && !form.processing && !uploading && !customUploading,
    base,
    draftKey,
    initialVersion: workingCopy?.version || 0,
    csrfToken,
  });
  const unprotectedChanges = form.isDirty && !copy.protected;
  const conflict = Boolean(
    workingCopy && workingCopy.baseVersion !== (item.version || 1) && !conflictResolved,
  );
  const history = useRef({
    past: [] as string[],
    future: [] as string[],
    last: form.data.content,
    stamp: 0,
    ignore: false,
  });
  const [historyState, setHistoryState] = useState({ undo: false, redo: false });
  useEffect(() => {
    const state = history.current;
    if (state.ignore) {
      state.ignore = false;
      state.last = form.data.content;
      return;
    }
    if (state.last !== form.data.content) {
      if (Date.now() - state.stamp > 800) {
        state.past.push(state.last);
        state.past = state.past.slice(-50);
      }
      state.future = [];
      state.last = form.data.content;
      state.stamp = Date.now();
      setHistoryState({ undo: state.past.length > 0, redo: false });
    }
  }, [form.data.content]);
  function undo(redo = false) {
    const state = history.current;
    const source = redo ? state.future : state.past;
    const value = source.pop();
    if (value === undefined) return;
    (redo ? state.past : state.future).push(form.data.content);
    state.ignore = true;
    form.setData('content', value);
    setHistoryState({ undo: state.past.length > 0, redo: state.future.length > 0 });
  }
  const textarea = useRef<HTMLTextAreaElement>(null),
    fileInput = useRef<HTMLInputElement>(null),
    target = useRef<UploadTarget>('content'),
    submitting = useRef(false);
  useEffect(() => {
    const unload = (event: BeforeUnloadEvent) => {
      if (unprotectedChanges && !submitting.current) {
        event.preventDefault();
        event.returnValue = '';
      }
    };
    window.addEventListener('beforeunload', unload);
    const remove = router.on('before', (event) => {
      if (
        unprotectedChanges &&
        !submitting.current &&
        !window.confirm(t('Leave this content? Changes not saved as a working copy will be lost.'))
      )
        event.preventDefault();
    });
    return () => {
      window.removeEventListener('beforeunload', unload);
      remove();
    };
  }, [unprotectedChanges]);
  const words = form.data.content.trim().split(/\s+/).filter(Boolean).length;
  function removeCover() {
    form.setData((previous) => ({ ...previous, image: '', image_alt: '' }));
    setFeedback((previous) => ({ ...previous, cover: '' }));
    if (uploadError === 'cover') setUploadError(null);
  }
  function title(value: string) {
    form.setData((previous) => ({
      ...previous,
      title: value,
      ...(!slugEdited && {
        slug: value
          .toLowerCase()
          .normalize('NFKD')
          .replace(/[\u0300-\u036f]/g, '')
          .replace(/[^a-z0-9]+/g, '-')
          .replace(/^-|-$/g, '')
          .slice(0, 180),
      }),
    }));
  }
  function insert(prefix: string, text: string, suffix: string, select = false) {
    history.current.stamp = 0;
    const element = textarea.current;
    const start = element?.selectionStart ?? form.data.content.length,
      end = element?.selectionEnd ?? start;
    form.setData((previous) => ({
      ...previous,
      content:
        previous.content.slice(0, start) + prefix + text + suffix + previous.content.slice(end),
    }));
    requestAnimationFrame(() => {
      element?.focus();
      element?.setSelectionRange(
        select ? start + prefix.length : start + prefix.length + text.length + suffix.length,
        select
          ? start + prefix.length + text.length
          : start + prefix.length + text.length + suffix.length,
      );
    });
  }
  function format(kind: string) {
    const element = textarea.current;
    const selected = form.data.content.slice(
      element?.selectionStart ?? 0,
      element?.selectionEnd ?? 0,
    );
    const formats: Record<string, [string, string, string]> = {
      heading: ['\n\n## ', selected || 'Heading', '\n\n'],
      bold: ['**', selected || 'Text', '**'],
      italic: ['*', selected || 'Text', '*'],
      link: ['[', selected || 'Link text', '](https://example.com)'],
      code: ['\n\n```\n', selected || 'Your code here', '\n```\n\n'],
      table: ['\n\n', '| Column | Column |\n| --- | --- |\n| Value | Value |', '\n\n'],
      task: ['\n\n- [ ] ', selected || 'A task to complete', '\n'],
      ordered: ['\n\n1. ', selected || 'The first step', '\n'],
      rule: ['\n\n', '---', '\n\n'],
      quote: ['\n\n> ', selected || 'Quote', '\n\n'],
      list: ['\n\n- ', selected || 'List item', '\n'],
    };
    insert(...formats[kind]);
  }
  function chooseImage(kind: UploadTarget) {
    target.current = kind;
    fileInput.current?.click();
  }
  async function upload(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file || uploading) return;
    const kind = target.current;
    const status = (message: string, error = false) => {
      setFeedback((previous) => ({ ...previous, [kind]: message }));
      setUploadError(error ? kind : null);
    };
    setUploading(kind);
    status('Uploading image…');
    try {
      const data = await uploadManagedImage(file, csrfToken, mediaRules);
      const description = data.description;
      if (kind === 'cover') {
        form.setData((previous) => ({
          ...previous,
          image: data.url,
          image_alt: previous.image_alt || description,
        }));
        status('Cover image uploaded.');
      } else {
        const prefix = (textarea.current?.selectionStart ?? 0) > 0 ? '\n\n![' : '![';
        insert(prefix, description, '](' + data.url + ')\n\n', true);
        status('Image added. Edit the selected text to describe it.');
      }
    } catch (error) {
      status(
        error instanceof Error
          ? error.message
          : 'The image could not be uploaded. Please try again.',
        true,
      );
    } finally {
      setUploading(null);
    }
  }
  const uploadMessage = (kind: UploadTarget) =>
    feedback[kind] && (
      <p
        className={'upload-status ' + (uploadError === kind ? 'error' : '')}
        role="status"
        aria-live="polite"
      >
        {t(feedback[kind])}
      </p>
    );
  return (
    <>
      <PageHead title={label(isNew ? 'create' : 'edit')} admin />
      <form
        action={base + '/save'}
        method="post"
        id="content-editor"
        onKeyDown={(event) => {
          if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
            event.preventDefault();
            event.currentTarget.requestSubmit();
          }
        }}
        onSubmit={(event) => {
          event.preventDefault();
          submitting.current = true;
          form.transform((data) => ({
            ...data,
            featured: data.featured ? '1' : '0',
            _token: csrfToken,
          }));
          form.post(base + '/save', {
            preserveState: 'errors',
            onFinish: () => {
              submitting.current = false;
            },
          });
        }}
      >
        <input type="hidden" name="_token" value={csrfToken || ''} />
        <input type="hidden" name="id" value={form.data.id} />
        <input type="hidden" name="image" value={form.data.image} />
        <div className="admin-page-heading editor-heading">
          <div>
            <Link className="back-link" href={base}>
              <Icon name="arrow-left" /> {t('Back to')} {t(contentType.name)}
            </Link>
            <h1>{label(isNew ? 'create' : 'edit')}</h1>
          </div>
          <div className="editor-actions">
            <button
              className="button button-outline"
              type="button"
              disabled={!!uploading || customUploading || form.processing}
              onClick={() => setMode(preview ? 'write' : 'preview')}
            >
              <Icon name="eye" />
              {preview ? t('Back to writing') : t('Preview')}
            </button>
            <button
              className="button"
              type="submit"
              disabled={
                !!uploading ||
                customUploading ||
                form.processing ||
                !hasCategories ||
                !canSave ||
                conflict
              }
            >
              <Icon name="check" />
              {form.processing ? t('Saving…') : label('save')}
            </button>
          </div>
        </div>
        <Alert message={notice} />
        <Alert error message={errorText(form.errors) || errorText(errors?.content)} />
        {!canSave && (
          <Alert
            error
            message={t(
              'An editor or owner can update published content. Your working copy can still be saved.',
            )}
          />
        )}
        {workingCopy && (
          <div className="working-copy-notice">
            <span>
              {conflict
                ? t('The saved content changed after this working copy was created.')
                : t('A private working copy has been restored.')}
            </span>
            <div>
              <button
                className="text-link"
                type="button"
                onClick={() => {
                  submitting.current = true;
                  router.post(
                    base + '/' + (item.id || 0) + '/discard-working',
                    { _token: csrfToken, draft_key: draftKey },
                    { preserveState: false },
                  );
                }}
              >
                {t('Reload saved version')}
              </button>
              {conflict && (
                <button
                  className="button button-outline"
                  type="button"
                  onClick={() => {
                    form.setData('version', String(item.version || 1));
                    setConflictResolved(true);
                  }}
                >
                  {t('Keep this working copy')}
                </button>
              )}
            </div>
            {conflict && (
              <details>
                <summary>{t('View the current saved content before choosing')}</summary>
                <div className="content-prose">
                  <Markdown content={item.content || ''} />
                </div>
              </details>
            )}
          </div>
        )}
        <div className="editor-session-status">
          <span role="status">
            {copy.message
              ? t(copy.message)
              : workingCopy
                ? t('Working copy restored')
                : t('Ready to write')}
          </span>
          <div className="editor-mode-tabs" aria-label={t('Editor layout')}>
            {(['write', 'split', 'preview'] as const).map((value) => (
              <button
                className={mode === value ? 'selected' : ''}
                type="button"
                key={value}
                onClick={() => setMode(value)}
              >
                {value === 'write'
                  ? t('Write')
                  : value === 'split'
                    ? t('Split preview')
                    : t('Preview')}
              </button>
            ))}
          </div>
        </div>
        <div className="editor-grid">
          <div className={'editor-content ' + (mode === 'split' ? 'editor-split' : '')}>
            <section className="admin-card editor-writing" hidden={preview}>
              <label htmlFor="content-title">{label('title')}</label>
              <input
                id="content-title"
                className="title-input"
                name="title"
                placeholder={t('Give your content a title…')}
                value={form.data.title}
                onChange={(e) => title(e.target.value)}
                required
                minLength={contentType.minimumTitleLength}
                maxLength={180}
              />
              {supports('excerpt') && (
                <>
                  <label htmlFor="content-excerpt">
                    {t('Excerpt')} <span>{t("Your content's excerpt")}</span>
                  </label>
                  <textarea
                    id="content-excerpt"
                    name="excerpt"
                    rows={3}
                    placeholder={t('A few words to draw your reader in…')}
                    required={contentType.minimumExcerptLength > 0}
                    minLength={contentType.minimumExcerptLength || undefined}
                    maxLength={500}
                    value={form.data.excerpt}
                    onChange={(e) => form.setData('excerpt', e.target.value)}
                  />
                </>
              )}
              {supports('body') && (
                <>
                  <div className="editor-label">
                    <label htmlFor="content-content">{t('Content')}</label>
                    <span>
                      {words} {t('words')}
                    </span>
                  </div>
                  <div className="writing-toolbar" aria-label={t('Formatting tools')}>
                    <button
                      type="button"
                      disabled={!historyState.undo}
                      onClick={() => undo()}
                      aria-label={t('Undo')}
                    >
                      ↶
                    </button>
                    <button
                      type="button"
                      disabled={!historyState.redo}
                      onClick={() => undo(true)}
                      aria-label={t('Redo')}
                    >
                      ↷
                    </button>
                    <button
                      type="button"
                      onClick={() => format('italic')}
                      aria-label={t('Italic text')}
                    >
                      <em>{t('I')}</em>
                    </button>
                    <button type="button" onClick={() => format('link')} aria-label={t('Add link')}>
                      {t('Link')}
                    </button>
                    <button
                      type="button"
                      onClick={() => format('code')}
                      aria-label={t('Add code block')}
                    >
                      {t('Code')}
                    </button>
                    <button
                      type="button"
                      onClick={() => format('table')}
                      aria-label={t('Add table')}
                    >
                      {t('Table')}
                    </button>
                    <button
                      type="button"
                      onClick={() => format('task')}
                      aria-label={t('Add task list')}
                    >
                      {t('Tasks')}
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        target.current = 'content';
                        setLibraryOpen(true);
                      }}
                    >
                      {t('Library')}
                    </button>
                    <button
                      type="button"
                      onClick={() => format('heading')}
                      aria-label={t('Add heading')}
                    >
                      {t('H2')}
                    </button>
                    <button
                      type="button"
                      onClick={() => format('bold')}
                      aria-label={t('Bold text')}
                    >
                      <strong>{t('B')}</strong>
                    </button>
                    <button
                      type="button"
                      onClick={() => format('quote')}
                      aria-label={t('Add quotation')}
                    >
                      <Icon name="quote" />
                    </button>
                    <button type="button" onClick={() => format('list')} aria-label={t('Add list')}>
                      <Icon name="list" />
                    </button>
                    <button
                      type="button"
                      className="image-tool"
                      disabled={!!uploading || customUploading || form.processing}
                      onClick={() => chooseImage('content')}
                      aria-label={t('Upload image')}
                    >
                      <Icon name="image" /> {t('Image')}
                    </button>
                  </div>
                  {uploadMessage('content')}
                  <textarea
                    ref={textarea}
                    id="content-content"
                    className="content-input"
                    name="content"
                    rows={19}
                    placeholder={t('Start with a sentence. See where it takes you…')}
                    maxLength={100000}
                    value={form.data.content}
                    onChange={(e) => form.setData('content', e.target.value)}
                    onKeyDown={(event) => {
                      if (!(event.metaKey || event.ctrlKey)) return;
                      const key = event.key.toLowerCase();
                      if (key === 'z') {
                        event.preventDefault();
                        undo(event.shiftKey);
                      }
                      if (key === 'b' || key === 'i' || key === 'k') {
                        event.preventDefault();
                        format(key === 'b' ? 'bold' : key === 'i' ? 'italic' : 'link');
                      }
                    }}
                  />
                  <p className="field-help">
                    {t(
                      'Use ## for headings, **bold**, > for quotations, and - for lists. Upload images with the Image button.',
                    )}
                  </p>
                </>
              )}
              <CustomFieldsEditor
                definitions={contentType.fields}
                values={customValues}
                publishing={form.data.status !== 'draft'}
                onBusyChange={setCustomUploading}
                onChange={(key, value) =>
                  form.setData('custom_fields', JSON.stringify({ ...customValues, [key]: value }))
                }
              />
            </section>
            {mode !== 'write' && (
              <section className="admin-card editor-preview">
                <p className="small-label">{t('Reader preview')}</p>
                <h2>{form.data.title || t('Your content begins here')}</h2>
                <p className="content-deck">{form.data.excerpt}</p>
                <div className="content-prose">
                  <Markdown content={supports('body') ? previewContent : ''} />
                  <FieldValues definitions={contentType.fields} values={customValues} />
                </div>
              </section>
            )}
          </div>
          <aside className="editor-sidebar">
            <section className="admin-card">
              <h2>{t('Publishing')}</h2>
              <label htmlFor="content-status">{t('Status')}</label>
              <select
                name="status"
                id="content-status"
                value={form.data.status}
                onChange={(e) => form.setData('status', e.target.value as ContentItem['status'])}
              >
                <option value="draft">{t('Draft')}</option>
                <option value="published" disabled={!canPublish}>
                  {t('Published')}
                </option>
                {(supports('schedule') || form.data.status === 'scheduled') && (
                  <option value="scheduled" disabled={!canPublish || !supports('schedule')}>
                    {t('Scheduled')}
                  </option>
                )}
              </select>
              <p className="field-help">
                {t(
                  'Published content is available at its public address. Add it to Navigation to help visitors find it.',
                )}
              </p>
              {supports('categories') && (
                <>
                  <label htmlFor="content-category">{t('Category')}</label>
                  <CategoryInput
                    id="content-category"
                    value={form.data.category}
                    onChange={(value) => form.setData('category', value)}
                    initialOptions={categories}
                    required
                    disabled={!hasCategories}
                  />
                  {hasCategories ? (
                    <p className="field-help">
                      {t('Type a category name to search the existing categories.')}
                    </p>
                  ) : (
                    <p className="field-help category-empty-note">
                      {t('Add a category before saving your content.')}{' '}
                      <Link className="text-link" href="/admin/categories">
                        {t('Manage categories')}
                      </Link>
                    </p>
                  )}
                </>
              )}
              {supports('tags') && (
                <TagPicker
                  value={selectedTags}
                  onChange={(tags) => {
                    setSelectedTags(tags);
                    form.setData('tags', tags.map((tag) => tag.id).join(','));
                  }}
                />
              )}
              {form.data.status === 'scheduled' && (
                <>
                  <label htmlFor="scheduled-time">{t('Publish at')}</label>
                  <input
                    id="scheduled-time"
                    type="datetime-local"
                    required
                    value={localTime(form.data.scheduled_epoch)}
                    onChange={(event) =>
                      form.setData(
                        'scheduled_epoch',
                        event.target.value ? String(new Date(event.target.value).getTime()) : '',
                      )
                    }
                  />
                  <p className="field-help">{t("The time uses your browser's local timezone.")}</p>
                </>
              )}
              <label htmlFor="content-date">{t('Site date')}</label>
              <input
                id="content-date"
                type="date"
                name="published_at"
                value={form.data.published_at}
                onChange={(e) => form.setData('published_at', e.target.value)}
              />
              <label htmlFor="content-slug">{t('URL slug')}</label>
              <input
                id="content-slug"
                name="slug"
                value={form.data.slug}
                onChange={(e) => {
                  setSlugEdited(true);
                  form.setData('slug', e.target.value);
                }}
                placeholder={t('your-content item-title')}
                required
                pattern="[a-z0-9]+(-[a-z0-9]+)*"
                maxLength={180}
              />
              <p className="field-help">
                {contentType.publicBase}/{form.data.slug}
              </p>
              {supports('featured') && (
                <label className="checkbox-label">
                  <input
                    type="checkbox"
                    name="featured"
                    value="1"
                    checked={form.data.featured}
                    onChange={(e) => form.setData('featured', e.target.checked)}
                  />
                  <span>
                    <strong>{t('Put it in the spotlight')}</strong>
                    <small>{t('Feature this content item on the homepage.')}</small>
                  </span>
                </label>
              )}
            </section>
            {supports('seo') && (
              <section className="admin-card">
                <h2>{t('Search appearance')}</h2>
                <label htmlFor="seo-title">{t('Search title')}</label>
                <input
                  id="seo-title"
                  value={form.data.seo_title}
                  maxLength={180}
                  placeholder={form.data.title}
                  onChange={(event) => form.setData('seo_title', event.target.value)}
                />
                <label htmlFor="seo-description">{t('Search description')}</label>
                <textarea
                  id="seo-description"
                  rows={4}
                  value={form.data.seo_description}
                  maxLength={500}
                  placeholder={form.data.excerpt}
                  onChange={(event) => form.setData('seo_description', event.target.value)}
                />
                <div className="search-appearance">
                  <small>
                    {siteUrl}
                    {contentType.publicBase}/{form.data.slug}
                  </small>
                  <strong>
                    {form.data.seo_title || form.data.title || t('Your content title')}
                  </strong>
                  <p>
                    {form.data.seo_description ||
                      form.data.excerpt ||
                      t('Write a short description for search results.')}
                  </p>
                </div>
              </section>
            )}
            {supports('image') && (
              <section className="admin-card">
                <h2>{t('Set the scene')}</h2>
                <button
                  className="button button-outline"
                  type="button"
                  onClick={() => {
                    target.current = 'cover';
                    setLibraryOpen(true);
                  }}
                >
                  {t('Choose from library')}
                </button>
                {allowedImage(form.data.image) ? (
                  <img
                    className="cover-preview"
                    src={form.data.image}
                    alt={t('Cover image preview')}
                  />
                ) : (
                  <div className="cover-placeholder">
                    <Icon name="image" />
                    <p>{t('No cover image yet.')}</p>
                    <span>{t('Upload an image from your device.')}</span>
                  </div>
                )}
                <button
                  type="button"
                  className="button button-outline upload-cover-button"
                  onClick={() => chooseImage('cover')}
                  disabled={!!uploading || customUploading || form.processing}
                >
                  <Icon name="upload" /> {t('Upload cover image')}
                </button>
                <p className="upload-size-note">{t('JPEG, PNG or GIF. Up to 5 MB.')}</p>
                {uploadMessage('cover')}
                {form.data.image && (
                  <button
                    type="button"
                    className="remove-cover-button"
                    disabled={!!uploading || customUploading || form.processing}
                    onClick={removeCover}
                  >
                    {t('Remove cover image')}
                  </button>
                )}
                <label htmlFor="cover-alt">{t('Describe the image')}</label>
                <input
                  id="cover-alt"
                  name="image_alt"
                  value={form.data.image_alt}
                  onChange={(e) => form.setData('image_alt', e.target.value)}
                  placeholder={t('What does the photo show?')}
                  maxLength={500}
                />
                <p className="field-help">
                  {t('A short description makes your content more accessible.')}
                </p>
              </section>
            )}
            <p className="editor-note">
              <Icon name="feather" /> {t('Good content take their time.')}
            </p>
          </aside>
        </div>
        <input
          ref={fileInput}
          type="file"
          onChange={upload}
          accept={mediaRules?.mimeTypes.join(',')}
          aria-label={t('Choose an image to upload')}
          hidden
        />
        {!isNew && supports('revisions') && (
          <RevisionHistory
            base={base}
            id={String(item.id)}
            beforeRestore={() => {
              submitting.current = true;
            }}
          />
        )}
      </form>
      <MediaPicker
        open={libraryOpen}
        onClose={() => setLibraryOpen(false)}
        onPick={(image) => {
          if (target.current === 'cover') {
            form.setData((previous) => ({ ...previous, image: image.url, image_alt: image.alt }));
          } else {
            insert(
              '\n\n![',
              image.alt.replace(/[\[\]\r\n]/g, ' ') || 'Image description',
              '](' + image.url + ')\n\n',
            );
          }
        }}
      />
    </>
  );
}
Editor.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
