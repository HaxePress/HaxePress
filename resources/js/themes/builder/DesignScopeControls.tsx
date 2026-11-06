import { Link } from '@inertiajs/react';
import { useState } from 'react';
import Icon from '../../components/Icon';
import { useTranslation } from '../../i18n';
import { templateIdentifier, easyPageName } from './easy-controls';
import {
  labelFor,
  scopesFor,
  sectionsFor,
  templateNames,
  visitBlocks,
  type TemplateName,
  type ThemeDocument,
} from './types';

export default function DesignScopeControls({
  document,
  scope,
  friendly = false,
  disabled,
  onScope,
  onChange,
}: {
  document: ThemeDocument;
  scope: string;
  friendly?: boolean;
  disabled: boolean;
  onScope: (scope: string) => void;
  onChange: (change: (document: ThemeDocument) => void) => void;
}) {
  const { t } = useTranslation();
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState('');
  const [identifier, setIdentifier] = useState('');
  const [fallback, setFallback] = useState<TemplateName>('Page');
  const chosenIdentifier = identifier || templateIdentifier(name, document);
  const component = scope.startsWith('@') ? document.components?.[scope.slice(1)] : undefined;
  const metadata = document.templateMeta?.[scope];
  let uses = 0;
  if (component)
    for (const value of scopesFor(document))
      for (const section of sectionsFor(document, value))
        visitBlocks(section.blocks, (node) => {
          if (node.type === 'component' && node.component === scope.slice(1)) uses++;
        });
  const valid =
    name.trim().length > 0 &&
    /^[A-Za-z][A-Za-z0-9_-]{0,79}$/.test(chosenIdentifier) &&
    !chosenIdentifier.startsWith('Admin') &&
    !Object.hasOwn(document.templates, chosenIdentifier) &&
    Object.keys(document.templates).length < 32;
  const label = friendly ? easyPageName(document, scope) : labelFor(document, scope);
  const templates = [
    ...templateNames.filter((name) => Object.hasOwn(document.templates, name)),
    ...Object.keys(document.templates).filter(
      (name) => !templateNames.includes(name as TemplateName),
    ),
  ];
  return (
    <fieldset className="studio-fields studio-scope-controls" disabled={disabled}>
      <div className="studio-scope-heading">
        <label htmlFor="studio-template">
          {t(friendly ? 'Which page do you want to edit?' : 'Template or component')}
        </label>
        <button
          type="button"
          className="icon-button"
          aria-label={t(friendly ? 'New page layout' : 'Create template')}
          aria-expanded={creating}
          onClick={() => setCreating(!creating)}
        >
          <Icon name="plus" />
        </button>
      </div>
      <select id="studio-template" value={scope} onChange={(event) => onScope(event.target.value)}>
        <optgroup label={t(friendly ? 'Pages' : 'Templates')}>
          {templates.map((value) => (
            <option key={value} value={value}>
              {t(friendly ? easyPageName(document, value) : labelFor(document, value))}
            </option>
          ))}
        </optgroup>
        <optgroup label={t('Shared sections')}>
          <option value="header">{t('Header')}</option>
          <option value="footer">{t('Footer')}</option>
        </optgroup>
        {Object.keys(document.components || {}).length > 0 && (
          <optgroup label={t(friendly ? 'Saved parts' : 'Reusable components')}>
            {Object.entries(document.components || {}).map(([id, component]) => (
              <option key={id} value={`@${id}`}>
                {component.name}
              </option>
            ))}
          </optgroup>
        )}
      </select>
      {creating && (
        <form
          className="studio-template-form"
          onSubmit={(event) => {
            event.preventDefault();
            if (!valid || disabled) return;
            onChange((document) => {
              document.templates[chosenIdentifier] = [];
              (document.templateMeta ||= {})[chosenIdentifier] = {
                label: name.trim(),
                fallback,
              };
            });
            onScope(chosenIdentifier);
            setCreating(false);
            setName('');
            setIdentifier('');
          }}
        >
          <label>
            {t(friendly ? 'Page layout name' : 'Template label')}
            <input value={name} maxLength={80} onChange={(event) => setName(event.target.value)} />
          </label>
          <label>
            {t(friendly ? 'What kind of page?' : 'CMS context')}
            <select
              value={fallback}
              onChange={(event) => setFallback(event.target.value as TemplateName)}
            >
              {templateNames.map((value) => (
                <option key={value} value={value}>
                  {t(friendly ? easyPageName(document, value) : labelFor(document, value))}
                </option>
              ))}
            </select>
          </label>
          <details className="studio-control-group" open={!friendly}>
            <summary>{t('Template identifier')}</summary>
            <label>
              {t('Template identifier')}
              <input
                value={identifier}
                placeholder={chosenIdentifier}
                maxLength={80}
                onChange={(event) => setIdentifier(event.target.value)}
              />
            </label>
          </details>
          <p className="studio-help">
            {t('Create a layout here, then choose it for a page or content type in the CMS.')}
          </p>
          <button className="button" type="submit" disabled={!valid}>
            {t(friendly ? 'Create page layout' : 'Create template')}
          </button>
        </form>
      )}
      {(component || metadata) && (
        <details className="studio-control-group studio-scope-settings" key={scope}>
          <summary>{t(component ? 'Saved part settings' : 'Page layout settings')}</summary>
          <label>
            {t(component ? 'Component name' : 'Template label')}
            <input
              value={component ? component.name : metadata!.label}
              maxLength={80}
              onChange={(event) =>
                onChange((document) => {
                  if (component) document.components![scope.slice(1)].name = event.target.value;
                  else document.templateMeta![scope].label = event.target.value;
                })
              }
            />
          </label>
          {metadata && (
            <label>
              {t(friendly ? 'What kind of page?' : 'CMS context')}
              <select
                value={metadata.fallback}
                onChange={(event) =>
                  onChange((document) => {
                    document.templateMeta![scope].fallback = event.target.value as TemplateName;
                  })
                }
              >
                {templateNames.map((value) => (
                  <option key={value} value={value}>
                    {t(friendly ? easyPageName(document, value) : labelFor(document, value))}
                  </option>
                ))}
              </select>
            </label>
          )}
          {uses > 0 && (
            <p className="studio-help">
              {t('Remove component instances before deleting its definition.')}
            </p>
          )}
          <button
            className="studio-text-button danger"
            type="button"
            disabled={uses > 0}
            aria-label={t('Delete {layout}', { layout: label })}
            onClick={() => {
              onChange((document) => {
                if (component) delete document.components?.[scope.slice(1)];
                else {
                  delete document.templates[scope];
                  delete document.templateMeta?.[scope];
                }
              });
              onScope('Home');
            }}
          >
            {t(component ? 'Delete saved part' : 'Delete page layout')}
          </button>
        </details>
      )}
      {friendly && metadata && (
        <Link href="/admin/pages" className="easy-text-button">
          <Icon name="external" />
          {t('Use this layout on a page')}
        </Link>
      )}
    </fieldset>
  );
}
