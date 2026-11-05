import { Link, router, useForm, usePage } from '@inertiajs/react';
import type { ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Alert from '../../components/Alert';
import Icon from '../../components/Icon';
import { errorText, type SharedProps } from '../../types';
import type { ContentFieldDefinition, ContentTypeDefinition } from '../../content';
import { useTranslation } from '../../i18n';

const featureLabels: Record<string, string> = {
  body: 'Content editor',
  excerpt: 'Excerpt',
  categories: 'Categories',
  tags: 'Tags',
  image: 'Cover image',
  seo: 'Search appearance',
  featured: 'Featured content',
  reading_time: 'Reading time',
  revisions: 'Revision history',
  schedule: 'Scheduled publication',
};

export default function ContentTypeEditor({
  definition,
  isNew,
  supportedFeatures,
  fieldKinds,
  notice,
}: {
  definition: ContentTypeDefinition | null;
  isNew: boolean;
  supportedFeatures: string[];
  fieldKinds: ContentFieldDefinition['kind'][];
  notice: string;
}) {
  const { t } = useTranslation();
  const { csrfToken, errors, siteUrl } = usePage<SharedProps>().props;
  const form = useForm({
    key: definition?.key || '',
    name: definition?.name || '',
    singular: definition?.singular || '',
    description: definition?.description || '',
    publicPath: definition?.publicBase.slice(1) || '',
    icon: definition?.icon || 'file',
    position: definition?.position ?? 10,
    publicVisible: definition?.publicVisible ?? true,
    hasArchive: definition?.hasArchive ?? true,
    enabled: definition?.enabled ?? true,
    dedicatedAccess: Boolean(definition?.capability && definition.capability !== 'content'),
    template: definition?.template || 'ContentDetail',
    archiveTemplate: definition?.archiveTemplate || 'ContentIndex',
    minimumTitleLength: definition?.minimumTitleLength ?? 1,
    minimumContentLength: definition?.minimumContentLength ?? 0,
    minimumExcerptLength: definition?.minimumExcerptLength ?? 0,
    features: definition?.features || ['body', 'excerpt', 'image', 'seo', 'revisions', 'schedule'],
    fields: definition?.fields || [],
    labels: definition?.labels || { create: '', edit: '', save: '', title: '', description: '' },
  });

  function updateField(index: number, changes: Partial<ContentFieldDefinition>) {
    form.setData(
      'fields',
      form.data.fields.map((field, current) =>
        current === index ? { ...field, ...changes } : field,
      ),
    );
  }

  function moveField(index: number, delta: number) {
    const fields = [...form.data.fields];
    const target = index + delta;
    if (target < 0 || target >= fields.length) return;
    [fields[index], fields[target]] = [fields[target], fields[index]];
    form.setData('fields', fields);
  }

  const savePath = isNew
    ? '/admin/content-types/create'
    : '/admin/content-types/' + definition?.key + '/save';
  return (
    <>
      <PageHead title={isNew ? t('New collection') : t('Edit collection')} admin />
      <form
        action={savePath}
        method="post"
        onSubmit={(event) => {
          event.preventDefault();
          form.transform((data) => ({ definition: JSON.stringify(data), _token: csrfToken }));
          form.post(savePath, { preserveState: 'errors' });
        }}
      >
        <div className="admin-page-heading">
          <div>
            <Link className="back-link" href="/admin/collections">
              <Icon name="arrow-left" /> {t('All collections')}
            </Link>
            <h1>{isNew ? t('New collection') : definition?.name}</h1>
          </div>
          <button className="button" type="submit" disabled={form.processing}>
            <Icon name="check" /> {form.processing ? t('Saving…') : t('Save collection')}
          </button>
        </div>
        <Alert error message={errorText(form.errors) || errorText(errors?.structure)} />
        <Alert message={notice === 'saved' ? t('The collection definition has been saved.') : ''} />
        {definition?.owner && (
          <Alert
            message={t(
              'This collection is provided by {plugin}. Its data and your settings are retained when the plugin is disabled.',
              { plugin: definition.owner },
            )}
          />
        )}
        <div className="editor-grid structure-grid">
          <div className="editor-main-column">
            <section className="admin-card editor-card">
              <h2>{t('Collection details')}</h2>
              <label htmlFor="type-name">{t('Collection name')}</label>
              <input
                id="type-name"
                value={form.data.name}
                required
                maxLength={100}
                onChange={(event) => form.setData('name', event.target.value)}
                placeholder={t('Products')}
              />
              <label htmlFor="type-singular">{t('Singular name')}</label>
              <input
                id="type-singular"
                value={form.data.singular}
                required
                maxLength={80}
                onChange={(event) => form.setData('singular', event.target.value)}
                placeholder={t('Product')}
              />
              <label htmlFor="type-key">{t('Stable key')}</label>
              <input
                id="type-key"
                value={form.data.key}
                required
                maxLength={32}
                pattern="[a-z][a-z0-9_]{0,31}"
                readOnly={!isNew}
                onChange={(event) => {
                  const key = event.target.value;
                  form.setData((previous) => {
                    const generatedPath = previous.key.replaceAll('_', '-');
                    const publicPath =
                      !previous.publicPath || previous.publicPath === generatedPath
                        ? key.replaceAll('_', '-')
                        : previous.publicPath;
                    return { ...previous, key, publicPath };
                  });
                }}
              />
              <p className="field-help">
                {t('The key identifies stored content and cannot be changed after creation.')}
              </p>
              <label htmlFor="type-description">{t('Description')}</label>
              <textarea
                id="type-description"
                rows={3}
                maxLength={500}
                value={form.data.description}
                onChange={(event) => form.setData('description', event.target.value)}
              />
            </section>
            <section className="admin-card editor-card">
              <h2>{t('Editor features')}</h2>
              <p className="field-help">
                {t('The same editor and publishing workflow adapts to the features you enable.')}
              </p>
              <div className="structure-feature-grid">
                {supportedFeatures.map((feature) => (
                  <label className="checkbox-label" key={feature}>
                    <input
                      type="checkbox"
                      checked={form.data.features.includes(feature)}
                      onChange={(event) =>
                        form.setData(
                          'features',
                          event.target.checked
                            ? [...form.data.features, feature]
                            : form.data.features.filter((value) => value !== feature),
                        )
                      }
                    />
                    <span>{t(featureLabels[feature] || feature)}</span>
                  </label>
                ))}
              </div>
            </section>
            <section className="admin-card editor-card">
              <div className="section-heading">
                <div>
                  <h2>{t('Custom fields')}</h2>
                  <p className="field-help">
                    {t(
                      'Add structured data without changing the content table or writing a new editor.',
                    )}
                  </p>
                </div>
                <button
                  className="button button-outline"
                  type="button"
                  disabled={form.data.fields.length >= 32}
                  onClick={() =>
                    form.setData('fields', [
                      ...form.data.fields,
                      {
                        key: '',
                        label: '',
                        kind: 'text',
                        help: '',
                        required: false,
                        publicVisible: true,
                        filterable: false,
                        inList: false,
                        options: [],
                      },
                    ])
                  }
                >
                  <Icon name="plus" /> {t('Add field')}
                </button>
              </div>
              {form.data.fields.length === 0 && (
                <p className="field-help">{t('This collection has no custom fields yet.')}</p>
              )}
              {form.data.fields.map((field, index) => (
                <fieldset className="structure-field" key={index}>
                  <legend>
                    {field.label || t('New field')} <span className="field-help">{index + 1}</span>
                  </legend>
                  <div className="structure-field-actions">
                    <button
                      className="icon-button"
                      type="button"
                      disabled={index === 0}
                      onClick={() => moveField(index, -1)}
                      aria-label={t('Move field up')}
                    >
                      <Icon name="arrow-up" />
                    </button>
                    <button
                      className="icon-button"
                      type="button"
                      disabled={index === form.data.fields.length - 1}
                      onClick={() => moveField(index, 1)}
                      aria-label={t('Move field down')}
                    >
                      <Icon name="arrow-down" />
                    </button>
                    <button
                      className="icon-button"
                      type="button"
                      onClick={() =>
                        form.setData(
                          'fields',
                          form.data.fields.filter((_, current) => current !== index),
                        )
                      }
                      aria-label={t('Remove field')}
                    >
                      <Icon name="trash" />
                    </button>
                  </div>
                  <div className="structure-field-grid">
                    <div>
                      <label htmlFor={'field-label-' + index}>{t('Field label')}</label>
                      <input
                        id={'field-label-' + index}
                        required
                        maxLength={100}
                        value={field.label}
                        onChange={(event) => updateField(index, { label: event.target.value })}
                      />
                    </div>
                    <div>
                      <label htmlFor={'field-key-' + index}>{t('Field key')}</label>
                      <input
                        id={'field-key-' + index}
                        required
                        maxLength={32}
                        pattern="[a-z][a-z0-9_]{0,31}"
                        value={field.key}
                        onChange={(event) => updateField(index, { key: event.target.value })}
                      />
                    </div>
                    <div>
                      <label htmlFor={'field-kind-' + index}>{t('Field type')}</label>
                      <select
                        id={'field-kind-' + index}
                        value={field.kind}
                        onChange={(event) =>
                          updateField(index, {
                            kind: event.target.value as ContentFieldDefinition['kind'],
                            inList: ['textarea', 'image'].includes(event.target.value)
                              ? false
                              : field.inList,
                            filterable: ['textarea', 'image'].includes(event.target.value)
                              ? false
                              : field.filterable,
                          })
                        }
                      >
                        {fieldKinds.map((kind) => (
                          <option key={kind} value={kind}>
                            {t('field.kind.' + kind)}
                          </option>
                        ))}
                      </select>
                    </div>
                    <div>
                      <label htmlFor={'field-help-' + index}>{t('Help text')}</label>
                      <input
                        id={'field-help-' + index}
                        maxLength={300}
                        value={field.help}
                        onChange={(event) => updateField(index, { help: event.target.value })}
                      />
                    </div>
                  </div>
                  {field.kind === 'select' && (
                    <div>
                      <label htmlFor={'field-options-' + index}>{t('Choices')}</label>
                      <textarea
                        id={'field-options-' + index}
                        rows={3}
                        key={field.key}
                        defaultValue={field.options
                          .map((option) => option.value + ' | ' + option.label)
                          .join('\n')}
                        placeholder="in-stock | In stock"
                        onChange={(event) =>
                          updateField(index, {
                            options: event.target.value
                              .split('\n')
                              .filter((line) => line.trim())
                              .map((line) => {
                                const [value, ...label] = line.split('|');
                                return {
                                  value: value.trim(),
                                  label: label.join('|').trim() || value.trim(),
                                };
                              }),
                          })
                        }
                      />
                      <p className="field-help">
                        {t('One choice per line: stable value | display label.')}
                      </p>
                    </div>
                  )}
                  <div className="structure-field-flags">
                    <label className="checkbox-label">
                      <input
                        type="checkbox"
                        disabled={['textarea', 'image'].includes(field.kind)}
                        checked={field.inList}
                        onChange={(event) => updateField(index, { inList: event.target.checked })}
                      />
                      <span>{t('Show in lists')}</span>
                    </label>
                    <label className="checkbox-label">
                      <input
                        type="checkbox"
                        checked={field.required}
                        onChange={(event) => updateField(index, { required: event.target.checked })}
                      />
                      <span>{t('Required for publication')}</span>
                    </label>
                    <label className="checkbox-label">
                      <input
                        type="checkbox"
                        checked={field.publicVisible}
                        onChange={(event) =>
                          updateField(index, {
                            publicVisible: event.target.checked,
                            filterable: event.target.checked && field.filterable,
                          })
                        }
                      />
                      <span>{t('Visible on the website')}</span>
                    </label>
                    <label className="checkbox-label">
                      <input
                        type="checkbox"
                        disabled={
                          !field.publicVisible || ['textarea', 'image'].includes(field.kind)
                        }
                        checked={field.filterable}
                        onChange={(event) =>
                          updateField(index, { filterable: event.target.checked })
                        }
                      />
                      <span>{t('Collection filter')}</span>
                    </label>
                  </div>
                </fieldset>
              ))}
              <p className="field-help">
                {t(
                  'Removing a field from the editor retains its stored values and revision history.',
                )}
              </p>
            </section>
          </div>
          <aside className="editor-side-column">
            <section className="admin-card editor-card">
              <h2>{t('Availability')}</h2>
              <label className="checkbox-label">
                <input
                  type="checkbox"
                  checked={form.data.dedicatedAccess}
                  onChange={(event) => form.setData('dedicatedAccess', event.target.checked)}
                />
                <span>{t('Use a dedicated collection permission')}</span>
              </label>
              <p className="field-help">
                {t('Assign this collection permission to roles that should manage its content.')}
              </p>
              <label className="checkbox-label">
                <input
                  type="checkbox"
                  disabled={definition?.system}
                  checked={form.data.enabled}
                  onChange={(event) => form.setData('enabled', event.target.checked)}
                />
                <span>{t('Collection enabled')}</span>
              </label>
              <label className="checkbox-label">
                <input
                  type="checkbox"
                  checked={form.data.publicVisible}
                  onChange={(event) => form.setData('publicVisible', event.target.checked)}
                />
                <span>{t('Public content')}</span>
              </label>
              <label className="checkbox-label">
                <input
                  type="checkbox"
                  checked={form.data.hasArchive}
                  onChange={(event) => form.setData('hasArchive', event.target.checked)}
                />
                <span>{t('Public archive')}</span>
              </label>
              <p className="field-help">
                {t(
                  'Private collections remain available to authorized administrators and are excluded from public routes.',
                )}
              </p>
              <label htmlFor="type-public-path">{t('Public path')}</label>
              <input
                id="type-public-path"
                value={form.data.publicPath}
                required
                maxLength={60}
                pattern="[a-z0-9]+(-[a-z0-9]+)*"
                onChange={(event) => form.setData('publicPath', event.target.value)}
              />
              <p className="field-help">
                {siteUrl}/{form.data.publicPath}/{'{slug}'}
              </p>
              <p className="field-help">
                {t('Previous collection paths keep redirecting when this address changes.')}
              </p>
            </section>
            <section className="admin-card editor-card">
              <h2>{t('Presentation')}</h2>
              <label htmlFor="type-icon">{t('Navigation icon')}</label>
              <input
                id="type-icon"
                value={form.data.icon}
                maxLength={40}
                onChange={(event) => form.setData('icon', event.target.value)}
              />
              <label htmlFor="type-template">{t('Detail template')}</label>
              <input
                id="type-template"
                value={form.data.template}
                required
                maxLength={80}
                onChange={(event) => form.setData('template', event.target.value)}
              />
              <label htmlFor="type-archive-template">{t('Archive template')}</label>
              <input
                id="type-archive-template"
                value={form.data.archiveTemplate}
                required
                maxLength={80}
                onChange={(event) => form.setData('archiveTemplate', event.target.value)}
              />
              <p className="field-help">
                {t(
                  'Themes can provide these named templates. The standard content view is used when a template is unavailable.',
                )}
              </p>
            </section>
            <section className="admin-card editor-card">
              <h2>{t('Validation')}</h2>
              {(
                [
                  ['minimumTitleLength', 'Minimum title length', 180],
                  ['minimumContentLength', 'Minimum body length', 100000],
                  ['minimumExcerptLength', 'Minimum excerpt length', 500],
                ] as const
              ).map(([key, label, maximum]) => (
                <div key={key}>
                  <label htmlFor={'type-' + key}>{t(label)}</label>
                  <input
                    id={'type-' + key}
                    type="number"
                    min={key === 'minimumTitleLength' ? 1 : 0}
                    max={maximum}
                    value={form.data[key]}
                    onChange={(event) => form.setData(key, Number(event.target.value))}
                  />
                </div>
              ))}
            </section>
            <section className="admin-card editor-card">
              <h2>{t('Interface labels')}</h2>
              {['create', 'edit', 'save', 'title', 'description'].map((key) => (
                <div key={key}>
                  <label htmlFor={'label-' + key}>{t('type.label.' + key)}</label>
                  <input
                    id={'label-' + key}
                    value={form.data.labels[key] || ''}
                    maxLength={300}
                    onChange={(event) =>
                      form.setData('labels', { ...form.data.labels, [key]: event.target.value })
                    }
                  />
                </div>
              ))}
              <p className="field-help">
                {t('Leave labels empty to generate them from the collection name.')}
              </p>
            </section>
            {!isNew && !definition?.system && !definition?.owner && (
              <section className="admin-card editor-card">
                <h2>{t('Remove collection')}</h2>
                <p className="field-help">
                  {t(
                    'Only empty collections without working copies can be removed. Disable a collection to retain its data.',
                  )}
                </p>
                <button
                  className="button button-outline danger"
                  type="button"
                  onClick={() => {
                    if (window.confirm(t('Remove this empty collection definition?')))
                      router.post('/admin/content-types/' + definition?.key + '/delete', {
                        _token: csrfToken,
                      });
                  }}
                >
                  {t('Remove collection')}
                </button>
              </section>
            )}
          </aside>
        </div>
      </form>
    </>
  );
}
ContentTypeEditor.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
