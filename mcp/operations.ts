import {
  blockLabels,
  canContain,
  cloneBlock,
  cloneSection,
  findBlockLocation,
  moveDesignEntry,
  newBlock,
  newSection,
  scopesFor,
  sectionsFor,
  selectionFor,
  setStyle,
  type BlockType,
  type Breakpoint,
  type DesignDrag,
  type DesignSelection,
  type Interaction,
  type ThemeDocument,
} from '../resources/js/themes/builder/types';
import {
  friendlySection,
  sectionChoices,
  type FriendlySection,
} from '../resources/js/themes/builder/friendly-presets';
import { layoutBlock, layoutPresets } from '../resources/js/themes/builder/presets';

export interface Operation {
  action:
    'insert' | 'section' | 'update' | 'style' | 'move' | 'remove' | 'duplicate' | 'tokens' | 'css';
  target?: DesignSelection;
  destination?: DesignDrag;
  preset?: string;
  name?: string;
  values?: Record<string, unknown>;
  breakpoint?: Breakpoint;
  state?: Interaction;
  text?: string;
}
const blockFields = new Set([
  'name',
  'text',
  'href',
  'image',
  'alt',
  'level',
  'tag',
  'classes',
  'attributes',
  'bindings',
  'source',
  'component',
  'slot',
  'condition',
  'styles',
  'children',
]);
const sectionFields = new Set([
  'name',
  'background',
  'color',
  'padding',
  'columns',
  'align',
  'width',
  'classes',
  'styles',
]);
const tokenFields = new Set(['background', 'text', 'accent', 'font', 'width', 'radius']);
const reserved = new Set(['__proto__', 'prototype', 'constructor']);
function assign(target: object, values: Record<string, unknown>, allowed: Set<string>) {
  for (const [key, value] of Object.entries(values)) {
    if (!allowed.has(key) || reserved.has(key)) throw new Error('Unsupported field: ' + key);
    Object.defineProperty(target, key, {
      value,
      configurable: true,
      enumerable: true,
      writable: true,
    });
  }
}

export function applyOperations(document: ThemeDocument, operations: Operation[]) {
  const created: DesignSelection[] = [];
  for (const operation of operations) {
    const target = operation.target;
    if (operation.action === 'tokens') {
      assign(document.tokens, operation.values || {}, tokenFields);
      continue;
    }
    if (operation.action === 'css') {
      document.css = operation.text || '';
      continue;
    }
    if (!target || !scopesFor(document).includes(target.scope))
      throw new Error('Choose an existing design scope.');
    const sections = sectionsFor(document, target.scope);
    const selected = selectionFor(document, target);
    if (operation.action === 'section') {
      if (
        operation.preset &&
        ![...sectionChoices.map((choice) => choice.id), 'header', 'footer'].includes(
          operation.preset,
        )
      )
        throw new Error('Choose a supported ready section.');
      const section = operation.preset
        ? friendlySection(operation.preset as FriendlySection)
        : newSection(operation.name || 'Section');
      if (operation.name) section.name = operation.name;
      const index = sections.findIndex((entry) => entry.id === target.section);
      sections.splice(index < 0 ? sections.length : index + 1, 0, section);
      created.push({ scope: target.scope, section: section.id });
      continue;
    }
    if (!selected.section || (target.block && !selected.block))
      throw new Error('The selected design element no longer exists.');
    if (operation.action === 'insert') {
      const preset = operation.preset || 'text';
      if (
        preset.startsWith('layout:')
          ? !Object.hasOwn(layoutPresets, preset.slice(7))
          : !Object.hasOwn(blockLabels, preset)
      )
        throw new Error('Choose a supported element or layout.');
      const node = preset.startsWith('layout:')
        ? layoutBlock(preset.slice(7) as keyof typeof layoutPresets)
        : newBlock(preset as BlockType);
      assign(node, operation.values || {}, blockFields);
      if (selected.block && canContain(selected.block)) (selected.block.children ||= []).push(node);
      else if (target.block) {
        const location = findBlockLocation(selected.section.blocks, target.block)!;
        location.list.splice(location.index + 1, 0, node);
      } else selected.section.blocks.push(node);
      created.push({ ...target, block: node.id });
    } else if (operation.action === 'update') {
      assign(
        selected.block || selected.section,
        operation.values || {},
        selected.block ? blockFields : sectionFields,
      );
    } else if (operation.action === 'style') {
      const node = selected.block || selected.section;
      for (const [property, value] of Object.entries(operation.values || {})) {
        if (reserved.has(property)) throw new Error('Choose a valid CSS property.');
        if (typeof value !== 'string') throw new Error('CSS values must be strings.');
        setStyle(
          (node.styles ||= {}),
          operation.breakpoint || 'desktop',
          operation.state || 'normal',
          property,
          value,
        );
      }
    } else if (operation.action === 'move') {
      if (!operation.destination || !moveDesignEntry(document, target, operation.destination))
        throw new Error('This move is invalid or would create a cycle.');
    } else if (operation.action === 'remove' || operation.action === 'duplicate') {
      if (target.block) {
        const location = findBlockLocation(selected.section.blocks, target.block)!;
        if (operation.action === 'remove') location.list.splice(location.index, 1);
        else {
          const copy = cloneBlock(location.list[location.index]);
          location.list.splice(location.index + 1, 0, copy);
          created.push({ ...target, block: copy.id });
        }
      } else {
        const index = sections.findIndex((entry) => entry.id === target.section);
        if (operation.action === 'remove') sections.splice(index, 1);
        else {
          const copy = cloneSection(selected.section);
          sections.splice(index + 1, 0, copy);
          created.push({ scope: target.scope, section: copy.id });
        }
      }
    }
  }
  return created;
}
