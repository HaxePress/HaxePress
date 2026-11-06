import { Link, usePage } from '../../page';
import type { SharedProps } from '../../types';
import { useState, useEffect } from 'react';
import type { ReactNode } from 'react';
import { useTranslation } from '../../i18n';
import Icon from '../../components/Icon';
import { editableText, friendlyLabel } from './friendly-presets';
import type { DesignDrag, DesignSelection, StyleMap } from './types';
import DesignInspector, { type DesignInspectorProps, type InspectorPanel } from './DesignInspector';
import EasyArrangement from './EasyArrangement';
import EasyMove from './EasyMove';
import { effectiveStyles } from './easy-controls';

function Options({ title, icon, children }: { title: string; icon: string; children: ReactNode }) {
  const { t } = useTranslation();
  const [open, setOpen] = useState(false);
  return (
    <details
      className="easy-detail-group"
      open={open}
      onToggle={(event) => setOpen(event.currentTarget.open)}
    >
      <summary>
        <Icon name={icon} />
        {t(title)}
      </summary>
      {open && children}
    </details>
  );
}

interface EasyInspectorProps extends DesignInspectorProps {
  selection: DesignSelection | null;
  onQuickStyle: (property: string, value: string) => void;
  onStyles: (values: StyleMap) => void;
  onReset: () => void;
  onMove: (source: DesignDrag, target: DesignDrag) => void;
  onAdd: () => void;
  onSelect: (block: string) => void;
}

