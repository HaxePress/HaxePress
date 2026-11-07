import { useEffect, useState } from 'react';
import Icon from '../../components/Icon';
import { useTranslation } from '../../i18n';
import ColorControl from './ColorControl';
import PublicFieldControl, { publicFields } from './PublicFieldControl';
import {
  blockLabels,
  htmlTags,
  type Breakpoint,
  type DesignBlock,
  type DesignSection,
  type Interaction,
  type ResponsiveStyles,
  type StyleMap,
  type ThemeDocument,
} from './types';

export type InspectorPanel = 'content' | 'style' | 'data' | 'advanced';

export interface DesignInspectorProps {
  embedded?: boolean;
  panel?: InspectorPanel;
  friendly?: boolean;
  styleOnly?: boolean;
  document: ThemeDocument;
  section?: DesignSection;
  block?: DesignBlock;
  breakpoint: Breakpoint;
  interaction: Interaction;
  disabled: boolean;
  onInteraction: (state: Interaction) => void;
  onBlock: (values: Partial<DesignBlock>) => void;
  onSection: (values: Partial<DesignSection>) => void;
  onStyle: (property: string, value: string) => void;
  onImage: (background: boolean) => void;
  onParent: () => void;
  onClear: () => void;
  onDuplicate: () => void;
  onDelete: () => void;
  onNudge: (direction: -1 | 1) => void;
  onComponent: () => void;
  onEditComponent: (id: string) => void;
  onConvertList: () => void;
}
const groups: { name: string; fields: [string, string, string[]?][] }[] = [
  {
    name: 'Layout',
    fields: [
      [
        'display',
        'Display',
        ['block', 'flex', 'grid', 'inline', 'inline-block', 'inline-flex', 'none'],
      ],
      ['flex-direction', 'Direction', ['row', 'column', 'row-reverse', 'column-reverse']],
      [
        'justify-content',
        'Justify',
        ['flex-start', 'center', 'flex-end', 'space-between', 'space-around', 'space-evenly'],
      ],
      ['align-items', 'Align items', ['stretch', 'flex-start', 'center', 'flex-end', 'baseline']],
      ['flex-wrap', 'Wrap', ['nowrap', 'wrap', 'wrap-reverse']],
      ['gap', 'Gap'],
      ['row-gap', 'Row gap'],
      ['column-gap', 'Column gap'],
      ['grid-template-columns', 'Grid columns'],
      ['grid-template-rows', 'Grid rows'],
      ['grid-auto-flow', 'Grid flow', ['row', 'column', 'dense']],
      ['grid-column', 'Grid column span'],
      ['grid-row', 'Grid row span'],
      ['order', 'Order'],
      ['flex', 'Flex sizing'],
      ['align-self', 'Align self', ['auto', 'stretch', 'flex-start', 'center', 'flex-end']],
    ],
  },
  {
    name: 'Size',
    fields: [
      ['width', 'Width'],
      ['height', 'Height'],
      ['min-width', 'Minimum width'],
      ['max-width', 'Maximum width'],
      ['min-height', 'Minimum height'],
      ['max-height', 'Maximum height'],
      ['aspect-ratio', 'Aspect ratio'],
      ['overflow', 'Overflow', ['visible', 'hidden', 'auto', 'scroll', 'clip']],
      ['object-fit', 'Image fit', ['cover', 'contain', 'fill', 'none', 'scale-down']],
      ['object-position', 'Image position'],
    ],
  },
  {
    name: 'Typography',
    fields: [
      ['font-family', 'Font family'],
      ['font-size', 'Font size'],
      [
        'font-weight',
        'Font weight',
        ['100', '200', '300', '400', '500', '600', '700', '800', '900'],
      ],
      ['line-height', 'Line height'],
      ['letter-spacing', 'Letter spacing'],
      ['color', 'Text color'],
      ['text-align', 'Text alignment', ['left', 'center', 'right', 'justify']],
      ['text-transform', 'Text transform', ['none', 'uppercase', 'lowercase', 'capitalize']],
      ['text-decoration', 'Text decoration', ['none', 'underline', 'line-through']],
      ['white-space', 'Whitespace', ['normal', 'pre-wrap', 'nowrap', 'pre']],
      ['text-wrap', 'Text wrapping', ['wrap', 'nowrap', 'balance', 'pretty']],
    ],
  },
  {
    name: 'Background and border',
    fields: [
      ['background', 'Background'],
      ['background-color', 'Background color'],
      ['background-size', 'Background size', ['cover', 'contain', 'auto']],
      ['background-position', 'Background position'],
      ['background-repeat', 'Background repeat', ['no-repeat', 'repeat', 'repeat-x', 'repeat-y']],
      ['border', 'Border'],
      ['border-radius', 'Corner radius'],
      ['border-color', 'Border color'],
      ['border-width', 'Border width'],
      ['border-style', 'Border style', ['none', 'solid', 'dashed', 'dotted', 'double']],
      ['box-shadow', 'Shadow'],
    ],
  },
  {
    name: 'Position',
    fields: [
      ['position', 'Position', ['static', 'relative', 'absolute', 'fixed', 'sticky']],
      ['top', 'Top'],
      ['right', 'Right'],
      ['bottom', 'Bottom'],
      ['left', 'Left'],
      ['z-index', 'Stacking order'],
      ['inset', 'Inset'],
    ],
  },
  {
    name: 'Effects',
    fields: [
      ['opacity', 'Opacity'],
      ['transform', 'Transform'],
      ['transform-origin', 'Transform origin'],
      ['transition', 'Transition'],
      ['filter', 'Filter'],
      ['backdrop-filter', 'Backdrop filter'],
      ['mix-blend-mode', 'Blend mode'],
      ['cursor', 'Cursor'],
      ['pointer-events', 'Pointer events', ['auto', 'none']],
    ],
  },
];
function Attributes({
  value,
  onChange,
}: {
  value: Record<string, string>;
  onChange: (value: Record<string, string>) => void;
}) {
  const { t } = useTranslation();
  const [text, setText] = useState(JSON.stringify(value, null, 2));
  const [error, setError] = useState('');
  const serialized = JSON.stringify(value);
  useEffect(() => setText(JSON.stringify(value, null, 2)), [serialized]);
  return (
    <label>
      {t('HTML attributes')}
      <textarea
        rows={5}
        value={text}
        spellCheck={false}
        onChange={(event) => setText(event.target.value)}
        onBlur={() => {
          try {
            const parsed = JSON.parse(text);
            if (
              !parsed ||
              typeof parsed !== 'object' ||
              Array.isArray(parsed) ||
              Object.values(parsed).some((value) => typeof value !== 'string')
            )
              throw new Error();
            onChange(parsed);
            setError('');
          } catch {
            setError('Enter a JSON object with text values.');
          }
        }}
      />
      {error && <small role="alert">{t(error)}</small>}
    </label>
  );
}

