import { useEffect, useState } from 'react';
import Icon from '../../components/Icon';
import { useTranslation } from '../../i18n';
import { friendlyLabel } from './friendly-presets';
import {
  canContain,
  labelFor,
  scopesFor,
  sectionsFor,
  selectionFor,
  visitBlocks,
  type DesignDrag,
  type DesignSelection,
  type ThemeDocument,
} from './types';

export default function EasyMove({
  document,
  selection,
  disabled,
  onMove,
}: {
  document: ThemeDocument;
  selection: DesignSelection;
  disabled: boolean;
  onMove: (source: DesignDrag, target: DesignDrag) => void;
}) {
  const { t } = useTranslation();
  const [scope, setScope] = useState(selection.scope);
  const [destination, setDestination] = useState('');
  const [position, setPosition] = useState<'before' | 'after' | 'inside'>('inside');
  useEffect(() => {
    setScope(selection.scope);
    setDestination('');
    setPosition(selection.block ? 'inside' : 'before');
  }, [selection.scope, selection.section, selection.block]);
  const selected = selectionFor(document, selection);
  const excluded = new Set<string>();
  if (selected.block) {
    excluded.add(selected.block.id);
    visitBlocks(selected.block.children || [], (node) => excluded.add(node.id));
  }
  const choices: { id: string; label: string; target: DesignDrag; container: boolean }[] = [];
  for (const section of sectionsFor(document, scope)) {
    if (!selection.block && scope === selection.scope && section.id === selection.section) continue;
    choices.push({
      id: section.id,
      label: section.name || t('Section'),
      target: { scope, section: section.id },
      container: Boolean(selection.block),
    });
    if (selection.block)
      visitBlocks(section.blocks, (node) => {
        if (!excluded.has(node.id))
          choices.push({
            id: node.id,
            label:
              (section.name || t('Section')) +
              ' / ' +
              (node.name || node.text.slice(0, 32) || t(friendlyLabel(node))),
            target: { scope, section: section.id, block: node.id },
            container: canContain(node),
          });
      });
  }
  if (!selection.block)
    choices.push({
      id: '$end',
      label: t('End of the page'),
      target: { scope, section: '' },
      container: false,
    });
  const chosen = choices.find((choice) => choice.id === destination);
  const sectionDestination = Boolean(selection.block && chosen && !chosen.target.block);
  const placement = sectionDestination
    ? 'inside'
    : position === 'inside' && !chosen?.container
      ? 'before'
      : position;
  return (
    <details className="easy-detail-group">
      <summary>
        <Icon name="move" />
        {t('Move somewhere else')}
      </summary>
      <fieldset className="easy-controls" disabled={disabled}>
        <label>
          {t('Destination page or saved part')}
          <select
            value={scope}
            onChange={(event) => {
              setScope(event.target.value);
              setDestination('');
            }}
          >
            {scopesFor(document).map((value) => (
              <option key={value} value={value}>
                {t(labelFor(document, value))}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t('Where on the page?')}
          <select value={destination} onChange={(event) => setDestination(event.target.value)}>
            <option value="">{t('Choose a destination')}</option>
            {choices.map((choice) => (
              <option key={choice.id} value={choice.id}>
                {choice.label}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t('Place it')}
          <select
            value={placement}
            onChange={(event) => setPosition(event.target.value as typeof position)}
          >
            {chosen?.container && <option value="inside">{t('Inside')}</option>}
            {!sectionDestination && (
              <>
                <option value="before">{t('Before')}</option>
                <option value="after">{t('After')}</option>
              </>
            )}
          </select>
        </label>
        <button
          type="button"
          className="button button-outline"
          disabled={!chosen}
          onClick={() => {
            if (chosen) onMove(selection, { ...chosen.target, position: placement });
          }}
        >
          {t('Move here')}
        </button>
      </fieldset>
    </details>
  );
}
