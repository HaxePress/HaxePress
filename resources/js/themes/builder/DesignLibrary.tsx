import Icon from '../../components/Icon';
import { useTranslation } from '../../i18n';
import { blockLabels, type BlockType, type ThemeDocument } from './types';
import { layoutPresets } from './presets';
import { friendlyBlockLabels } from './friendly-presets';

export default function DesignLibrary({
  document,
  disabled,
  onInsert,
  onSection,
  group,
  friendly = false,
  query = '',
}: {
  document: ThemeDocument;
  disabled: boolean;
  onInsert: (preset: string) => void;
  onSection: () => void;
  group?: 'layouts' | 'elements' | 'components';
  friendly?: boolean;
  query?: string;
}) {
  const { t } = useTranslation();
  const atomic = [
    'heading',
    'text',
    'image',
    'button',
    'divider',
    'spacer',
    'container',
    'element',
    'brand',
    'navigation',
    'content-title',
    'content-excerpt',
    'content-image',
    'content-body',
    'site-description',
    'pagination',
    'search',
    'extension',
    'repeat',
    'content-list',
  ] as BlockType[];
  function tile(id: string, label: string, icon: string) {
    if (query && !t(label).toLocaleLowerCase().includes(query.toLocaleLowerCase())) return null;
    return (
      <button
        type="button"
        key={id}
        disabled={disabled}
        draggable
        onDragStart={(event) => {
          event.dataTransfer.setData('application/x-haxepress-preset', id);
          event.dataTransfer.effectAllowed = 'copy';
        }}
        onClick={() => onInsert(id)}
      >
        <Icon name={icon} />
        <span>{t(label)}</span>
      </button>
    );
  }
  return (
    <>
      {(!group || group === 'layouts') && (
        <>
          <div className="studio-panel-heading">
            <h2>{t('Layout')}</h2>
            <button
              type="button"
              className="icon-button"
              aria-label={t('Add section')}
              disabled={disabled}
              onClick={onSection}
            >
              <Icon name="plus" />
            </button>
          </div>
          <p className="studio-help">
            {t('Click to insert, or drag into a container in the canvas.')}
          </p>
          <div className="studio-presets">
            {Object.entries(layoutPresets).map(([id, label]) =>
              tile(`layout:${id}`, label, id === 'grid' || id === 'cards' ? 'grid' : 'layout'),
            )}
          </div>
        </>
      )}
      {(!group || group === 'elements') && (
        <>
          <div className="studio-panel-heading">
            <h2>{t('Elements')}</h2>
          </div>
          <div className="studio-block-library">
            {atomic.map((type) =>
              tile(
                `block:${type}`,
                friendly ? friendlyBlockLabels[type] : blockLabels[type],
                type.includes('image') ? 'image' : type === 'extension' ? 'puzzle' : 'file',
              ),
            )}
          </div>
        </>
      )}
      {(!group || group === 'components') && Object.keys(document.components || {}).length > 0 && (
        <>
          <div className="studio-panel-heading">
            <h2>{t(friendly ? 'Saved parts' : 'Reusable components')}</h2>
          </div>
          <div className="studio-block-library">
            {Object.entries(document.components || {}).map(([id, component]) =>
              tile(`component:${id}`, component.name, 'puzzle'),
            )}
          </div>
        </>
      )}
    </>
  );
}
