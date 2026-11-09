import { useTranslation } from '../i18n';
import { useEffect, useMemo, useRef, useState, type ChangeEvent } from 'react';
import Alert from './Alert';
import Markdown, { allowedImage } from './Markdown';
import Icon from './Icon';
import CategoryInput from './CategoryInput';
import TagPicker from './TagPicker';
import MediaPicker from './MediaPicker';
import RevisionHistory from './RevisionHistory';
import useWorkingCopy from './useWorkingCopy';
import CustomFieldsEditor from './CustomFieldsEditor';
import {
  collectionLabel,
  readCustomFields,
  type ContentTypeDefinition,
  type CustomFieldValues,
} from '../content';
import { uploadManagedImage, type MediaRules } from '../media';
import { postForm } from '../post-form';
import type { ContentItem, Tag } from '../types';

type UploadTarget = 'content' | 'cover';
type ContentStatus = ContentItem['status'];

interface EditorValues {
  id: string;
  title: string;
  slug: string;
  excerpt: string;
  content: string;
  category: string;
  image: string;
  image_alt: string;
  status: ContentStatus;
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
  language: string;
  all_languages: boolean;
  translation_of: string;
}

/** The saved content item, as `ContentEditorData` prepares it. */
export interface EditorItem {
  id: number;
  title: string;
  slug: string;
  excerpt: string;
  content: string;
  category: string;
  image: string;
  image_alt: string;
  status: ContentStatus;
  featured: boolean;
  published_at: string;
  version: number;
  seo_title: string;
  seo_description: string;
  scheduled_epoch: string;
  tags: Tag[];
  fields: CustomFieldValues;
  language: string;
  all_languages: boolean;
}

/** The site's languages and the item's translations; no choices on a single-language site. */
export interface EditorLanguages {
  choices: { code: string; name: string; direction: string; enabled: boolean }[];
  translations: {
    id: number;
    language: string;
    name: string;
    title: string;
    status: string;
    editUrl: string;
  }[];
  missing: { code: string; name: string; url: string }[];
  translationOf: number;
  sourceTitle: string;
}

export type EditorContentType = Pick<
  ContentTypeDefinition,
  | 'name'
  | 'singular'
  | 'adminBase'
  | 'publicBase'
  | 'features'
  | 'fields'
  | 'labels'
  | 'minimumTitleLength'
  | 'minimumExcerptLength'
>;

export interface EditorWorkingCopy {
  key: string;
  baseVersion: number;
  version: number;
  updatedAt: string;
}

/** Unsaved values from a working copy or a submission that failed validation. */
export interface EditorSeed {
  values: Partial<Record<keyof EditorValues, string>>;
  tags: Tag[] | null;
}

export interface ContentEditorData {
  heading: string;
  item: EditorItem;
  contentType: EditorContentType;
  isNew: boolean;
  hasCategories: boolean;
  categories: string[];
  draftKey: string;
  workingCopy: EditorWorkingCopy | null;
  seed: EditorSeed | null;
  canPublish: boolean;
  notice: string;
  mediaRules: MediaRules;
  languages: EditorLanguages;
}