export default function EasyInspector(props: EasyInspectorProps) {
  const {
    section,
    block,
    disabled,
    onBlock,
    onSection,
    onQuickStyle: onStyle,
    onImage,
    onSelect,
    onClear,
    onDuplicate,
    onDelete,
    document,
    breakpoint,
    interaction,
  } = props;
  const { t } = useTranslation();
  const { primaryArchive } = usePage<SharedProps>().props;
  const destinations = [
    { value: '/', label: 'Home page' },
    { value: '/about', label: 'About page' },
    { value: primaryArchive || '/content', label: 'All content' },
  ];
  const [customLink, setCustomLink] = useState(false);
  useEffect(
    () =>
      setCustomLink(
        Boolean(block?.href) &&
          !destinations.some((destination) => destination.value === block?.href),
      ),
    [block?.id],
  );
  if (!section)
    return (
      <div className="easy-inspector-intro">
        <span className="easy-pointer">
          <Icon name="cursor" />
        </span>
        <h2>{t('Click something to change it')}</h2>
        <p>{t('Choose a title, picture or section in the page. Its options will appear here.')}</p>
        <div className="easy-quick-tip">
          <Icon name="edit" />
          <p>{t('Double-click words on the page to edit them directly.')}</p>
        </div>
      </div>
    );
  const title = block ? friendlyLabel(block) : section.name || 'Section';
  const values = effectiveStyles(document, block || section, breakpoint, interaction);
  const bound = Boolean(
    block?.bindings?.text ||
    [
      'content-title',
      'content-excerpt',
      'content-body',
      'site-description',
      'content-image',
    ].includes(block?.type || ''),
  );
  const siteBound =
    block?.type === 'site-description' ||
    block?.bindings?.text?.startsWith('site.') ||
    block?.bindings?.image?.startsWith('site.');
  const children = block?.children || [];
  const optionPanels: { panel: InspectorPanel; title: string; icon: string }[] = props.styleOnly
    ? [
        { panel: 'style', title: 'All appearance settings', icon: 'palette' },
        { panel: 'advanced', title: 'Style properties', icon: 'code' },
      ]
    : [
        { panel: 'content', title: 'Content and links', icon: 'file' },
        { panel: 'style', title: 'All appearance settings', icon: 'palette' },
        { panel: 'data', title: 'Connect to your content', icon: 'database' },
        { panel: 'advanced', title: 'Attributes and custom styles', icon: 'code' },
      ];
  function color(label: string, value: string, change: (value: string) => void) {
    return (
      <label className="easy-color">
        <span>{t(label)}</span>
        <input
          type="color"
          aria-label={t(label)}
          value={/^#[0-9a-f]{6}$/i.test(value) ? value : '#1d2939'}
          onChange={(event) => change(event.target.value)}
        />
      </label>
    );
  }
  return (
    <>
      <div className="easy-panel-title">
        <h2>{t(title)}</h2>
        <button
          className="icon-button"
          type="button"
          aria-label={t('Back to page')}
          onClick={onClear}
        >
          <Icon name="x" />
        </button>
      </div>
      <div className="easy-edit-context">
        <strong>
          <Icon name={breakpoint} />
          {t(breakpoint === 'desktop' ? 'Desktop' : breakpoint === 'tablet' ? 'Tablet' : 'Mobile')}
        </strong>
        <select
          aria-label={t('When does this look apply?')}
          value={interaction}
          onChange={(event) => props.onInteraction(event.target.value as typeof interaction)}
        >
          <option value="normal">{t('Normal appearance')}</option>
          <option value="hover">{t('When pointed at')}</option>
          <option value="focus">{t('When focused')}</option>
        </select>
      </div>
      <p className="easy-help">
        {t(
          breakpoint === 'desktop'
            ? 'Appearance changes apply to all screens unless a smaller screen has its own setting.'
            : 'Appearance changes here only affect this screen size and smaller screens.',
        )}
      </p>
      <fieldset className="easy-controls" disabled={disabled}>
        {!block && !props.styleOnly && (
          <>
            <label>
              {t('Section name')}
              <input
                value={section.name}
                maxLength={80}
                onChange={(event) => onSection({ name: event.target.value })}
              />
            </label>
            <div
              className="easy-choice-label"
              role="group"
              aria-label={t('Space around the section')}
            >
              {t('Space around the section')}
              <span className="easy-choice-row">
                {[
                  { name: 'Less', value: 24 },
                  { name: 'Normal', value: 48 },
                  { name: 'More', value: 80 },
                ].map((option) => (
                  <button
                    type="button"
                    key={option.value}
                    aria-pressed={
                      (values['padding-block'] || `${section.padding}px`) === `${option.value}px`
                    }
                    onClick={() => onStyle('padding-block', `${option.value}px`)}
                  >
                    {t(option.name)}
                  </button>
                ))}
              </span>
            </div>
            {color(
              'Section background',
              values.background || section.background || '#ffffff',
              (background) => onStyle('background', background),
            )}
            <button
              className="easy-text-button"
              type="button"
              onClick={() => onStyle('background', 'transparent')}
            >
              {t('Use the page background')}
            </button>
          </>
        )}
        {block && editableText(block) && (
          <>
            <label>
              {t(block.type === 'button' ? 'Button text' : 'Words on the page')}
              <textarea
                rows={block.type === 'button' || friendlyLabel(block) === 'Heading' ? 2 : 5}
                maxLength={16000}
                value={block.text}
                onChange={(event) => onBlock({ text: event.target.value })}
              />
            </label>
            <p className="easy-help">
              {t('You can also double-click these words in the preview.')}
            </p>
            {block.type === 'button' && (
              <>
                <label>
                  {t('Where should the button go?')}
                  <select
                    value={customLink ? 'custom' : block.href || '/about'}
                    onChange={(event) => {
                      if (event.target.value === 'custom') setCustomLink(true);
                      else {
                        setCustomLink(false);
                        onBlock({ href: event.target.value });
                      }
                    }}
                  >
                    {destinations.map((destination) => (
                      <option key={destination.label} value={destination.value}>
                        {t(destination.label)}
                      </option>
                    ))}
                    <option value="custom">{t('Another web address')}</option>
                  </select>
                </label>
                {customLink && (
                  <label>
                    {t('Web address')}
                    <input
                      value={block.href}
                      maxLength={500}
                      placeholder="https://example.com"
                      onChange={(event) => onBlock({ href: event.target.value })}
                    />
                  </label>
                )}
              </>
            )}
            <div className="easy-choice-label" role="group" aria-label={t('Text size')}>
              {t('Text size')}
              <span className="easy-choice-row">
                {(block.type === 'heading'
                  ? [
                      { name: 'Small', value: '32px' },
                      { name: 'Medium', value: '48px' },
                      { name: 'Large', value: '72px' },
                    ]
                  : [
                      { name: 'Small', value: '14px' },
                      { name: 'Medium', value: '18px' },
                      { name: 'Large', value: '24px' },
                    ]
                ).map((option) => (
                  <button
                    type="button"
                    key={option.name}
                    aria-pressed={values['font-size'] === option.value}
                    onClick={() => onStyle('font-size', option.value)}
                  >
                    {t(option.name)}
                  </button>
                ))}
              </span>
            </div>
            <div className="easy-choice-label" role="group" aria-label={t('Place the text')}>
              {t('Place the text')}
              <span className="easy-choice-row">
                {['left', 'center', 'right'].map((value) => (
                  <button
                    type="button"
                    key={value}
                    aria-label={t(
                      value === 'left'
                        ? 'Align left'
                        : value === 'center'
                          ? 'Center text'
                          : 'Align right',
                    )}
                    aria-pressed={values['text-align'] === value}
                    onClick={() => onStyle('text-align', value)}
                  >
                    <Icon
                      name={
                        value === 'center'
                          ? 'align-center'
                          : value === 'right'
                            ? 'align-right'
                            : 'align-left'
                      }
                    />
                  </button>
                ))}
              </span>
            </div>
            {color('Text color', values.color || document.tokens.text, (value) =>
              onStyle('color', value),
            )}
          </>
        )}
        {block?.type === 'image' && !block.bindings?.image && (
          <>
            <div className="easy-photo">
              {block.image ? (
                <img src={block.image} alt={block.alt} />
              ) : (
                <>
                  <Icon name="image" />
                  <span>{t('Choose your picture')}</span>
                </>
              )}
            </div>
            <button className="button" type="button" onClick={() => onImage(false)}>
              <Icon name="image" />
              {t(block.image ? 'Change picture' : 'Choose a picture')}
            </button>
            <label>
              {t('Describe this picture')}
              <input
                aria-label={t('Describe this picture')}
                value={block.alt}
                maxLength={240}
                onChange={(event) => onBlock({ alt: event.target.value })}
              />
              <small>{t('A short description helps people who cannot see the image.')}</small>
            </label>
            <div className="easy-choice-label" role="group" aria-label={t('Picture corners')}>
              {t('Picture corners')}
              <span className="easy-choice-row">
                {[
                  { name: 'Square', value: '0px' },
                  { name: 'Soft', value: '12px' },
                  { name: 'Round', value: '32px' },
                ].map((option) => (
                  <button
                    type="button"
                    key={option.name}
                    aria-pressed={values['border-radius'] === option.value}
                    onClick={() => onStyle('border-radius', option.value)}
                  >
                    {t(option.name)}
                  </button>
                ))}
              </span>
            </div>
          </>
        )}
        {block?.type === 'brand' && (
          <div className="easy-connected">
            <Icon name="settings" />
            <h3>{t('Your site name and logo')}</h3>
            <p>{t('Change these once in Site settings and they update everywhere.')}</p>
            <Link className="button button-outline" href="/admin/settings">
              {t('Open Site settings')}
            </Link>
          </div>
        )}
        {(bound || block?.bindings?.image) && (
          <div className="easy-connected">
            <Icon name="link" />
            <h3>{t(siteBound ? 'Site settings' : 'This comes from your content')}</h3>
            <p>
              {t(
                siteBound
                  ? 'Change these once in Site settings and they update everywhere.'
                  : 'Edit the original content and this part updates automatically.',
              )}
            </p>
            <Link
              className="button button-outline"
              href={siteBound ? '/admin/settings' : '/admin/collections'}
            >
              {t(siteBound ? 'Open Site settings' : 'Manage content')}
            </Link>
          </div>
        )}
        {block && ['repeat', 'content-list'].includes(block.type) && (
          <>
            <p className="easy-help">{t('Your published content appears here automatically.')}</p>
            <div className="easy-choice-label" role="group" aria-label={t('How should it look?')}>
              {t('How should it look?')}
              <span className="easy-choice-row">
                <button
                  type="button"
                  onClick={() => onStyle('grid-template-columns', 'repeat(3, minmax(0, 1fr))')}
                >
                  {t('Cards')}
                </button>
                <button
                  type="button"
                  onClick={() => onStyle('grid-template-columns', 'minmax(0, 1fr)')}
                >
                  {t('One column')}
                </button>
              </span>
            </div>
            <Link className="easy-text-button" href="/admin/collections">
              {t('Add or edit content')}
            </Link>
          </>
        )}
        {children.length > 0 && (
          <div className="easy-part-list">
            <h3>{t('Change something inside')}</h3>
            {children.map((child) => (
              <button key={child.id} type="button" onClick={() => onSelect(child.id)}>
                <Icon name={child.type === 'image' ? 'image' : 'edit'} />
                <span>{child.text || t(friendlyLabel(child))}</span>
                <Icon name="chevron-right" />
              </button>
            ))}
          </div>
        )}
        {block?.type === 'navigation' && (
          <div className="easy-connected">
            <Icon name="menu" />
            <p>{t('Choose the links people use to move around your website.')}</p>
            <Link className="button button-outline" href="/admin/navigation">
              {t('Edit menu links')}
            </Link>
          </div>
        )}
        {block && (
          <button className="easy-text-button" type="button" onClick={props.onParent}>
            <Icon name="arrow-up" />
            {t('Choose the surrounding group')}
          </button>
        )}
        {!props.styleOnly && (
          <div className="easy-selection-tools">
            <button className="button button-outline" type="button" onClick={props.onAdd}>
              <Icon name="plus" />
              {t('Add an element here')}
            </button>
            <div className="easy-choice-row">
              <button type="button" onClick={() => props.onNudge(-1)}>
                <Icon name="arrow-up" />
                {t('Move up')}
              </button>
              <button type="button" onClick={() => props.onNudge(1)}>
                <Icon name="arrow-down" />
                {t('Move down')}
              </button>
            </div>
          </div>
        )}
        <EasyArrangement
          values={values}
          onStyle={props.onStyle}
          onStyles={props.onStyles}
          onImage={() => onImage(true)}
        />
        {optionPanels.map((option) => (
          <Options
            key={`${option.panel}-${block?.id || section.id}`}
            title={option.title}
            icon={option.icon}
          >
            <DesignInspector {...props} panel={option.panel} embedded friendly />
          </Options>
        ))}
        {!props.styleOnly && props.selection && (
          <EasyMove
            document={document}
            selection={props.selection}
            disabled={disabled}
            onMove={props.onMove}
          />
        )}
        {!props.styleOnly && (
          <button
            className="button button-outline"
            type="button"
            disabled={Object.keys(document.components || {}).length >= 32}
            onClick={props.onComponent}
          >
            <Icon name="puzzle" />
            {t('Save as a reusable part')}
          </button>
        )}
        <button className="easy-text-button" type="button" onClick={props.onReset}>
          <Icon name="refresh" />
          {t('Reset appearance for this screen and state')}
        </button>
        <div className="easy-remove-row">
          {!props.styleOnly && (
            <button className="button button-outline" type="button" onClick={onDuplicate}>
              <Icon name="copy" />
              {t('Duplicate')}
            </button>
          )}
          <button className="easy-text-button danger" type="button" onClick={onDelete}>
            <Icon name="trash" />
            {t('Remove')}
          </button>
        </div>
      </fieldset>
    </>
  );
}
