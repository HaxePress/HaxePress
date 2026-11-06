import { useEffect, useState, type DragEvent } from 'react';
import Icon from '../../components/Icon';
import { useTranslation } from '../../i18n';
import { friendlyLabel } from './friendly-presets';
import {
  blockLabels,
  containerTypes,
  canContain,
  type DesignBlock,
  type DesignDrag,
  type DesignSection,
  type DesignSelection,
} from './types';

export default function DesignLayers({
  scope,
  sections,
  selection,
  onSelect,
  onDrop,
  friendly = false,
  disabled = false,
}: {
  scope: string;
  sections: DesignSection[];
  selection: DesignSelection | null;
  onSelect: (selection: DesignSelection) => void;
  onDrop: (source: DesignDrag, target: DesignDrag) => void;
  friendly?: boolean;
  disabled?: boolean;
}) {
  const { t } = useTranslation();
  const [open, setOpen] = useState<Record<string, boolean>>({});
  useEffect(() => {
    if (!selection?.block) return;
    const path: string[] = [];
    function find(nodes: DesignBlock[]): boolean {
      for (const node of nodes) {
        if (node.id === selection!.block) return true;
        if (find(node.children || [])) {
          path.push(node.id);
          return true;
        }
      }
      return false;
    }
    for (const section of sections) if (find(section.blocks)) break;
    if (path.length)
      setOpen((previous) => ({ ...previous, ...Object.fromEntries(path.map((id) => [id, true])) }));
  }, [selection?.block, scope]);
  function start(event: DragEvent, target: DesignDrag) {
    if (disabled) return;
    event.stopPropagation();
    event.dataTransfer.setData('application/x-haxepress-design', JSON.stringify(target));
    event.dataTransfer.effectAllowed = 'move';
  }
  function drop(event: DragEvent, target: DesignDrag) {
    event.preventDefault();
    event.stopPropagation();
    if (disabled) return;
    try {
      onDrop(JSON.parse(event.dataTransfer.getData('application/x-haxepress-design')), target);
    } catch {
      /* Unrelated drag source. */
    }
  }
  function zone(target: DesignDrag, label: string) {
    return (
      <div
        className="studio-drop-zone"
        aria-label={t(label)}
        onDragOver={(event) => {
          event.preventDefault();
          event.stopPropagation();
          event.currentTarget.classList.add('is-over');
        }}
        onDragLeave={(event) => event.currentTarget.classList.remove('is-over')}
        onDrop={(event) => {
          event.currentTarget.classList.remove('is-over');
          drop(event, target);
        }}
      />
    );
  }
  function blocks(entries: DesignBlock[], section: string, depth: number) {
    return entries.map((block) => {
      const target = { scope, section, block: block.id };
      const expanded = open[block.id] ?? depth < 2;
      return (
        <div key={block.id} className="studio-tree-entry">
          {zone({ ...target, position: 'before' }, 'Insert before element')}
          <button
            type="button"
            className={`studio-layer studio-layer-block${selection?.block === block.id ? ' is-selected' : ''}`}
            style={{ paddingInlineStart: 18 + depth * 14 }}
            draggable={!disabled}
            disabled={disabled}
            onDragStart={(event) => start(event, target)}
            onClick={() => onSelect(target)}
            onDragOver={(event) => {
              event.preventDefault();
              event.stopPropagation();
            }}
            onDrop={(event) =>
              drop(event, {
                ...target,
                position: canContain(block) ? 'inside' : 'before',
              })
            }
          >
            <Icon name="grip" />
            <Icon
              name={
                block.type === 'container'
                  ? 'layout'
                  : block.type === 'repeat'
                    ? 'grid'
                    : block.type === 'component'
                      ? 'puzzle'
                      : block.type === 'image'
                        ? 'image'
                        : 'file'
              }
            />
            <span>
              {block.name ||
                block.text ||
                t(friendly ? friendlyLabel(block) : blockLabels[block.type])}
            </span>
            {block.bindings && Object.values(block.bindings).some(Boolean) && <Icon name="link" />}
          </button>
          {block.children?.length ? (
            <button
              type="button"
              className="studio-tree-toggle"
              aria-label={t(expanded ? 'Collapse {element}' : 'Expand {element}', {
                element: block.name || block.text || t(blockLabels[block.type]),
              })}
              aria-expanded={expanded}
              onClick={() => setOpen((previous) => ({ ...previous, [block.id]: !expanded }))}
            >
              {expanded ? '−' : '+'}
            </button>
          ) : null}
          {expanded && blocks(block.children || [], section, depth + 1)}
          {canContain(block) && expanded && (
            <div
              className="studio-tree-inside"
              style={{ marginInlineStart: 34 + depth * 14 }}
              onDragOver={(event) => {
                event.preventDefault();
                event.stopPropagation();
              }}
              onDrop={(event) => drop(event, { ...target, position: 'inside' })}
            >
              {t(friendly ? 'Drag an item here' : 'Drop inside')}
            </div>
          )}
          {zone({ ...target, position: 'after' }, 'Insert after element')}
        </div>
      );
    });
  }
  return (
    <div className="studio-layers studio-tree">
      {sections.map((section) => (
        <div className="studio-layer-section" key={section.id}>
          {zone({ scope, section: section.id, position: 'before' }, 'Insert before section')}
          <button
            type="button"
            className={`studio-layer${selection?.section === section.id && !selection.block ? ' is-selected' : ''}`}
            draggable={!disabled}
            disabled={disabled}
            onDragStart={(event) => start(event, { scope, section: section.id })}
            onClick={() => onSelect({ scope, section: section.id })}
            onDragOver={(event) => event.preventDefault()}
            onDrop={(event) => drop(event, { scope, section: section.id, position: 'inside' })}
          >
            <Icon name="grip" />
            <Icon name="layout" />
            <span>{section.name || t('Section')}</span>
          </button>
          {blocks(section.blocks, section.id, 0)}
          {zone({ scope, section: section.id, position: 'inside' }, 'Append to section')}
        </div>
      ))}
      {zone({ scope, section: '', position: 'after' }, 'Move section to end')}
    </div>
  );
}
