import { useTranslation } from '../../i18n';
import { useState } from 'react';
import Icon from '../../components/Icon';
import FriendlyPreview from './FriendlyPreview';
import { sectionChoices, type FriendlySection } from './friendly-presets';
import DesignLibrary from './DesignLibrary';
import DesignMarkupImport from './DesignMarkupImport';
import type { ThemeDocument } from './types';

export default function EasyLibrary({
  scope,
  disabled,
  onAdd,
  document,
  destination,
  onInsert,
  onImport,
  initialGroup = 'sections',
}: {
  scope: string;
  disabled: boolean;
  onAdd: (kind: FriendlySection) => void;
  document: ThemeDocument;
  destination: string;
  onInsert: (preset: string) => void;
  onImport: (html: string) => Promise<boolean>;
  initialGroup?: 'sections' | 'elements';
}) {
  const { t } = useTranslation();
  const [group, setGroup] = useState<'sections' | 'elements' | 'layouts' | 'components'>(
    initialGroup,
  );
  const [query, setQuery] = useState('');
  const shared = scope === 'header' || scope === 'footer';
  return (
    <>
      <h2>{t('What would you like to add?')}</h2>
      <div className="easy-library-types" role="group" aria-label={t('Things to add')}>
        {(
          [
            { id: 'sections', label: 'Ready sections', icon: 'layout' },
            { id: 'elements', label: 'Elements', icon: 'plus' },
            { id: 'layouts', label: 'Layouts', icon: 'grid' },
            { id: 'components', label: 'Saved parts', icon: 'puzzle' },
          ] as const
        ).map((option) => (
          <button
            key={option.id}
            type="button"
            aria-pressed={group === option.id}
            onClick={() => setGroup(option.id)}
          >
            <Icon name={option.icon} />
            {t(option.label)}
          </button>
        ))}
      </div>
      <label className="easy-library-search">
        <span className="sr-only">{t('Find something to add')}</span>
        <Icon name="search" />
        <input
          type="search"
          value={query}
          placeholder={t('Find something to add')}
          onChange={(event) => setQuery(event.target.value)}
        />
      </label>
      {group !== 'sections' && (
        <p className="easy-insert-destination">
          <Icon name="cursor" />
          {t('Add to: {destination}', { destination })}
        </p>
      )}
      {group === 'sections' ? (
        <>
          <p className="easy-help">
            {t('Pick a layout. Then click its words or pictures to make it yours.')}
          </p>
          <div className="easy-section-library">
            {shared && (
              <button
                type="button"
                className="easy-section-card"
                disabled={disabled}
                onClick={() => onAdd(scope === 'header' ? 'header' : 'footer')}
              >
                <FriendlyPreview kind={scope === 'header' ? 'header' : 'footer'} />
                <strong>{t(scope === 'header' ? 'Site name and menu' : 'Simple footer')}</strong>
              </button>
            )}
            {sectionChoices
              .filter(
                (choice) =>
                  !query || t(choice.name).toLocaleLowerCase().includes(query.toLocaleLowerCase()),
              )
              .map((choice) => (
                <button
                  className="easy-section-card"
                  type="button"
                  key={choice.id}
                  disabled={disabled}
                  onClick={() => onAdd(choice.id)}
                >
                  <FriendlyPreview kind={choice.id} />
                  <span>
                    <strong>{t(choice.name)}</strong>
                    <small>{t(choice.description)}</small>
                  </span>
                </button>
              ))}
          </div>
        </>
      ) : (
        <DesignLibrary
          document={document}
          disabled={disabled}
          onInsert={onInsert}
          onSection={() => onAdd('empty')}
          group={group}
          friendly
          query={query}
        />
      )}
      {group === 'components' && !Object.keys(document.components || {}).length && (
        <p className="easy-help">
          {t(
            'Select a group or section, then choose Save as a reusable part. You can add it here whenever you need it.',
          )}
        </p>
      )}
      <DesignMarkupImport disabled={disabled} onImport={onImport} />
    </>
  );
}
