import { useState } from 'react';
import Icon from '../../components/Icon';
import { useTranslation } from '../../i18n';
import ColorControl from './ColorControl';
import { type DesignFeed, type ThemeDocument } from './types';

export default function DesignSettings({
  document,
  panel,
  collections,
  onChange,
  onClass,
  disabled,
  friendly = false,
}: {
  document: ThemeDocument;
  panel: 'design' | 'sources';
  collections: { key: string; name: string }[];
  onChange: (change: (document: ThemeDocument) => void) => void;
  onClass: (name: string) => void;
  disabled: boolean;
  friendly?: boolean;
}) {
  const { t } = useTranslation();
  const [name, setName] = useState('');
  function feedChange(id: string, values: Partial<DesignFeed>) {
    onChange((document) => {
      const feed = document.feeds?.find((feed) => feed.id === id);
      if (feed) Object.assign(feed, values);
    });
  }
  return (
    <fieldset className="studio-fields" disabled={disabled}>
      {panel === 'design' ? (
        <>
          <div className="studio-panel-heading">
            <h2>{t('Site design')}</h2>
          </div>
          <ColorControl
            label="Background"
            value={document.tokens.background}
            onChange={(background) =>
              onChange((document) => {
                document.tokens.background = background;
              })
            }
          />
          <ColorControl
            label="Text color"
            value={document.tokens.text}
            onChange={(text) =>
              onChange((document) => {
                document.tokens.text = text;
              })
            }
          />
          <ColorControl
            label="Accent color"
            value={document.tokens.accent}
            onChange={(accent) =>
              onChange((document) => {
                document.tokens.accent = accent;
              })
            }
          />
          <label>
            {t('Font family')}
            <input
              list="studio-fonts"
              value={document.tokens.font}
              maxLength={200}
              onChange={(event) =>
                onChange((document) => {
                  document.tokens.font = event.target.value;
                })
              }
            />
            <datalist id="studio-fonts">
              <option value="sans" />
              <option value="serif" />
              <option value="IBM Plex Sans, sans-serif" />
              <option value="system-ui, sans-serif" />
              <option value="Georgia, serif" />
              <option value="monospace" />
            </datalist>
          </label>
          <label>
            {t('Content width')}
            <input
              type="number"
              min={240}
              max={3840}
              value={document.tokens.width}
              onChange={(event) =>
                onChange((document) => {
                  document.tokens.width = Number(event.target.value);
                })
              }
            />
          </label>
          <label>
            {t('Corner radius')}
            <input
              type="number"
              min={0}
              max={200}
              value={document.tokens.radius}
              onChange={(event) =>
                onChange((document) => {
                  document.tokens.radius = Number(event.target.value);
                })
              }
            />
          </label>
          <details className="studio-control-group" open>
            <summary>{t(friendly ? 'Shared appearances' : 'Reusable style classes')}</summary>
            <div className="studio-class-list">
              {Object.keys(document.classes || {}).map((className) => (
                <button type="button" key={className} onClick={() => onClass(className)}>
                  <Icon name="palette" />
                  <code>.{className}</code>
                  <Icon name="edit" />
                </button>
              ))}
            </div>
            <label>
              {t('Class name')}
              <input
                value={name}
                placeholder="content-card"
                maxLength={40}
                onChange={(event) => setName(event.target.value)}
              />
            </label>
            <button
              type="button"
              className="button button-outline"
              disabled={
                !/^[a-z][a-z0-9-]{0,39}$/.test(name) || Object.hasOwn(document.classes || {}, name)
              }
              onClick={() => {
                onChange((document) => {
                  (document.classes ||= {})[name] = {};
                });
                onClass(name);
                setName('');
              }}
            >
              {t('Create style class')}
            </button>
          </details>
          <details className="studio-control-group">
            <summary>{t('Custom CSS')}</summary>
            <p className="studio-help">
              {t(
                'Use :scope for the theme root. Class selectors use the names you assign to elements.',
              )}
            </p>
            <textarea
              className="studio-code-editor"
              aria-label={t('Theme CSS')}
              value={document.css || ''}
              rows={18}
              maxLength={64000}
              spellCheck={false}
              placeholder={
                ':scope {\n  --brand-color: #405bcc;\n}\n\n.content-card:hover {\n  transform: translateY(-4px);\n}'
              }
              onChange={(event) =>
                onChange((document) => {
                  document.css = event.target.value;
                })
              }
            />
          </details>
        </>
      ) : (
        <>
          <div className="studio-panel-heading">
            <h2>{t('Content sources')}</h2>
            <button
              type="button"
              className="icon-button"
              aria-label={t('Add content source')}
              disabled={(document.feeds?.length || 0) >= 8}
              onClick={() =>
                onChange((document) => {
                  (document.feeds ||= []).push({
                    id: crypto.randomUUID(),
                    name: 'Content source',
                    collection: collections[0]?.key || 'entry',
                    limit: 6,
                    category: '',
                    tag: '',
                    query: '',
                    order: 'published_at',
                    direction: 'DESC',
                  });
                })
              }
            >
              <Icon name="plus" />
            </button>
          </div>
          <p className="studio-help">
            {t(
              friendly
                ? 'Choose which content appears in your design. Connect it to a Content cards element.'
                : 'Connect a repeater to a collection. Only sources used by the visible template are queried.',
            )}
          </p>
          <datalist id="studio-collections">
            {collections.map((collection) => (
              <option key={collection.key} value={collection.key}>
                {collection.name}
              </option>
            ))}
          </datalist>
          {(document.feeds || []).map((feed) => (
            <details className="studio-control-group" key={feed.id} open>
              <summary>{feed.name || t('Content source')}</summary>
              <label>
                {t('Source name')}
                <input
                  value={feed.name}
                  maxLength={80}
                  onChange={(event) => feedChange(feed.id, { name: event.target.value })}
                />
              </label>
              <label>
                {t('Collection')}
                <input
                  list="studio-collections"
                  value={feed.collection}
                  maxLength={32}
                  onChange={(event) => feedChange(feed.id, { collection: event.target.value })}
                />
              </label>
              <label>
                {t('Number of records')}
                <input
                  type="number"
                  min={1}
                  max={24}
                  value={feed.limit}
                  onChange={(event) => feedChange(feed.id, { limit: Number(event.target.value) })}
                />
              </label>
              <label>
                {t('Category')}
                <input
                  value={feed.category}
                  maxLength={80}
                  onChange={(event) => feedChange(feed.id, { category: event.target.value })}
                />
              </label>
              <label>
                {t('Tag slug')}
                <input
                  value={feed.tag}
                  maxLength={120}
                  onChange={(event) => feedChange(feed.id, { tag: event.target.value })}
                />
              </label>
              <label>
                {t('Search query')}
                <input
                  value={feed.query}
                  maxLength={120}
                  onChange={(event) => feedChange(feed.id, { query: event.target.value })}
                />
              </label>
              <div className="studio-style-grid">
                <label>
                  {t('Sort by')}
                  <select
                    value={feed.order}
                    onChange={(event) =>
                      feedChange(feed.id, { order: event.target.value as DesignFeed['order'] })
                    }
                  >
                    <option value="published_at">{t('Publication date')}</option>
                    <option value="title">{t('Title')}</option>
                    <option value="id">{t('ID')}</option>
                  </select>
                </label>
                <label>
                  {t('Direction')}
                  <select
                    value={feed.direction}
                    onChange={(event) =>
                      feedChange(feed.id, { direction: event.target.value as 'ASC' | 'DESC' })
                    }
                  >
                    <option value="DESC">{t('Descending')}</option>
                    <option value="ASC">{t('Ascending')}</option>
                  </select>
                </label>
              </div>
              <button
                className="studio-text-button"
                type="button"
                onClick={() =>
                  onChange((document) => {
                    document.feeds = document.feeds?.filter((entry) => entry.id !== feed.id);
                  })
                }
              >
                {t('Remove source')}
              </button>
            </details>
          ))}
          {!document.feeds?.length && (
            <button
              className="button button-outline"
              type="button"
              onClick={() =>
                onChange((document) => {
                  document.feeds = [
                    {
                      id: crypto.randomUUID(),
                      name: 'Content source',
                      collection: collections[0]?.key || 'entry',
                      limit: 6,
                      category: '',
                      tag: '',
                      query: '',
                      order: 'published_at',
                      direction: 'DESC',
                    },
                  ];
                })
              }
            >
              {t('Add content source')}
            </button>
          )}
        </>
      )}
    </fieldset>
  );
}
