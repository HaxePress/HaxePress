import Icon from '../../components/Icon';
import { useTranslation } from '../../i18n';
import { layoutStyles } from './easy-controls';
import type { StyleMap } from './types';

function LengthControl({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  const { t } = useTranslation();
  const parsed = /^(-?\d*\.?\d+)(px|%|rem|em|vw|vh)?$/.exec(value);
  const unit = parsed ? parsed[2] || 'px' : value === 'auto' ? 'auto' : value ? 'custom' : '';
  return (
    <label className="easy-length">
      <span>{t(label)}</span>
      <span>
        {unit !== 'auto' && (
          <input
            aria-label={t(label)}
            type={unit === 'custom' ? 'text' : 'number'}
            step="any"
            value={parsed ? parsed[1] : unit === 'custom' ? value : ''}
            placeholder={t('Automatic')}
            maxLength={2000}
            onChange={(event) =>
              onChange(
                event.target.value === ''
                  ? ''
                  : event.target.value + (unit === 'custom' ? '' : unit || 'px'),
              )
            }
          />
        )}
        <select
          aria-label={t('{field} unit', { field: t(label) })}
          value={unit}
          onChange={(event) => {
            const next = event.target.value;
            if (!next || next === 'auto') onChange(next);
            else if (next !== 'custom') onChange((parsed?.[1] || '0') + next);
          }}
        >
          <option value="">{t('Automatic')}</option>
          {['px', '%', 'rem', 'em', 'vw', 'vh'].map((option) => (
            <option value={option} key={option}>
              {option}
            </option>
          ))}
          <option value="auto">auto</option>
          {unit === 'custom' && <option value="custom">{t('Custom value')}</option>}
        </select>
        {value && (
          <button
            className="icon-button"
            type="button"
            aria-label={t('Reset {field}', { field: t(label) })}
            onClick={() => onChange('')}
          >
            <Icon name="x" />
          </button>
        )}
      </span>
    </label>
  );
}

export default function EasyArrangement({
  values,
  onStyle,
  onStyles,
  onImage,
}: {
  values: StyleMap;
  onStyle: (property: string, value: string) => void;
  onStyles: (values: StyleMap) => void;
  onImage: () => void;
}) {
  const { t } = useTranslation();
  const layout =
    values.display === 'grid'
      ? 'grid'
      : values.display === 'flex'
        ? values['flex-direction'] === 'row'
          ? 'row'
          : 'stack'
        : '';
  const columns = /^repeat\((\d+),/.exec(values['grid-template-columns'] || '')?.[1];
  function length(property: string, label: string) {
    return (
      <LengthControl
        key={property}
        label={label}
        value={values[property] || ''}
        onChange={(value) => onStyle(property, value)}
      />
    );
  }
  return (
    <div className="easy-arrangement">
      <details className="easy-detail-group">
        <summary>
          <Icon name="layout" />
          {t('Arrange and resize')}
        </summary>
        <div className="easy-controls">
          <div className="easy-choice-label" role="group" aria-label={t('Arrange items')}>
            {t('Arrange items')}
            <span className="easy-choice-row">
              {(
                [
                  { id: 'stack', name: 'Stack', icon: 'layers' },
                  { id: 'row', name: 'Side by side', icon: 'columns' },
                  { id: 'grid', name: 'Grid', icon: 'grid' },
                ] as const
              ).map((option) => (
                <button
                  key={option.id}
                  type="button"
                  aria-pressed={layout === option.id}
                  onClick={() => onStyles(layoutStyles(option.id))}
                >
                  <Icon name={option.icon} />
                  <span>{t(option.name)}</span>
                </button>
              ))}
            </span>
          </div>
          {layout === 'grid' && (
            <label>
              {t('Number of columns')}
              <input
                type="number"
                min={1}
                max={24}
                value={columns || ''}
                placeholder={t('Custom value')}
                onChange={(event) => {
                  const count = event.target.valueAsNumber;
                  if (Number.isInteger(count) && count >= 1 && count <= 24)
                    onStyle('grid-template-columns', `repeat(${count}, minmax(0, 1fr))`);
                }}
              />
            </label>
          )}
          {length('gap', 'Space between items')}
          <div className="easy-style-pair">
            {length('width', 'Width')}
            {length('height', 'Height')}
          </div>
          <div className="easy-style-pair">
            {length('max-width', 'Maximum width')}
            {length('min-height', 'Minimum height')}
          </div>
          <label>
            {t('How should it stay on the page?')}
            <select
              value={values.position || ''}
              onChange={(event) => onStyle('position', event.target.value)}
            >
              <option value="">{t('Automatic')}</option>
              <option value="static">{t('Follow the page layout')}</option>
              <option value="relative">{t('Offset from its place')}</option>
              <option value="absolute">{t('Place freely inside its group')}</option>
              <option value="sticky">{t('Stick while scrolling')}</option>
              <option value="fixed">{t('Stay on the screen')}</option>
            </select>
          </label>
          {values.position && values.position !== 'static' && (
            <>
              <div className="easy-style-pair">
                {length('left', 'Distance from left')}
                {length('top', 'Distance from top')}
              </div>
              <label>
                {t('Layer order')}
                <input
                  type="number"
                  min={-1000}
                  max={10000}
                  value={values['z-index'] || ''}
                  placeholder={t('Automatic')}
                  onChange={(event) => onStyle('z-index', event.target.value)}
                />
              </label>
            </>
          )}
          <label>
            {t('Line up items')}
            <select
              value={values['align-items'] || ''}
              onChange={(event) => onStyle('align-items', event.target.value)}
            >
              <option value="">{t('Automatic')}</option>
              <option value="flex-start">{t('Start')}</option>
              <option value="center">{t('Center')}</option>
              <option value="flex-end">{t('End')}</option>
              <option value="stretch">{t('Stretch')}</option>
              <option value="baseline">{t('Text baseline')}</option>
            </select>
          </label>
          <div className="easy-style-pair">
            <label>
              {t('Inside space')}
              <input
                type="number"
                min={0}
                max={2000}
                placeholder={t('Automatic')}
                value={/^\d+px$/.test(values.padding || '') ? parseInt(values.padding, 10) : ''}
                onChange={(event) =>
                  onStyle('padding', event.target.value ? event.target.value + 'px' : '')
                }
              />
            </label>
            <label>
              {t('Outside space')}
              <input
                type="number"
                min={-2000}
                max={2000}
                placeholder={t('Automatic')}
                value={/^-?\d+px$/.test(values.margin || '') ? parseInt(values.margin, 10) : ''}
                onChange={(event) =>
                  onStyle('margin', event.target.value ? event.target.value + 'px' : '')
                }
              />
            </label>
          </div>
          <label>
            {t('Show on this screen')}
            <select
              value={values.display === 'none' ? 'hidden' : 'visible'}
              onChange={(event) =>
                onStyle(
                  'display',
                  event.target.value === 'hidden'
                    ? 'none'
                    : values['grid-template-columns']
                      ? 'grid'
                      : values['flex-direction']
                        ? 'flex'
                        : 'block',
                )
              }
            >
              <option value="visible">{t('Visible')}</option>
              <option value="hidden">{t('Hidden')}</option>
            </select>
          </label>
        </div>
      </details>
      <details className="easy-detail-group">
        <summary>
          <Icon name="palette" />
          {t('Colors, borders and pictures')}
        </summary>
        <div className="easy-controls">
          <label>
            {t('Fill color')}
            <input
              type="color"
              aria-label={t('Choose fill color')}
              value={
                /^#[0-9a-f]{6}$/i.test(values['background-color'] || values.background || '')
                  ? values['background-color'] || values.background
                  : '#ffffff'
              }
              onChange={(event) => onStyle('background-color', event.target.value)}
            />
            <input
              value={values['background-color'] || values.background || ''}
              placeholder={t('Automatic')}
              maxLength={2000}
              onChange={(event) => onStyle('background-color', event.target.value)}
            />
          </label>
          <button className="button button-outline" type="button" onClick={onImage}>
            <Icon name="image" />
            {t('Background image')}
          </button>
          <button
            className="easy-text-button"
            type="button"
            onClick={() => onStyle('background-image', 'none')}
          >
            {t('Remove background image')}
          </button>
          {length('border-radius', 'Corner radius')}
          <label>
            {t('Shadow')}
            <select
              value={
                [
                  '',
                  'none',
                  '0 4px 16px rgb(0 0 0 / 0.12)',
                  '0 12px 36px rgb(0 0 0 / 0.18)',
                ].includes(values['box-shadow'] || '')
                  ? values['box-shadow'] || ''
                  : 'custom'
              }
              onChange={(event) => onStyle('box-shadow', event.target.value)}
            >
              <option value="">{t('Automatic')}</option>
              <option value="none">{t('None')}</option>
              <option value="0 4px 16px rgb(0 0 0 / 0.12)">{t('Soft')}</option>
              <option value="0 12px 36px rgb(0 0 0 / 0.18)">{t('Strong')}</option>
              <option value="custom" disabled>
                {t('Custom value')}
              </option>
            </select>
          </label>
        </div>
      </details>
    </div>
  );
}
