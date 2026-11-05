import Icon from '../../components/Icon';
import { useTranslation } from '../../i18n';
import DesignLayers from './DesignLayers';
import DesignScopeControls from './DesignScopeControls';
import type { DesignDrag, DesignSection, DesignSelection, ThemeDocument } from './types';

export default function EasyPages({
  document,
  scope,
  sections,
  selection,
  onScope,
  onSelect,
  onAdd,
  onMove,
  onChange,
  disabled,
}: {
  document: ThemeDocument;
  scope: string;
  sections: DesignSection[];
  selection: DesignSelection | null;
  onScope: (scope: string) => void;
  onSelect: (selection: DesignSelection) => void;
  onAdd: () => void;
  onMove: (source: DesignDrag, target: DesignDrag) => void;
  onChange: (change: (document: ThemeDocument) => void) => void;
  disabled: boolean;
}) {
  const { t } = useTranslation();
  return (
    <>
      <DesignScopeControls
        document={document}
        scope={scope}
        friendly
        disabled={disabled}
        onScope={onScope}
        onChange={onChange}
      />
      <div className="easy-panel-title">
        <h2>{t('On this page')}</h2>
        <button
          className="icon-button"
          type="button"
          aria-label={t('Add a section')}
          disabled={disabled}
          onClick={onAdd}
        >
          <Icon name="plus" />
        </button>
      </div>
      <p className="easy-help">
        {t('Choose anything here, even hidden items. Drag to reorder or put items inside a group.')}
      </p>
      {sections.length === 0 ? (
        <div className="easy-empty">
          <Icon name="layout" />
          <p>{t('Your page is empty. Start by adding a section.')}</p>
          <button className="button" type="button" disabled={disabled} onClick={onAdd}>
            {t('Add your first section')}
          </button>
        </div>
      ) : (
        <>
          <DesignLayers
            scope={scope}
            sections={sections}
            selection={selection}
            onSelect={onSelect}
            onDrop={onMove}
            disabled={disabled}
            friendly
          />
          <button type="button" className="studio-add-section" disabled={disabled} onClick={onAdd}>
            <Icon name="plus" />
            {t('Add another section')}
          </button>
        </>
      )}
    </>
  );
}