function localTime(epoch: string) {
  const value = Number(epoch);
  if (!Number.isFinite(value) || value <= 0) return '';
  const date = new Date(value);
  return new Date(value - date.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
}

function initialValues(editor: ContentEditorData): EditorValues {
  const { item, contentType, workingCopy } = editor;
  const seed = editor.seed?.values ?? {};
  const tags = editor.seed?.tags ?? item.tags;
  const featured =
    seed.featured === undefined ? item.featured : seed.featured === '1' || seed.featured === 'true';
  const customFields = readCustomFields(seed.custom_fields, contentType.fields, item.fields);
  return {
    id: item.id ? String(item.id) : '',
    title: seed.title ?? item.title,
    slug: seed.slug ?? item.slug,
    excerpt: seed.excerpt ?? item.excerpt,
    content: seed.content ?? item.content,
    category: seed.category ?? item.category,
    image: seed.image ?? item.image,
    image_alt: seed.image_alt ?? item.image_alt,
    status: (seed.status ?? item.status) as ContentStatus,
    featured,
    published_at: (seed.published_at ?? item.published_at).slice(0, 10),
    tags: tags.map((tag) => tag.id).join(','),
    version: seed.version ?? String(workingCopy?.baseVersion ?? item.version ?? 1),
    draft_key: editor.draftKey,
    stay: '1',
    seo_title: seed.seo_title ?? item.seo_title,
    seo_description: seed.seo_description ?? item.seo_description,
    scheduled_epoch: seed.scheduled_epoch ?? item.scheduled_epoch,
    custom_fields: JSON.stringify(customFields),
    language: seed.language ?? item.language,
    all_languages:
      seed.all_languages === undefined
        ? item.all_languages
        : seed.all_languages === '1' || seed.all_languages === 'true',
    translation_of:
      seed.translation_of ??
      (editor.languages.translationOf ? String(editor.languages.translationOf) : ''),
  };
}

/** The content editor: a Wellout island on the `Admin/Editor` page. */
export default function ContentEditor({
  editor,
  csrfToken,
  siteUrl,
  error,
}: {
  editor: ContentEditorData;
  csrfToken: string;
  siteUrl: string;
  error: string;
}) {
  const { t } = useTranslation();
  const {
    item,
    isNew,
    hasCategories,
    contentType,
    draftKey,
    workingCopy,
    canPublish,
    notice,
    categories,
    mediaRules,
  } = editor;
  const base = contentType.adminBase;
  const supports = (feature: string) => contentType.features.includes(feature);
  const label = (key: string) => collectionLabel(contentType, key, t);
  const [initial] = useState(() => initialValues(editor));
  const [data, setValues] = useState(initial);
  const setData = <K extends keyof EditorValues>(key: K, value: EditorValues[K]) =>
    setValues((previous) => ({ ...previous, [key]: value }));
  const initialSignature = useMemo(() => JSON.stringify(initial), [initial]);
  const isDirty = useMemo(
    () => JSON.stringify(data) !== initialSignature,
    [data, initialSignature],
  );
  const [processing, setProcessing] = useState(false);
  const [selectedTags, setSelectedTags] = useState(() => editor.seed?.tags ?? item.tags);
  const [customUploading, setCustomUploading] = useState(false);
  const customValues = readCustomFields(data.custom_fields, contentType.fields);
  const [mode, setMode] = useState<'write' | 'split' | 'preview'>('write');
  const preview = mode === 'preview';
  const showPreview = mode !== 'write';
  const previewForm = useRef<HTMLFormElement>(null);
  const previewUrl = `${base}/preview`;
  const [slugEdited, setSlugEdited] = useState(Boolean(data.slug));
  const [uploading, setUploading] = useState<UploadTarget | null>(null);
  const [feedback, setFeedback] = useState({ content: '', cover: '' });
  const [uploadError, setUploadError] = useState<UploadTarget | null>(null);
  const [libraryOpen, setLibraryOpen] = useState(false);
  const [conflictResolved, setConflictResolved] = useState(false);
  useEffect(() => {
    if (!showPreview) return;
    const timer = window.setTimeout(() => previewForm.current?.requestSubmit(), 300);
    return () => window.clearTimeout(timer);
  }, [showPreview, data, csrfToken, previewUrl]);

  const canSave = canPublish || !['published', 'scheduled'].includes(item.status);
  const copy = useWorkingCopy({
    data,
    enabled: isDirty && !processing && !uploading && !customUploading,
    base,
    draftKey,
    initialVersion: workingCopy?.version || 0,
    csrfToken,
  });
  const unprotectedChanges = isDirty && !copy.protected;
  const conflict = Boolean(
    workingCopy && workingCopy.baseVersion !== (item.version || 1) && !conflictResolved,
  );
  const history = useRef({
    past: [] as string[],
    future: [] as string[],
    last: data.content,
    stamp: 0,
    ignore: false,
  });
  const [historyState, setHistoryState] = useState({ undo: false, redo: false });
  useEffect(() => {
    const state = history.current;
    if (state.ignore) {
      state.ignore = false;
      state.last = data.content;
      return;
    }
    if (state.last !== data.content) {
      if (Date.now() - state.stamp > 800) {
        state.past.push(state.last);
        state.past = state.past.slice(-50);
      }
      state.future = [];
      state.last = data.content;
      state.stamp = Date.now();
      setHistoryState({ undo: state.past.length > 0, redo: false });
    }
  }, [data.content]);
  function undo(redo = false) {
    const state = history.current;
    const source = redo ? state.future : state.past;
    const value = source.pop();
    if (value === undefined) return;
    (redo ? state.past : state.future).push(data.content);
    state.ignore = true;
    setData('content', value);
    setHistoryState({ undo: state.past.length > 0, redo: state.future.length > 0 });
  }
  const textarea = useRef<HTMLTextAreaElement>(null);
  const fileInput = useRef<HTMLInputElement>(null);
  const target = useRef<UploadTarget>('content');
  const submitting = useRef(false);
  useEffect(() => {
    const unload = (event: BeforeUnloadEvent) => {
      if (unprotectedChanges && !submitting.current) {
        event.preventDefault();
        event.returnValue = '';
      }
    };
    window.addEventListener('beforeunload', unload);
    return () => window.removeEventListener('beforeunload', unload);
  }, [unprotectedChanges]);
  useEffect(() => {
    // A page restored from the back-forward cache is editable again.
    const restored = (event: PageTransitionEvent) => {
      if (!event.persisted) return;
      submitting.current = false;
      setProcessing(false);
    };
    window.addEventListener('pageshow', restored);
    return () => window.removeEventListener('pageshow', restored);
  }, []);
  const words = data.content.trim().split(/\s+/).filter(Boolean).length;
  const busy = !!uploading || customUploading || processing;
  function removeCover() {
    setValues((previous) => ({ ...previous, image: '', image_alt: '' }));
    setFeedback((previous) => ({ ...previous, cover: '' }));
    if (uploadError === 'cover') setUploadError(null);
  }
  function title(value: string) {
    setValues((previous) => ({
      ...previous,
      title: value,
      ...(!slugEdited && {
        slug: value
          .toLowerCase()
          .normalize('NFKD')
          .replace(/[̀-ͯ]/g, '')
          .replace(/[^a-z0-9]+/g, '-')
          .replace(/^-|-$/g, '')
          .slice(0, 180),
      }),
    }));
  }
  function insert(prefix: string, text: string, suffix: string, select = false) {
    history.current.stamp = 0;
    const element = textarea.current;
    const start = element?.selectionStart ?? data.content.length;
    const end = element?.selectionEnd ?? start;
    setValues((previous) => ({
      ...previous,
      content: `${previous.content.slice(0, start)}${prefix}${text}${suffix}${previous.content.slice(end)}`,
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
    const selected = data.content.slice(element?.selectionStart ?? 0, element?.selectionEnd ?? 0);
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
    const status = (message: string, failed = false) => {
      setFeedback((previous) => ({ ...previous, [kind]: message }));
      setUploadError(failed ? kind : null);
    };
    setUploading(kind);
    status('Uploading image…');
    try {
      const uploaded = await uploadManagedImage(file, csrfToken, mediaRules);
      const description = uploaded.description;
      if (kind === 'cover') {
        setValues((previous) => ({
          ...previous,
          image: uploaded.url,
          image_alt: previous.image_alt || description,
        }));
        status('Cover image uploaded.');
      } else {
        const prefix = (textarea.current?.selectionStart ?? 0) > 0 ? '\n\n![' : '![';
        insert(prefix, description, `](${uploaded.url})\n\n`, true);
        status('Image added. Edit the selected text to describe it.');
      }
    } catch (failure) {
      status(
        failure instanceof Error
          ? failure.message
          : 'The image could not be uploaded. Please try again.',
        true,
      );
    } finally {
      setUploading(null);
    }
  }
  function leaveWith(action: () => void) {
    submitting.current = true;
    action();
  }
  const uploadMessage = (kind: UploadTarget) =>
    feedback[kind] && (
      <p
        className={`upload-status ${uploadError === kind ? 'error' : ''}`}
        role="status"
        aria-live="polite"
      >
        {t(feedback[kind])}
      </p>
    );
  return (
    <>
      <form
        id="content-preview-form"
        ref={previewForm}
        action={previewUrl}
        method="post"
        target="content-preview-frame"
        hidden
      >
        <input type="hidden" name="_token" value={csrfToken} />
        {Object.entries(data).map(([name, value]) => (
          <input
            key={name}
            type="hidden"
            name={name}
            value={typeof value === 'boolean' ? (value ? '1' : '0') : value}
          />
        ))}
      </form>
      <form
        action={`${base}/save`}
        method="post"
        id="content-editor"
        onKeyDown={(event) => {
          if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
            event.preventDefault();
            event.currentTarget.requestSubmit();
          }
        }}
        onSubmit={(event) => {
          // The browser posts the form; the handler redirects to the saved
          // content or back here with the validation error.
          if (processing) {
            event.preventDefault();
            return;
          }
          submitting.current = true;
          setProcessing(true);
        }}
      >
        <input type="hidden" name="_token" value={csrfToken} />
        <input type="hidden" name="id" value={data.id} />
        <input type="hidden" name="image" value={data.image} />
        <input type="hidden" name="featured" value={data.featured ? '1' : '0'} />
        <input type="hidden" name="tags" value={data.tags} />
        <input type="hidden" name="version" value={data.version} />
        <input type="hidden" name="draft_key" value={data.draft_key} />
        <input type="hidden" name="stay" value={data.stay} />
        <input type="hidden" name="seo_title" value={data.seo_title} />
        <input type="hidden" name="seo_description" value={data.seo_description} />
        <input type="hidden" name="scheduled_epoch" value={data.scheduled_epoch} />
        <input type="hidden" name="custom_fields" value={data.custom_fields} />
        <input type="hidden" name="language" value={data.language} />
        <input type="hidden" name="all_languages" value={data.all_languages ? '1' : '0'} />
        <input type="hidden" name="translation_of" value={data.translation_of} />
        <div className="admin-page-heading editor-heading">
          <div>
            <a className="back-link" href={base}>
              <Icon name="arrow-left" /> {t('Back to')} {t(contentType.name)}
            </a>
            <h1>{editor.heading}</h1>
          </div>
          <div className="editor-actions">
            <button
              className="button button-outline"
              type="button"
              disabled={busy}
              onClick={() => setMode(preview ? 'write' : 'preview')}
            >
              <Icon name="eye" />
              {preview ? t('Back to writing') : t('Preview')}
            </button>
            <button
              className="button button-outline"
              type="submit"
              form="content-preview-form"
              formTarget="_blank"
              disabled={busy}
            >
              <Icon name="external" />
              {t('Full preview')}
            </button>
            <button
              className="button"
              type="submit"
              disabled={busy || !hasCategories || !canSave || conflict}
            >
              <Icon name="check" />
              {processing ? t('Saving…') : label('save')}
            </button>
          </div>
        </div>
        <Alert message={notice} />
        <Alert error message={error} />
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
                onClick={() =>
                  leaveWith(() =>
                    postForm(`${base}/${item.id || 0}/discard-working`, {
                      _token: csrfToken,
                      draft_key: draftKey,
                    }),
                  )
                }
              >
                {t('Reload saved version')}
              </button>
              {conflict && (
                <button
                  className="button button-outline"
                  type="button"
                  onClick={() => {
                    setData('version', String(item.version || 1));
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
                  <Markdown content={item.content} />
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
        <div className={`editor-grid${preview ? ' editor-grid-preview' : ''}`}>
          <div className={`editor-content ${mode === 'split' ? 'editor-split' : ''}`}>
            <section className="admin-card editor-writing" hidden={preview}>
              <label htmlFor="content-title">{label('title')}</label>
              <input
                id="content-title"
                className="title-input"
                name="title"
                placeholder={t('Give your content a title…')}
                value={data.title}
                onChange={(event) => title(event.target.value)}
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
                    value={data.excerpt}
                    onChange={(event) => setData('excerpt', event.target.value)}
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
                      disabled={busy}
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
                    value={data.content}
                    onChange={(event) => setData('content', event.target.value)}
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
                publishing={data.status !== 'draft'}
                csrfToken={csrfToken}
                mediaRules={mediaRules}
                onBusyChange={setCustomUploading}
                onChange={(key, value) =>
                  setData('custom_fields', JSON.stringify({ ...customValues, [key]: value }))
                }
              />
            </section>
            {showPreview && (
              <section className="admin-card editor-preview">
                <p className="small-label">{t('Reader preview')}</p>
                <iframe
                  name="content-preview-frame"
                  className="editor-preview-frame"
                  title={t('Reader preview')}
                />
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
                value={data.status}
                onChange={(event) => setData('status', event.target.value as ContentStatus)}
              >
                <option value="draft">{t('Draft')}</option>
                <option value="published" disabled={!canPublish}>
                  {t('Published')}
                </option>
                {(supports('schedule') || data.status === 'scheduled') && (
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
                    value={data.category}
                    onChange={(value) => setData('category', value)}
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
                      <a className="text-link" href="/admin/categories">
                        {t('Manage categories')}
                      </a>
                    </p>
                  )}
                </>
              )}
              {supports('tags') && (
                <TagPicker
                  value={selectedTags}
                  onChange={(tags) => {
                    setSelectedTags(tags);
                    setData('tags', tags.map((tag) => tag.id).join(','));
                  }}
                />
              )}
              {data.status === 'scheduled' && (
                <>
                  <label htmlFor="scheduled-time">{t('Publish at')}</label>
                  <input
                    id="scheduled-time"
                    type="datetime-local"
                    required
                    value={localTime(data.scheduled_epoch)}
                    onChange={(event) =>
                      setData(
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
                value={data.published_at}
                onChange={(event) => setData('published_at', event.target.value)}
              />
              <label htmlFor="content-slug">{t('URL slug')}</label>
              <input
                id="content-slug"
                name="slug"
                value={data.slug}
                onChange={(event) => {
                  setSlugEdited(true);
                  setData('slug', event.target.value);
                }}
                placeholder={t('your-content item-title')}
                required
                pattern="[a-z0-9]+(-[a-z0-9]+)*"
                maxLength={180}
              />
              <p className="field-help">
                {contentType.publicBase}/{data.slug}
              </p>
              {editor.languages.choices.length > 0 && (
                <>
                  <label htmlFor="content-language">{t('Language')}</label>
                  <select
                    id="content-language"
                    value={data.language}
                    onChange={(event) => setData('language', event.target.value)}
                  >
                    {editor.languages.choices.map((choice) => (
                      <option key={choice.code} value={choice.code}>
                        {choice.enabled ? choice.name : `${choice.name} (${t('Disabled')})`}
                      </option>
                    ))}
                  </select>
                  {editor.languages.sourceTitle && (
                    <p className="field-help">
                      {t('A translation of “{title}”.', { title: editor.languages.sourceTitle })}
                    </p>
                  )}
                  <label className="checkbox-label">
                    <input
                      type="checkbox"
                      checked={data.all_languages}
                      onChange={(event) => setData('all_languages', event.target.checked)}
                    />
                    <span>
                      <strong>{t('Show in every language')}</strong>
                      <small>
                        {t('Languages without a published translation list this item as it is.')}
                      </small>
                    </span>
                  </label>
                </>
              )}
              {supports('featured') && (
                <label className="checkbox-label">
                  <input
                    type="checkbox"
                    checked={data.featured}
                    onChange={(event) => setData('featured', event.target.checked)}
                  />
                  <span>
                    <strong>{t('Put it in the spotlight')}</strong>
                    <small>{t('Feature this content item on the homepage.')}</small>
                  </span>
                </label>
              )}
            </section>
            {editor.languages.choices.length > 0 && !isNew && (
              <section className="admin-card editor-translations">
                <h2>{t('Translations')}</h2>
                {editor.languages.translations.length > 0 ? (
                  <ul>
                    {editor.languages.translations.map((translation) => (
                      <li key={translation.id}>
                        <a href={translation.editUrl}>
                          <strong>{translation.name}</strong> {translation.title}
                        </a>
                        <span className={`status-badge ${translation.status}`}>
                          {t(translation.status === 'published' ? 'Published' : 'Draft')}
                        </span>
                      </li>
                    ))}
                  </ul>
                ) : (
                  <p className="field-help">{t('This content has no translations yet.')}</p>
                )}
                {editor.languages.missing.length > 0 && (
                  <p className="editor-translation-actions">
                    {editor.languages.missing.map((language) => (
                      <a key={language.code} className="button button-outline" href={language.url}>
                        {t('Translate into {language}', { language: language.name })}
                      </a>
                    ))}
                  </p>
                )}
              </section>
            )}
            {supports('seo') && (
              <section className="admin-card">
                <h2>{t('Search appearance')}</h2>
                <label htmlFor="seo-title">{t('Search title')}</label>
                <input
                  id="seo-title"
                  value={data.seo_title}
                  maxLength={180}
                  placeholder={data.title}
                  onChange={(event) => setData('seo_title', event.target.value)}
                />
                <label htmlFor="seo-description">{t('Search description')}</label>
                <textarea
                  id="seo-description"
                  rows={4}
                  value={data.seo_description}
                  maxLength={500}
                  placeholder={data.excerpt}
                  onChange={(event) => setData('seo_description', event.target.value)}
                />
                <div className="search-appearance">
                  <small>
                    {siteUrl}
                    {contentType.publicBase}/{data.slug}
                  </small>
                  <strong>{data.seo_title || data.title || t('Your content title')}</strong>
                  <p>
                    {data.seo_description ||
                      data.excerpt ||
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
                {allowedImage(data.image) ? (
                  <img className="cover-preview" src={data.image} alt={t('Cover image preview')} />
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
                  disabled={busy}
                >
                  <Icon name="upload" /> {t('Upload cover image')}
                </button>
                <p className="upload-size-note">{t('JPEG, PNG or GIF. Up to 5 MB.')}</p>
                {uploadMessage('cover')}
                {data.image && (
                  <button
                    type="button"
                    className="remove-cover-button"
                    disabled={busy}
                    onClick={removeCover}
                  >
                    {t('Remove cover image')}
                  </button>
                )}
                <label htmlFor="cover-alt">{t('Describe the image')}</label>
                <input
                  id="cover-alt"
                  name="image_alt"
                  value={data.image_alt}
                  onChange={(event) => setData('image_alt', event.target.value)}
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
          accept={mediaRules.mimeTypes.join(',')}
          aria-label={t('Choose an image to upload')}
          hidden
        />
        {!isNew && supports('revisions') && (
          <RevisionHistory
            base={base}
            id={String(item.id)}
            csrfToken={csrfToken}
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
            setValues((previous) => ({ ...previous, image: image.url, image_alt: image.alt }));
          } else {
            insert(
              '\n\n![',
              image.alt.replace(/[\[\]\r\n]/g, ' ') || 'Image description',
              `](${image.url})\n\n`,
            );
          }
        }}
      />
    </>
  );
}