export default function DesignInspector(props: DesignInspectorProps) {
  const { t } = useTranslation();
  const {
    section,
    block,
    document,
    breakpoint,
    interaction,
    onStyle,
    onBlock,
    onSection,
    disabled,
  } = props;
  const [tab, setTab] = useState<'content' | 'style' | 'data' | 'advanced'>('content');
  useEffect(() => {
    const editableContent =
      block &&
      [
        'heading',
        'text',
        'image',
        'button',
        'element',
        'component',
        'extension',
        'content-list',
      ].includes(block.type);
    setTab(
      props.styleOnly
        ? 'style'
        : block?.type === 'repeat'
          ? 'data'
          : editableContent
            ? 'content'
            : 'style',
    );
  }, [block?.id, section?.id, props.styleOnly]);
  const [property, setProperty] = useState('');
  const [propertyValue, setPropertyValue] = useState('');
  const target = block || section;
  const styles: ResponsiveStyles = target?.styles || {};
  const values: StyleMap = styles[breakpoint]?.[interaction] || {};
  if (!section)
    return (
      <div className="studio-inspector-empty">
        <Icon name="cursor" />
        <p>{t('Select any element in the canvas or the layer tree.')}</p>
      </div>
    );
  function field(property: string, label: string, options?: string[]) {
    const value = values[property] || '';
    return (
      <label key={property}>
        {t(label)}
        {options ? (
          <select value={value} onChange={(event) => onStyle(property, event.target.value)}>
            <option value="">{t('Inherit')}</option>
            {options.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        ) : (
          <input
            value={value}
            maxLength={2000}
            placeholder={t('Inherit')}
            onChange={(event) => onStyle(property, event.target.value)}
          />
        )}
      </label>
    );
  }
  function patchClasses(value: string[]) {
    if (block) onBlock({ classes: value });
    else onSection({ classes: value });
  }
  function binding(field: string, label: string) {
    if (props.friendly)
      return (
        <PublicFieldControl
          key={field}
          label={label}
          value={block?.bindings?.[field] || ''}
          onChange={(value) => onBlock({ bindings: { ...block?.bindings, [field]: value } })}
        />
      );
    return (
      <label key={field}>
        {t(label)}
        <input
          list="studio-binding-fields"
          value={block?.bindings?.[field] || ''}
          placeholder="item.fields.custom_field"
          maxLength={120}
          onChange={(event) =>
            onBlock({ bindings: { ...block?.bindings, [field]: event.target.value } })
          }
        />
      </label>
    );
  }
  const requestedTab = props.panel || tab;
  const selectedTab =
    props.styleOnly && (requestedTab === 'content' || requestedTab === 'data')
      ? 'style'
      : requestedTab;
  const tabs = props.styleOnly
    ? (['style', 'advanced'] as const)
    : (['content', 'style', 'data', 'advanced'] as const);
  const title = block ? block.name || t(blockLabels[block.type]) : section.name || t('Section');
  return (
    <>
      {!props.embedded && (
        <>
          <div className="studio-panel-heading">
            <h2 title={title}>{title}</h2>
            <button
              className="icon-button"
              type="button"
              aria-label={t('Clear selection')}
              onClick={props.onClear}
            >
              <Icon name="x" />
            </button>
          </div>
          <div className="studio-selection-actions">
            <button
              type="button"
              className="icon-button"
              aria-label={t('Move up')}
              title={t('Move up')}
              disabled={disabled || props.styleOnly}
              onClick={() => props.onNudge(-1)}
            >
              <Icon name="arrow-up" />
            </button>
            <button
              type="button"
              className="icon-button"
              aria-label={t('Move down')}
              title={t('Move down')}
              disabled={disabled || props.styleOnly}
              onClick={() => props.onNudge(1)}
            >
              <Icon name="arrow-down" />
            </button>
            <button
              type="button"
              className="icon-button"
              aria-label={t('Duplicate')}
              title={t('Duplicate')}
              disabled={disabled || props.styleOnly}
              onClick={props.onDuplicate}
            >
              <Icon name="copy" />
            </button>
            <button
              type="button"
              className="icon-button danger"
              aria-label={t('Delete selected')}
              title={t('Delete selected')}
              disabled={disabled}
              onClick={props.onDelete}
            >
              <Icon name="trash" />
            </button>
          </div>
          <div className="studio-property-tabs" role="tablist" aria-label={t('Element properties')}>
            {tabs.map((value) => (
              <button
                role="tab"
                type="button"
                key={value}
                aria-selected={selectedTab === value}
                onClick={() => setTab(value)}
              >
                {t(
                  value === 'content'
                    ? 'Content'
                    : value === 'style'
                      ? 'Style'
                      : value === 'data'
                        ? 'Data'
                        : 'Advanced',
                )}
              </button>
            ))}
          </div>
        </>
      )}
      <fieldset className="studio-fields" disabled={disabled}>
        {selectedTab === 'content' && (
          <>
            <label>
              {t(block ? 'Element name' : 'Section name')}
              <input
                value={block ? block.name || '' : section.name}
                maxLength={80}
                onChange={(event) =>
                  block
                    ? onBlock({ name: event.target.value })
                    : onSection({ name: event.target.value })
                }
              />
            </label>
            {block ? (
              <>
                {['heading', 'text', 'button', 'element'].includes(block.type) && (
                  <label>
                    {t('Text')}
                    <textarea
                      rows={5}
                      maxLength={16000}
                      value={block.text}
                      onChange={(event) => onBlock({ text: event.target.value })}
                    />
                  </label>
                )}
                {['button', 'heading', 'image', 'element'].includes(block.type) && (
                  <label>
                    {t('Link')}
                    <input
                      value={block.href}
                      maxLength={500}
                      placeholder="/content"
                      onChange={(event) => onBlock({ href: event.target.value })}
                    />
                  </label>
                )}
                {(['button', 'heading', 'image'].includes(block.type) ||
                  (block.type === 'element' && block.tag === 'a')) && (
                  <label className="studio-check">
                    <input
                      type="checkbox"
                      checked={block.newTab === true}
                      onChange={(event) => onBlock({ newTab: event.target.checked })}
                    />
                    <span>{t('Open in a new tab')}</span>
                  </label>
                )}
                {block.type === 'heading' && (
                  <label>
                    {t('Heading level')}
                    <select
                      value={block.level}
                      onChange={(event) => onBlock({ level: Number(event.target.value) })}
                    >
                      {[1, 2, 3, 4, 5, 6].map((level) => (
                        <option key={level} value={level}>
                          H{level}
                        </option>
                      ))}
                    </select>
                  </label>
                )}
                {block.type === 'element' && (
                  <label>
                    {t('HTML tag')}
                    <select
                      value={block.tag || 'div'}
                      onChange={(event) => onBlock({ tag: event.target.value })}
                    >
                      {htmlTags.map((tag) => (
                        <option key={tag} value={tag}>
                          {tag}
                        </option>
                      ))}
                    </select>
                  </label>
                )}
                {block.type === 'image' && (
                  <>
                    <div className="studio-image-preview">
                      {block.image ? (
                        <img src={block.image} alt={block.alt} />
                      ) : (
                        <Icon name="image" />
                      )}
                    </div>
                    <button
                      className="button button-outline"
                      type="button"
                      onClick={() => props.onImage(false)}
                    >
                      {t('Choose or upload image')}
                    </button>
                    {block.image && (
                      <button
                        type="button"
                        className="studio-text-button"
                        onClick={() => onBlock({ image: '', alt: '' })}
                      >
                        {t('Remove image')}
                      </button>
                    )}
                    <label>
                      {t('Alternative text')}
                      <input
                        value={block.alt}
                        maxLength={240}
                        onChange={(event) => onBlock({ alt: event.target.value })}
                      />
                    </label>
                  </>
                )}
                {block.type === 'spacer' && (
                  <label>
                    {t('Space size')}
                    <select
                      value={block.level}
                      onChange={(event) => onBlock({ level: Number(event.target.value) })}
                    >
                      {[1, 2, 3, 4, 5, 6].map((value) => (
                        <option key={value} value={value}>
                          {value * 16}px
                        </option>
                      ))}
                    </select>
                  </label>
                )}
                {block.type === 'component' && (
                  <>
                    <label>
                      {t('Reusable component')}
                      <select
                        value={block.component || ''}
                        onChange={(event) => onBlock({ component: event.target.value })}
                      >
                        <option value="">{t('Choose a component')}</option>
                        {Object.entries(document.components || {}).map(([id, component]) => (
                          <option key={id} value={id}>
                            {component.name}
                          </option>
                        ))}
                      </select>
                    </label>
                    {block.component && (
                      <button
                        className="button button-outline"
                        type="button"
                        onClick={() => props.onEditComponent(block.component!)}
                      >
                        {t('Edit component')}
                      </button>
                    )}
                  </>
                )}
                {block.type === 'extension' && (
                  <label>
                    {t('Plugin slot')}
                    <input
                      value={block.slot || ''}
                      placeholder="site.footer"
                      maxLength={80}
                      onChange={(event) => onBlock({ slot: event.target.value })}
                    />
                  </label>
                )}
                {block.type === 'content-list' && (
                  <>
                    <p className="studio-help">
                      {t('Convert this list to edit the complete card layout.')}
                    </p>
                    <button
                      className="button button-outline"
                      type="button"
                      onClick={props.onConvertList}
                    >
                      {t('Customize card layout')}
                    </button>
                  </>
                )}
                {!props.embedded && (
                  <button type="button" className="studio-text-button" onClick={props.onParent}>
                    {t('Select parent')}
                  </button>
                )}
              </>
            ) : (
              <>
                <ColorControl
                  label="Background"
                  value={section.background}
                  optional
                  onChange={(background) => onSection({ background })}
                />
                <ColorControl
                  label="Text color"
                  value={section.color}
                  optional
                  onChange={(color) => onSection({ color })}
                />
                <label>
                  {t('Content width')}
                  <select
                    value={section.width}
                    onChange={(event) =>
                      onSection({ width: event.target.value as DesignSection['width'] })
                    }
                  >
                    <option value="content">{t('Content width')}</option>
                    <option value="wide">{t('Wide')}</option>
                    <option value="full">{t('Full width')}</option>
                  </select>
                </label>
                <label>
                  {t('Columns')}
                  <input
                    type="number"
                    min={1}
                    max={24}
                    value={section.columns}
                    onChange={(event) => onSection({ columns: Number(event.target.value) })}
                  />
                </label>
                <label>
                  {t('Vertical spacing')}
                  <input
                    type="number"
                    min={0}
                    max={2000}
                    value={section.padding}
                    onChange={(event) => onSection({ padding: Number(event.target.value) })}
                  />
                </label>
              </>
            )}
            {!props.embedded && (
              <button className="button button-outline" type="button" onClick={props.onComponent}>
                <Icon name="puzzle" />
                {t('Save as component')}
              </button>
            )}
          </>
        )}
        {(selectedTab === 'style' || selectedTab === 'advanced') && (
          <>
            {!props.embedded && (
              <div className="studio-style-context">
                <strong>
                  {t(
                    breakpoint === 'desktop'
                      ? 'Desktop default'
                      : breakpoint === 'tablet'
                        ? 'Tablet override'
                        : 'Mobile override',
                  )}
                </strong>
                <select
                  aria-label={t('Interaction state')}
                  value={interaction}
                  onChange={(event) => props.onInteraction(event.target.value as Interaction)}
                >
                  <option value="normal">{t('Normal')}</option>
                  <option value="hover">{t('Hover')}</option>
                  <option value="focus">{t('Focus')}</option>
                </select>
              </div>
            )}
            {selectedTab === 'style' && (
              <>
                {groups.map((group) => (
                  <details
                    className="studio-control-group"
                    key={group.name}
                    open={!props.friendly && ['Layout', 'Size'].includes(group.name)}
                  >
                    <summary>{t(group.name)}</summary>
                    <div className="studio-style-grid">
                      {group.fields.map(([property, label, options]) =>
                        field(property, label, options),
                      )}
                    </div>
                    {group.name === 'Background and border' && (
                      <button
                        className="button button-outline"
                        type="button"
                        onClick={() => props.onImage(true)}
                      >
                        {t('Background image')}
                      </button>
                    )}
                  </details>
                ))}
                <details className="studio-control-group" open={!props.friendly}>
                  <summary>{t('Spacing')}</summary>
                  {['padding', 'margin'].map((prefix) => (
                    <div className="studio-spacing" key={prefix}>
                      <strong>{t(prefix === 'padding' ? 'Padding' : 'Margin')}</strong>
                      <div>
                        {['top', 'right', 'bottom', 'left'].map((side) =>
                          field(
                            `${prefix}-${side}`,
                            `${side.charAt(0).toUpperCase()}${side.slice(1)}`,
                          ),
                        )}
                      </div>
                    </div>
                  ))}
                </details>
              </>
            )}
            {selectedTab === 'advanced' && (
              <>
                {block?.type === 'element' && (
                  <Attributes
                    value={block.attributes || {}}
                    onChange={(attributes) => onBlock({ attributes })}
                  />
                )}
                {props.friendly ? (
                  <div
                    className="easy-class-choices"
                    role="group"
                    aria-label={t('Shared appearances')}
                  >
                    <span>{t('Shared appearances')}</span>
                    {Object.keys(document.classes || {}).map((name) => (
                      <label key={name}>
                        <input
                          type="checkbox"
                          checked={target?.classes?.includes(name) || false}
                          onChange={(event) =>
                            patchClasses(
                              event.target.checked
                                ? [...(target?.classes || []), name]
                                : (target?.classes || []).filter((value) => value !== name),
                            )
                          }
                        />
                        <span>{name}</span>
                      </label>
                    ))}
                  </div>
                ) : (
                  <label>
                    {t('Reusable style classes')}
                    <select
                      multiple
                      value={target?.classes || []}
                      onChange={(event) =>
                        patchClasses(
                          Array.from(event.target.selectedOptions, (option) => option.value),
                        )
                      }
                    >
                      {Object.keys(document.classes || {}).map((name) => (
                        <option key={name} value={name}>
                          {name}
                        </option>
                      ))}
                    </select>
                  </label>
                )}
                <p className="studio-help">
                  {t(
                    props.friendly
                      ? 'Create shared appearances in Look and feel, then choose them here.'
                      : 'Classes can be created and edited in the Design panel.',
                  )}
                </p>
                <details className="studio-control-group" open>
                  <summary>{t('All CSS properties')}</summary>
                  <div className="studio-css-properties">
                    {Object.entries(values).map(([key, value]) => (
                      <label key={key}>
                        <code>{key}</code>
                        <span>
                          <input
                            aria-label={key}
                            value={value}
                            onChange={(event) => onStyle(key, event.target.value)}
                          />
                          <button
                            className="icon-button"
                            type="button"
                            aria-label={t('Remove {property}', { property: key })}
                            onClick={() => onStyle(key, '')}
                          >
                            <Icon name="x" />
                          </button>
                        </span>
                      </label>
                    ))}
                  </div>
                  <label>
                    {t('CSS property')}
                    <input
                      value={property}
                      onChange={(event) => setProperty(event.target.value)}
                      placeholder="clip-path"
                    />
                  </label>
                  <label>
                    {t('CSS value')}
                    <input
                      value={propertyValue}
                      onChange={(event) => setPropertyValue(event.target.value)}
                      placeholder="polygon(0 0, 100% 0, 80% 100%, 0 100%)"
                    />
                  </label>
                  <button
                    type="button"
                    className="button button-outline"
                    disabled={
                      !/^(--[A-Za-z][A-Za-z0-9-]*|-?[a-z][a-z0-9-]*)$/.test(property) ||
                      !propertyValue
                    }
                    onClick={() => {
                      onStyle(property, propertyValue);
                      setProperty('');
                      setPropertyValue('');
                    }}
                  >
                    {t('Apply property')}
                  </button>
                </details>
              </>
            )}
          </>
        )}
        {selectedTab === 'data' && block && (
          <>
            <datalist id="studio-binding-fields">
              {publicFields.map(([field, name]) => (
                <option key={field} value={field} label={t(name)} />
              ))}
            </datalist>
            <p className="studio-help">
              {t(
                props.friendly
                  ? 'Choose a CMS field to keep this element up to date automatically.'
                  : 'Bind values to public CMS fields. Custom fields use item.fields.field_name.',
              )}
            </p>
            {['heading', 'text', 'button', 'element'].includes(block.type) &&
              binding('text', 'Text field')}
            {['heading', 'button', 'image', 'element'].includes(block.type) &&
              binding('href', 'Link field')}
            {block.type === 'image' && (
              <>
                {binding('image', 'Image field')}
                {binding('alt', 'Alternative text field')}
              </>
            )}
            {block.type === 'element' && (
              <>
                {binding('value', 'Input value field')}
                {binding('datetime', 'Date field')}
              </>
            )}
            {block.type === 'repeat' && (
              <>
                <label>
                  {t('Content source')}
                  <select
                    value={block.source || 'page.items'}
                    onChange={(event) => onBlock({ source: event.target.value })}
                  >
                    <option value="page.items">{t('Current page content')}</option>
                    <option value="page.related">{t('Related content')}</option>
                    {(document.feeds || []).map((feed) => (
                      <option key={feed.id} value={`feed:${feed.id}`}>
                        {feed.name || feed.collection}
                      </option>
                    ))}
                  </select>
                </label>
                <p className="studio-help">
                  {t(
                    props.friendly
                      ? 'Design one card. It repeats for each matching content item.'
                      : 'Every child is repeated for each record. Bind its elements to item fields.',
                  )}
                </p>
              </>
            )}
            <details className="studio-control-group" open>
              <summary>
                {t(props.friendly ? 'Show or hide automatically' : 'Conditional visibility')}
              </summary>
              {props.friendly ? (
                <PublicFieldControl
                  label="Show based on"
                  value={block.condition?.field || ''}
                  onChange={(field) =>
                    onBlock({
                      condition: {
                        field,
                        operator: block.condition?.operator || 'present',
                        value: block.condition?.value || '',
                      },
                    })
                  }
                />
              ) : (
                <label>
                  {t('Field')}
                  <input
                    list="studio-binding-fields"
                    value={block.condition?.field || ''}
                    maxLength={120}
                    onChange={(event) =>
                      onBlock({
                        condition: {
                          field: event.target.value,
                          operator: block.condition?.operator || 'present',
                          value: block.condition?.value || '',
                        },
                      })
                    }
                  />
                </label>
              )}
              <label>
                {t('Condition')}
                <select
                  value={block.condition?.operator || 'present'}
                  onChange={(event) =>
                    onBlock({
                      condition: {
                        field: block.condition?.field || '',
                        operator: event.target.value as 'present' | 'empty' | 'equals',
                        value: block.condition?.value || '',
                      },
                    })
                  }
                >
                  <option value="present">{t('Has a value')}</option>
                  <option value="empty">{t('Is empty')}</option>
                  <option value="equals">{t('Equals')}</option>
                </select>
              </label>
              {block.condition?.operator === 'equals' && (
                <label>
                  {t('Value')}
                  <input
                    value={block.condition.value}
                    maxLength={500}
                    onChange={(event) =>
                      onBlock({ condition: { ...block.condition!, value: event.target.value } })
                    }
                  />
                </label>
              )}
            </details>
          </>
        )}
        {selectedTab === 'data' && !block && (
          <p className="studio-help">
            {t('Select an element to bind CMS fields or configure a repeater.')}
          </p>
        )}
      </fieldset>
    </>
  );
}
