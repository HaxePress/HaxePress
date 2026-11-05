import { Link } from '@inertiajs/react';
import { useTranslation } from '../../i18n';
import { paletteChoices } from './friendly-presets';
import type { ThemeDocument } from './types';
import DesignSettings from './DesignSettings';
import ColorControl from './ColorControl';

export default function EasyDesign({
  document,
  onChange,
  disabled,
  collections,
  onClass,
}: {
  document: ThemeDocument;
  onChange: (change: (document: ThemeDocument) => void) => void;
  disabled: boolean;
  collections: { key: string; name: string }[];
  onClass: (name: string) => void;
}) {
  const { t } = useTranslation();
  return (
    <fieldset className="easy-controls" disabled={disabled}>
      <h2>{t('Make it yours')}</h2>
      <p className="easy-help">{t('These choices work across your whole design.')}</p>
      <div>
        <h3>{t('Choose a color')}</h3>
        <div className="easy-palette" role="group" aria-label={t('Color palette')}>
          {paletteChoices.map((palette) => (
            <button
              key={palette.name}
              type="button"
              style={{ background: palette.value }}
              aria-label={t(palette.name)}
              aria-pressed={document.tokens.accent === palette.value}
              onClick={() =>
                onChange((document) => {
                  document.tokens.accent = palette.value;
                })
              }
            >
              {document.tokens.accent === palette.value ? '✓' : ''}
            </button>
          ))}
          <label className="easy-custom-color" title={t('Choose your own color')}>
            <input
              type="color"
              aria-label={t('Choose your own color')}
              value={document.tokens.accent}
              onChange={(event) =>
                onChange((document) => {
                  document.tokens.accent = event.target.value;
                })
              }
            />
            <span>+</span>
          </label>
        </div>
      </div>
      <div>
        <h3>{t('Choose a writing style')}</h3>
        <div className="easy-fonts">
          {[
            { name: 'Modern', value: 'sans', font: 'DM Sans' },
            { name: 'Classic', value: 'serif', font: 'DM Serif Display' },
          ].map((font) => (
            <button
              key={font.value}
              type="button"
              aria-pressed={document.tokens.font === font.value}
              onClick={() =>
                onChange((document) => {
                  document.tokens.font = font.value;
                })
              }
            >
              <span style={{ fontFamily: font.font }}>Aa</span>
              {t(font.name)}
            </button>
          ))}
        </div>
      </div>
      <label className="easy-color">
        <span>{t('Page background')}</span>
        <input
          type="color"
          aria-label={t('Page background')}
          value={document.tokens.background}
          onChange={(event) =>
            onChange((document) => {
              document.tokens.background = event.target.value;
            })
          }
        />
      </label>
      <ColorControl
        label="Text color"
        value={document.tokens.text}
        onChange={(text) =>
          onChange((document) => {
            document.tokens.text = text;
          })
        }
      />
      <details className="easy-detail-group">
        <summary>{t('All design settings')}</summary>
        <DesignSettings
          document={document}
          panel="design"
          collections={collections}
          disabled={disabled}
          onChange={onChange}
          onClass={onClass}
          friendly
        />
      </details>
      <div className="easy-connected">
        <h3>{t('Site name and logo')}</h3>
        <p>{t('Use your own name and picture in the site header.')}</p>
        <Link className="button button-outline" href="/admin/settings">
          {t('Open Site settings')}
        </Link>
      </div>
    </fieldset>
  );
}
