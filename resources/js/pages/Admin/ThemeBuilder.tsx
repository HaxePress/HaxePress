import { Link, router, usePage } from '../../page';
import { useEffect, useMemo, useRef, useState } from 'react';
import PageHead from '../../components/PageHead';
import Icon from '../../components/Icon';
import Alert from '../../components/Alert';
import MediaPicker from '../../components/MediaPicker';
import { uploadManagedImage, type MediaRules } from '../../media';
import { useTranslation } from '../../i18n';
import type { ContentItem, SharedProps } from '../../types';
import EasyPages from '../../themes/builder/EasyPages';
import { easyPageName } from '../../themes/builder/easy-controls';
import DesignScopeControls from '../../themes/builder/DesignScopeControls';
import DesignMarkupImport from '../../themes/builder/DesignMarkupImport';
import EasyLibrary from '../../themes/builder/EasyLibrary';
import EasyInspector from '../../themes/builder/EasyInspector';
import EasyDesign from '../../themes/builder/EasyDesign';
import useDesignSaving from '../../themes/builder/useDesignSaving';
import ThemeAiPanel from '../../themes/builder/ThemeAiPanel';
import AdminAiControl from '../../components/AdminAiControl';
import useThemeAiSync from '../../themes/builder/useThemeAiSync';
import {
  friendlySection,
  friendlyLabel,
  firstEditable,
  editableText,
  sectionChoices,
  type FriendlySection,
} from '../../themes/builder/friendly-presets';
import DesignLayers from '../../themes/builder/DesignLayers';
import DesignLibrary from '../../themes/builder/DesignLibrary';
import DesignInspector, { type DesignInspectorProps } from '../../themes/builder/DesignInspector';
import { importHtml } from '../../themes/builder/html-import';
import DesignSettings from '../../themes/builder/DesignSettings';
import { contentRepeater, layoutBlock, layoutPresets } from '../../themes/builder/presets';
import {
  blockLabels,
  cloneBlock,
  cloneSection,
  canContain,
  designMessages,
  findBlock,
  findBlockLocation,
  labelFor,
  moveDesignEntry,
  newBlock,
  newSection,
  scopesFor,
  sectionsFor,
  selectionFor,
  setStyle,
  upgradeDocument,
  visitBlocks,
  type BlockType,
  type Breakpoint,
  type DesignBlock,
  type DesignDrag,
  type DesignSection,
  type DesignSelection,
  type Interaction,
  type ThemeDocument,
  type StyleMap,
} from '../../themes/builder/types';

interface Studio {
  id: string;
  name: string;
  enabled: boolean;
  document: ThemeDocument;
  imageRules: MediaRules;
  version: number;
  publishedVersion: number;
  session: string;
  frameUrl: string;
  collections: { key: string; name: string }[];
}
const devices = [
  { id: 'desktop', label: 'Desktop', width: 1280 },
  { id: 'tablet', label: 'Tablet', width: 768 },
  { id: 'mobile', label: 'Mobile', width: 390 },
] as const;
type Snapshot = { name: string; document: ThemeDocument };

export default function ThemeBuilder({ studio }: { studio: Studio }) {
  const { t } = useTranslation();
  const { csrfToken, auth } = usePage<SharedProps>().props;
  const mediaRules = studio.imageRules;
  const [history, setHistory] = useState<{
    past: Snapshot[];
    present: Snapshot;
    future: Snapshot[];
  }>({
    past: [],
    present: { name: studio.name, document: upgradeDocument(studio.document) },
    future: [],
  });
  const { name, document } = history.present;
  const [mode, setMode] = useState<'easy' | 'advanced'>('easy');
  const [easyPanel, setEasyPanel] = useState<'pages' | 'add' | 'design' | 'sources'>('pages');
  const [easyAddGroup, setEasyAddGroup] = useState<'sections' | 'elements'>('sections');
  const saving = useDesignSaving({
    id: studio.id,
    csrfToken,
    snapshot: history.present,
    initialVersion: studio.version,
    initialPublishedVersion: studio.publishedVersion,
    initialActive: studio.enabled,
    autoSave: mode === 'easy',
  });
  const { version, publishedVersion, dirty } = saving;
  const [template, setTemplate] = useState('Home');
  const [scope, setScope] = useState('Home');
  const [selection, setSelection] = useState<DesignSelection | null>(null);
  const [device, setDevice] = useState<(typeof devices)[number]>(devices[0]);
  const deviceChosen = useRef(false);
  const [interaction, setInteraction] = useState<Interaction>('normal');
  const [panel, setPanel] = useState<'layers' | 'add' | 'design' | 'sources'>('layers');
  const [styleClass, setStyleClass] = useState('');
  const [ready, setReady] = useState(false);
  const [operationBusy, setBusy] = useState(false);
  const [exporting, setExporting] = useState(false);
  const exportPending = useRef(false);
  const busy = operationBusy || saving.publishing || exporting;
  const busyRef = useRef(false);
  busyRef.current = busy;
  const [uploading, setUploading] = useState(false);
  const [picker, setPicker] = useState(false);
  const [aiPanel, setAiPanel] = useState(false);
  const [imageTarget, setImageTarget] = useState<{
    selection: DesignSelection | null;
    styleClass: string;
    background: boolean;
    breakpoint: Breakpoint;
    interaction: Interaction;
  } | null>(null);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const [feeds, setFeeds] = useState<Record<string, ContentItem[]>>({});
  const [refresh, setRefresh] = useState(0);
  const [sourceStatus, setSourceStatus] = useState('');
  const [previewCollection, setPreviewCollection] = useState('');
  const frame = useRef<HTMLIFrameElement>(null);
  const canvas = useRef<HTMLElement>(null);
  const [canvasWidth, setCanvasWidth] = useState(1280);
  const current = useRef({
    document,
    selection,
    feeds,
    scope: template,
    interaction,
    breakpoint: device.id,
    styleClass,
    mode,
  });
  current.current = {
    document,
    selection,
    feeds,
    scope: template,
    interaction,
    breakpoint: device.id,
    styleClass,
    mode,
  };
  const historyRef = useRef(history.present);
  historyRef.current = history.present;
  const aiSync = useThemeAiSync({
    id: studio.id,
    snapshot: history.present,
    saving,
    blocked: busy || uploading,
    getEditorContext: () => ({ scope, selection }),
    onLoad: (remote) => {
      const next = { name: remote.name, document: upgradeDocument(remote.document) };
      setHistory((previous) => ({
        past: [...previous.past.slice(-39), previous.present],
        present: next,
        future: [],
      }));
      if (!scopesFor(next.document).includes(scope)) showScope('Home');
      if (selection) {
        const found = selectionFor(next.document, selection);
        if (!found.section || (selection.block && !found.block)) setSelection(null);
      }
      if (styleClass && !Object.hasOwn(next.document.classes || {}, styleClass)) setStyleClass('');
      setNotice('Design updated from the saved draft.');
    },
  });
  const protectedThemeImages = useMemo(() => {
    const source = JSON.stringify(document);
    const urls = source.match(
      /\/theme-assets\/theme-[a-z0-9]+(?:-[a-z0-9]+)*\/ta_[A-Za-z0-9_-]{32}\.(?:jpg|png|webp|gif)/g,
    );
    return new Set(urls || []);
  }, [document]);
  const selected = selectionFor(document, selection);
  const sections = sectionsFor(document, scope);
  const fallback = document.templateMeta?.[template]?.fallback || template;
  const templateParam = encodeURIComponent(template);
  const fallbackParam = encodeURIComponent(String(fallback));
  const collectionParam = previewCollection
    ? `&collection=${encodeURIComponent(previewCollection)}`
    : '';
  const frameUrl = `${studio.frameUrl}&template=${templateParam}&fallback=${fallbackParam}${collectionParam}`;
  const frameScale = Math.min(1, canvasWidth / device.width);

  useEffect(() => {
    if (!canvas.current) return;
    const observer = new ResizeObserver((entries) => {
      setCanvasWidth(Math.max(1, entries[0].contentRect.width));
      if (!deviceChosen.current)
        setDevice(window.matchMedia('(max-width:620px)').matches ? devices[2] : devices[0]);
    });
    observer.observe(canvas.current);
    return () => observer.disconnect();
  }, []);
  function edit(change: (snapshot: Snapshot) => void) {
    if (busyRef.current) return;
    setHistory((previous) => {
      const next = structuredClone(previous.present);
      change(next);
      if (JSON.stringify(next) === JSON.stringify(previous.present)) return previous;
      return { past: [...previous.past.slice(-39), previous.present], present: next, future: [] };
    });
    setNotice('');
    setError('');
  }
  function changeDocument(change: (document: ThemeDocument) => void) {
    edit((snapshot) => change(snapshot.document));
  }
  function undo() {
    if (busyRef.current) return;
    setHistory((previous) =>
      previous.past.length
        ? {
            past: previous.past.slice(0, -1),
            present: previous.past[previous.past.length - 1],
            future: [previous.present, ...previous.future].slice(0, 40),
          }
        : previous,
    );
  }
  function redo() {
    if (busyRef.current) return;
    setHistory((previous) =>
      previous.future.length
        ? {
            past: [...previous.past, previous.present],
            present: previous.future[0],
            future: previous.future.slice(1),
          }
        : previous,
    );
  }
  function send() {
    frame.current?.contentWindow?.postMessage(
      {
        type: designMessages.update,
        themeId: studio.id,
        session: studio.session,
        ...current.current,
      },
      location.origin,
    );
  }
  function select(target: DesignSelection) {
    const found = selectionFor(current.current.document, target);
    if (!found.section || (target.block && !found.block)) return;
    setSelection(target);
    setScope(target.scope);
    setStyleClass('');
    setPanel('layers');
    setEasyPanel('pages');
  }
  function showScope(value: string) {
    setScope(value);
    setSelection(null);
    setStyleClass('');
    if (value !== 'header' && value !== 'footer') setTemplate(value);
  }
  function move(source: DesignDrag, target: DesignDrag) {
    if (!source || !target) return;
    const check = structuredClone(current.current.document);
    if (!moveDesignEntry(check, source, target)) return;
    changeDocument((document) => {
      moveDesignEntry(document, source, target);
    });
    setScope(target.scope);
    if (target.scope !== 'header' && target.scope !== 'footer') setTemplate(target.scope);
    setStyleClass('');
    setEasyPanel('pages');
    setSelection({
      scope: target.scope,
      section: source.block ? target.section : source.section,
      block: source.block,
    });
  }
  function patchBlock(values: Partial<DesignBlock>) {
    if (!selection) return;
    changeDocument((document) => {
      const node = selectionFor(document, selection).block;
      if (node) Object.assign(node, values);
    });
  }
  function patchSection(values: Partial<DesignSection>) {
    if (!selection) return;
    changeDocument((document) => {
      const node = selectionFor(document, selection).section;
      if (node) Object.assign(node, values);
    });
  }
  function easyStyle(property: string, value: string) {
    if (
      property === 'font-size' &&
      selection &&
      device.id === 'desktop' &&
      interaction === 'normal'
    ) {
      const size = parseInt(value, 10);
      changeDocument((document) => {
        const node = selectionFor(document, selection).block;
        if (!node) return;
        const styles = (node.styles ||= {});
        setStyle(styles, 'desktop', 'normal', property, value);
        if (friendlyLabel(node) === 'Heading') {
          if (!styles.tablet?.normal?.['font-size'])
            setStyle(
              styles,
              'tablet',
              'normal',
              property,
              `${Math.max(28, Math.round(size * 0.8))}px`,
            );
          if (!styles.mobile?.normal?.['font-size'])
            setStyle(
              styles,
              'mobile',
              'normal',
              property,
              `${Math.max(24, Math.round(size * 0.6))}px`,
            );
        }
      });
      return;
    }
    if (property === 'grid-template-columns' && selected.block?.type === 'content-list') {
      convertContentList(property, value);
      return;
    }
    updateStyle(property, value);
  }
  function updateStyle(
    property: string,
    value: string,
    where = selection,
    breakpoint: Breakpoint = device.id,
    state: Interaction = interaction,
  ) {
    updateStyles({ [property]: value }, where, breakpoint, state);
  }
  function updateStyles(
    values: StyleMap,
    where = selection,
    breakpoint: Breakpoint = device.id,
    state: Interaction = interaction,
  ) {
    changeDocument((document) => {
      let styles;
      if (styleClass) styles = (document.classes ||= {})[styleClass] ||= {};
      else {
        const found = selectionFor(document, where);
        const node = found.block || found.section;
        if (!node) return;
        styles = node.styles ||= {};
      }
      for (const [property, value] of Object.entries(values)) {
        setStyle(styles, breakpoint, state, property, value);
        if (
          property === 'position' &&
          value === 'absolute' &&
          state === 'normal' &&
          breakpoint === 'desktop' &&
          !styles.mobile?.normal?.position
        ) {
          setStyle(styles, 'mobile', 'normal', 'position', 'static');
          setStyle(styles, 'mobile', 'normal', 'inset', 'auto');
        }
        if (
          property === 'display' &&
          value === 'grid' &&
          state === 'normal' &&
          breakpoint === 'desktop' &&
          !styles.mobile?.normal?.['grid-template-columns']
        )
          setStyle(styles, 'mobile', 'normal', 'grid-template-columns', 'minmax(0, 1fr)');
      }
    });
  }
  function resetAppearance() {
    changeDocument((document) => {
      const target = selectionFor(document, selection);
      const styles = styleClass
        ? document.classes?.[styleClass]
        : (target.block || target.section)?.styles;
      if (styles?.[device.id]) delete styles[device.id]![interaction];
    });
  }
  function selectClass(name: string) {
    setStyleClass(name);
    setSelection(null);
  }
  function convertContentList(property?: string, value = '') {
    if (!selected.block) return;
    const replacement = contentRepeater();
    const styles = (replacement.styles ||= {});
    for (const point of ['desktop', 'tablet', 'mobile'] as const)
      for (const state of ['normal', 'hover', 'focus'] as const) {
        const previous = selected.block.styles?.[point]?.[state];
        if (previous) {
          const device = (styles[point] ||= {});
          device[state] = { ...device[state], ...previous };
        }
      }
    if (property) setStyle(styles, device.id, interaction, property, value);
    patchBlock({
      ...replacement,
      id: selected.block.id,
      name: selected.block.name,
      attributes: selected.block.attributes,
      classes: selected.block.classes,
      condition: selected.block.condition,
    });
  }
  function insert(preset: string, target?: DesignDrag) {
    if (preset.startsWith('section:')) {
      addReadySection(preset.slice(8) as FriendlySection, target);
      return;
    }
    let node: DesignBlock;
    if (preset.startsWith('layout:')) {
      const key = preset.slice(7) as keyof typeof layoutPresets;
      if (!Object.hasOwn(layoutPresets, key)) return;
      node = layoutBlock(key);
    } else if (preset.startsWith('component:')) {
      const id = preset.slice(10);
      if (!current.current.document.components?.[id] || scope === `@${id}`) {
        setError('A component cannot contain itself.');
        return;
      }
      node = newBlock('component');
      node.component = id;
      node.name = current.current.document.components[id].name;
    } else {
      const type = preset.slice(6) as BlockType;
      if (!Object.hasOwn(blockLabels, type)) return;
      node = newBlock(type);
    }
    const destination = target || current.current.selection;
    const insertionScope = target?.scope || scope;
    const entries = sectionsFor(current.current.document, insertionScope);
    const found = selectionFor(current.current.document, destination || null);
    const created = found.section ? null : newSection();
    const sectionId = found.section?.id || created!.id;
    changeDocument((document) => {
      const entries = sectionsFor(document, insertionScope);
      let section = entries.find((section) => section.id === sectionId);
      if (!section) {
        section = structuredClone(created!);
        entries.push(section);
      }
      const selectedNode = findBlock(section.blocks, destination?.block);
      if (selectedNode && canContain(selectedNode) && (target?.position === 'inside' || !target)) {
        (selectedNode.children ||= []).push(node);
      } else if (destination?.block) {
        const location = findBlockLocation(section.blocks, destination.block);
        if (location)
          location.list.splice(location.index + (target?.position === 'before' ? 0 : 1), 0, node);
        else section.blocks.push(node);
      } else section.blocks.push(node);
    });
    setSelection({ scope: insertionScope, section: sectionId, block: node.id });
    setScope(insertionScope);
    setStyleClass('');
    setPanel('layers');
    setEasyPanel('pages');
  }
  function addReadySection(kind: FriendlySection, target?: DesignDrag) {
    const destinationScope = target?.scope || scope;
    if (
      !sectionChoices.some((choice) => choice.id === kind) &&
      !['header', 'footer'].includes(kind)
    )
      return;
    const section = friendlySection(kind);
    const selectedSection = target?.section || current.current.selection?.section;
    changeDocument((document) => {
      const entries = sectionsFor(document, destinationScope);
      const index = entries.findIndex((entry) => entry.id === selectedSection);
      entries.splice(index < 0 ? entries.length : index + 1, 0, section);
    });
    const block = firstEditable(section);
    setScope(destinationScope);
    setSelection({ scope: destinationScope, section: section.id, block: block?.id });
    setEasyPanel('pages');
    setPanel('layers');
    setNotice('Section added. Click its words or pictures to change them.');
  }
  function addSection() {
    const section = newSection();
    changeDocument((document) => sectionsFor(document, scope).push(section));
    setSelection({ scope, section: section.id });
    setPanel('add');
  }
  function removeSelected() {
    if (styleClass) {
      const key = styleClass;
      changeDocument((document) => {
        delete document.classes?.[key];
      });
      setStyleClass('');
      return;
    }
    if (!selection) return;
    changeDocument((document) => {
      const entries = sectionsFor(document, selection.scope);
      const index = entries.findIndex((section) => section.id === selection.section);
      if (index < 0) return;
      if (selection.block) {
        const location = findBlockLocation(entries[index].blocks, selection.block);
        if (location) location.list.splice(location.index, 1);
      } else entries.splice(index, 1);
    });
    setSelection(null);
  }
  function duplicateSelected() {
    if (!selection || !selected.section) return;
    const block = selected.block ? cloneBlock(selected.block) : null;
    const section = block ? null : cloneSection(selected.section);
    changeDocument((document) => {
      const entries = sectionsFor(document, selection.scope);
      const parent = entries.find((entry) => entry.id === selection.section);
      if (block && parent) {
        const location = findBlockLocation(parent.blocks, selection.block!);
        if (location) location.list.splice(location.index + 1, 0, block);
      } else if (section)
        entries.splice(
          entries.findIndex((entry) => entry.id === selection.section) + 1,
          0,
          section,
        );
    });
    setSelection({
      ...selection,
      section: block ? selection.section : section!.id,
      block: block?.id,
    });
  }
  function nudge(direction: -1 | 1) {
    if (!selection || !selected.section) return;
    changeDocument((document) => {
      const entries = sectionsFor(document, selection.scope);
      if (selection.block) {
        const parent = entries.find((section) => section.id === selection.section);
        const location = parent ? findBlockLocation(parent.blocks, selection.block) : null;
        if (!location) return;
        const next = location.index + direction;
        if (next < 0 || next >= location.list.length) return;
        [location.list[location.index], location.list[next]] = [
          location.list[next],
          location.list[location.index],
        ];
      } else {
        const index = entries.findIndex((section) => section.id === selection.section);
        const next = index + direction;
        if (next < 0 || next >= entries.length) return;
        [entries[index], entries[next]] = [entries[next], entries[index]];
      }
    });
  }
  function parentSelection() {
    if (!selection || !selected.section) return;
    const location = selection.block
      ? findBlockLocation(selected.section.blocks, selection.block)
      : null;
    setSelection({ ...selection, block: location?.parent?.id });
  }
  function saveComponent() {
    if (!selected.section) return;
    const id = crypto.randomUUID();
    const section = selected.block
      ? {
          ...newSection(selected.block.name || blockLabels[selected.block.type]),
          padding: 0,
          width: 'full' as const,
          blocks: [cloneBlock(selected.block)],
        }
      : cloneSection(selected.section);
    changeDocument((document) => {
      (document.components ||= {})[id] = {
        name: selected.block
          ? selected.block.name ||
            selected.block.text.slice(0, 80) ||
            blockLabels[selected.block.type]
          : selected.section!.name || 'Component',
        sections: [section],
      };
    });
    setNotice('Component saved. Add it from the element library.');
  }
  function openImage(background: boolean) {
    if (!selection && !styleClass) return;
    setImageTarget({
      selection: selection ? { ...selection } : null,
      styleClass,
      background,
      breakpoint: device.id,
      interaction,
    });
    setPicker(true);
  }
  function applyImage(url: string, alt: string) {
    if (!imageTarget) return;
    const target = imageTarget;
    changeDocument((document) => {
      const found = selectionFor(document, target.selection);
      const node = found.block || found.section;
      const styles = target.styleClass
        ? document.classes?.[target.styleClass]
        : node
          ? (node.styles ||= {})
          : null;
      if (!styles) return;
      if (target.background)
        setStyle(
          styles,
          target.breakpoint,
          target.interaction,
          'background-image',
          `url("${url}")`,
        );
      else if (found.block) Object.assign(found.block, { image: url, alt });
    });
  }
  async function upload(file?: File) {
    if (!file) return;
    setUploading(true);
    setError('');
    try {
      const image = await uploadManagedImage(file, csrfToken, mediaRules);
      applyImage(image.url, image.description);
      setPicker(false);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'The image could not be uploaded.');
    } finally {
      setUploading(false);
    }
  }
  async function importMarkup(html: string): Promise<boolean> {
    if (busy) return false;
    setError('');
    const snapshot = historyRef.current;
    try {
      const imported = importHtml(html, mediaRules);
      const proposal = structuredClone(snapshot.document);
      const section = newSection('Imported layout');
      section.padding = 0;
      section.width = 'full';
      section.blocks = imported.nodes;
      sectionsFor(proposal, scope).push(section);
      proposal.css = [proposal.css, imported.css].filter(Boolean).join('\n');
      setBusy(true);
      const response = await fetch(`/admin/themes/${studio.id}/design/data`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-TOKEN': csrfToken || '',
          Accept: 'application/json',
        },
        body: JSON.stringify({ design: JSON.stringify(proposal), scope: template, normalize: '1' }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'The HTML could not be imported.');
      setHistory((previous) => ({
        past: [...previous.past.slice(-39), previous.present],
        present: { name: previous.present.name, document: result.document },
        future: [],
      }));
      setSelection({ scope, section: section.id });
      setPanel('layers');
      setEasyPanel('pages');
      setNotice('HTML imported as editable elements.');
      return true;
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'The HTML could not be imported.');
      return false;
    } finally {
      setBusy(false);
    }
  }
  async function save(publish: boolean) {
    if (uploading || operationBusy) return;
    await saving.save(publish ? 'publish' : 'save');
  }
  async function exportTheme() {
    if (exportPending.current || busyRef.current || uploading) return;
    exportPending.current = true;
    setError('');
    setNotice('');
    try {
      // Let an inline editor's blur message reach the parent before taking the snapshot.
      await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
      const snapshot = historyRef.current;
      setExporting(true);
      const response = await fetch(`/admin/themes/${studio.id}/export`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-TOKEN': csrfToken || '',
          Accept: 'application/zip, application/json',
        },
        body: JSON.stringify({ name: snapshot.name, design: JSON.stringify(snapshot.document) }),
      });
      if (!response.ok) {
        const result = await response.json();
        throw new Error(result.error || 'The theme could not be exported.');
      }
      if (!response.headers.get('content-type')?.includes('application/zip')) {
        throw new Error('Your session expired. Reload the page and sign in again.');
      }
      const archive = await response.blob();
      const disposition = response.headers.get('content-disposition') || '';
      const filename = /filename="([^"]+)"/.exec(disposition)?.[1] || 'theme.zip';
      const url = URL.createObjectURL(archive);
      const link = window.document.createElement('a');
      link.href = url;
      link.download = filename;
      window.document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      setNotice('Theme exported.');
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'The theme could not be exported.');
    } finally {
      exportPending.current = false;
      setExporting(false);
    }
  }
  useEffect(() => {
    setReady(false);
    const receive = (event: MessageEvent) => {
      if (event.origin !== location.origin || event.source !== frame.current?.contentWindow) return;
      const message = event.data;
      if (message?.session !== studio.session || message.themeId !== studio.id) return;
      if (message.type === designMessages.ready) {
        setReady(true);
        send();
      }
      if (message.type === designMessages.select && message.selection) select(message.selection);
      if (
        message.type === designMessages.editText &&
        message.selection &&
        typeof message.text === 'string' &&
        message.text.length <= 16000
      ) {
        edit((snapshot) => {
          const node = selectionFor(snapshot.document, message.selection).block;
          if (node && editableText(node)) node.text = message.text;
        });
      }
      if (message.type === designMessages.chooseImage && message.selection) {
        const node = selectionFor(current.current.document, message.selection).block;
        if (node?.type === 'image' && !node.bindings?.image) {
          setImageTarget({
            selection: message.selection,
            styleClass: '',
            background: false,
            breakpoint: 'desktop',
            interaction: 'normal',
          });
          setPicker(true);
        }
      }
      if (message.type === designMessages.move) move(message.source, message.target);
      if (message.type === designMessages.insert && typeof message.preset === 'string')
        insert(message.preset, message.target);
      if (message.type === designMessages.resize && message.selection) {
        const target = message.selection as DesignSelection;
        const width = Math.max(1, Math.min(3840, Math.round(Number(message.width))));
        const height = Math.max(1, Math.min(6000, Math.round(Number(message.height))));
        if (Number.isFinite(width) && Number.isFinite(height)) {
          const point = selectionFor(current.current.document, target);
          if (point.block || point.section) {
            edit((snapshot) => {
              const point = selectionFor(snapshot.document, target);
              const node = point.block || point.section;
              if (node) {
                const styles = (node.styles ||= {});
                setStyle(styles, current.current.breakpoint, 'normal', 'width', `${width}px`);
                setStyle(styles, current.current.breakpoint, 'normal', 'height', `${height}px`);
              }
            });
          }
        }
      }
    };
    window.addEventListener('message', receive);
    return () => window.removeEventListener('message', receive);
  }, [frameUrl]);
  useEffect(() => {
    if (ready) send();
  }, [document, selection, feeds, ready, interaction, device.id, styleClass, mode]);
  const sourceIds: string[] = [];
  const checked = new Set<string>();
  function collect(scope: string) {
    if (checked.has(scope)) return;
    checked.add(scope);
    for (const section of sectionsFor(document, scope))
      visitBlocks(section.blocks, (node) => {
        if (node.type === 'repeat' && node.source?.startsWith('feed:')) sourceIds.push(node.source);
        if (node.type === 'component' && node.component) collect(`@${node.component}`);
      });
  }
  collect(template);
  if (!template.startsWith('@')) {
    collect('header');
    collect('footer');
  }
  const sourceKey = JSON.stringify({
    ids: [...new Set(sourceIds)].sort(),
    feeds: document.feeds || [],
    template,
    refresh,
  });
  useEffect(() => {
    if (!sourceIds.length) {
      setFeeds({});
      setSourceStatus('');
      return;
    }
    const controller = new AbortController();
    const timeout = setTimeout(async () => {
      setSourceStatus('Loading content…');
      try {
        const response = await fetch(`/admin/themes/${studio.id}/design/data`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-TOKEN': csrfToken || '',
            Accept: 'application/json',
          },
          body: JSON.stringify({
            design: JSON.stringify(historyRef.current.document),
            scope: template,
          }),
          signal: controller.signal,
        });
        if (!response.ok)
          throw new Error(
            'The content preview could not be loaded. Save a valid design and try again.',
          );
        const result = await response.json();
        if (!controller.signal.aborted) {
          setFeeds(result.feeds);
          setSourceStatus('');
        }
      } catch (failure) {
        if (!controller.signal.aborted)
          setSourceStatus(
            failure instanceof Error ? failure.message : 'The content preview could not be loaded.',
          );
      }
    }, 350);
    return () => {
      clearTimeout(timeout);
      controller.abort();
    };
  }, [sourceKey]);
  useEffect(() => {
    const unload = (event: BeforeUnloadEvent) => {
      if (dirty) {
        event.preventDefault();
        event.returnValue = '';
      }
    };
    const remove = router.on('before', (event) => {
      if (dirty && !window.confirm(t('Leave the theme builder? Unsaved changes will be lost.')))
        event.preventDefault();
    });
    window.addEventListener('beforeunload', unload);
    return () => {
      window.removeEventListener('beforeunload', unload);
      remove();
    };
  }, [dirty]);
  const status = dirty
    ? 'Unsaved changes'
    : version === publishedVersion
      ? 'Published'
      : publishedVersion
        ? 'Saved draft'
        : 'Unpublished draft';
  let count = 0;
  for (const value of scopesFor(document))
    for (const section of sectionsFor(document, value)) {
      count++;
      visitBlocks(section.blocks, () => count++);
    }
  const classSection: DesignSection | undefined = styleClass
    ? {
        id: 'style-class',
        name: `.${styleClass}`,
        background: '',
        color: '',
        padding: 0,
        columns: 1,
        align: 'left',
        width: 'full',
        blocks: [],
        styles: document.classes?.[styleClass] || {},
      }
    : undefined;
  const inspectorProps: DesignInspectorProps = {
    document,
    section: classSection || selected.section,
    block: styleClass ? undefined : selected.block,
    styleOnly: Boolean(styleClass),
    breakpoint: device.id,
    interaction,
    disabled: busy || uploading,
    onInteraction: setInteraction,
    onBlock: patchBlock,
    onSection: patchSection,
    onStyle: updateStyle,
    onImage: openImage,
    onParent: parentSelection,
    onClear: () => {
      setSelection(null);
      setStyleClass('');
    },
    onDuplicate: duplicateSelected,
    onDelete: () => {
      removeSelected();
      setNotice('Removed. You can bring it back with Undo.');
    },
    onNudge: nudge,
    onComponent: saveComponent,
    onEditComponent: (id) => showScope(`@${id}`),
    onConvertList: () => convertContentList(),
  };
  const exportAction = (
    <button
      className="button button-outline"
      type="button"
      disabled={busy || uploading || name.trim().length < 2}
      onClick={() => void exportTheme()}
      title={t('Download the current design, including its uploaded images.')}
    >
      <Icon name="download" />
      {t(exporting ? 'Exporting…' : 'Export theme')}
    </button>
  );
  const aiAction = (
    <button
      className="button button-outline"
      type="button"
      disabled={busy}
      onClick={() => setAiPanel(true)}
    >
      <Icon name="sparkles" />
      {t('Theme AI permissions')}
    </button>
  );
  const easyClass = mode === 'easy' ? ' theme-studio-easy' : '';
  const addingClass = mode === 'easy' && easyPanel === 'add' ? ' is-adding' : '';
  const selectionClass = selection || styleClass ? ' has-selection' : '';
  const studioClass = `admin-body theme-studio theme-studio-flexible${easyClass}${addingClass}${selectionClass}`;
  return (
    <div className={studioClass}>
      <PageHead title={t('Theme builder')} admin />
      <header className="studio-toolbar">
        <Link
          className="studio-back icon-button"
          href="/admin/themes"
          aria-label={t('Back to themes')}
        >
          <Icon name="arrow-left" />
        </Link>
        <div className="studio-title">
          <label className="sr-only" htmlFor="studio-name">
            {t('Theme name')}
          </label>
          <input
            id="studio-name"
            value={name}
            maxLength={100}
            disabled={busy}
            onChange={(event) =>
              edit((snapshot) => {
                snapshot.name = event.target.value;
              })
            }
          />
          <span role="status" className={dirty ? 'is-dirty' : ''}>
            {t(
              mode === 'easy'
                ? saving.saving
                  ? 'Saving your changes…'
                  : saving.error
                    ? 'Changes need attention'
                    : dirty
                      ? 'Changes waiting to save'
                      : 'All changes saved'
                : status,
            )}
          </span>
        </div>
        <div className="studio-history">
          <button
            className="icon-button"
            type="button"
            aria-label={t('Undo')}
            title={t('Undo')}
            disabled={busy || !history.past.length}
            onClick={undo}
          >
            <Icon name="undo" />
          </button>
          <button
            className="icon-button"
            type="button"
            aria-label={t('Redo')}
            title={t('Redo')}
            disabled={busy || !history.future.length}
            onClick={redo}
          >
            <Icon name="redo" />
          </button>
        </div>
        <div className="easy-mode-switch" role="group" aria-label={t('Editing tools')}>
          <button
            type="button"
            aria-pressed={mode === 'easy'}
            onClick={() => {
              setMode('easy');
              setInteraction('normal');
              setStyleClass('');
              setEasyPanel('pages');
            }}
          >
            {t('Easy')}
          </button>
          <button
            type="button"
            aria-pressed={mode === 'advanced'}
            onClick={() => setMode('advanced')}
          >
            {t('Advanced')}
          </button>
        </div>
        <div className="studio-devices" role="group" aria-label={t('Preview size')}>
          {devices.map((option) => (
            <button
              className="icon-button"
              type="button"
              key={option.id}
              aria-label={t(option.label)}
              title={t(option.label)}
              aria-pressed={device.id === option.id}
              onClick={() => {
                deviceChosen.current = true;
                setDevice(option);
              }}
            >
              <Icon name={option.id} />
            </button>
          ))}
        </div>
        {auth && <AdminAiControl adminId={auth.admin.id} csrfToken={csrfToken} />}
        {mode === 'easy' ? (
          <div className="studio-save-actions">
            {exportAction}
            {aiAction}
            <a href="/" target="_blank" rel="noopener noreferrer" className="button button-outline">
              {t('View website')}
            </a>
            <button
              type="button"
              className="button"
              disabled={
                busy ||
                uploading ||
                name.trim().length < 2 ||
                (!dirty && saving.active && publishedVersion === version)
              }
              onClick={() => void saving.save('launch')}
            >
              {t(
                saving.publishing
                  ? 'Publishing…'
                  : saving.active
                    ? 'Publish changes'
                    : 'Publish website',
              )}
              <Icon name="arrow-up-right" />
            </button>
          </div>
        ) : (
          <>
            <div className="studio-save-actions">
              {exportAction}
              {aiAction}
              <button
                className="button button-outline"
                type="button"
                disabled={busy || uploading || !dirty}
                onClick={() => void save(false)}
              >
                {t('Save draft')}
              </button>
              <button
                className="button"
                type="button"
                disabled={
                  busy ||
                  uploading ||
                  name.trim().length < 2 ||
                  (!dirty && publishedVersion === version)
                }
                onClick={() => void save(true)}
              >
                {t(busy ? 'Saving…' : 'Publish')}
              </button>
            </div>
          </>
        )}
      </header>
      <div className="studio-feedback">
        {(aiSync.available || aiSync.error) && (
          <div className="theme-ai-update" role="status">
            <span>
              {t(
                aiSync.error ||
                  'A newer saved design is available. Your local changes are still here.',
              )}
            </span>
            <button
              type="button"
              className="button button-outline"
              disabled={aiSync.loading || saving.saving || busy}
              onClick={() => void aiSync.load(true)}
            >
              {t('Load saved design')}
            </button>
          </div>
        )}
        <Alert
          error
          message={
            error ||
            (mode === 'easy' && saving.error.includes('another editor')
              ? t('This design changed in another tab. Reload to see the latest saved version.')
              : saving.error)
          }
        />
        {saving.error && (
          <button
            type="button"
            className="easy-retry"
            onClick={() =>
              saving.error.includes('another editor')
                ? window.location.reload()
                : void saving.retry()
            }
          >
            {t(
              saving.error.includes('another editor') ? 'Reload latest design' : 'Try saving again',
            )}
          </button>
        )}
        <Alert message={saving.notice || notice} />
      </div>
      <div className="studio-workspace">
        {mode === 'easy' ? (
          <aside className="studio-library easy-library" aria-label={t('Build your page')}>
            <div className="easy-main-tabs" role="tablist" aria-label={t('Website tools')}>
              {(
                [
                  { id: 'pages', label: 'Pages', icon: 'file' },
                  { id: 'add', label: 'Add', icon: 'plus' },
                  { id: 'design', label: 'Look and feel', icon: 'palette' },
                  { id: 'sources', label: 'Content', icon: 'database' },
                ] as const
              ).map((tab) => (
                <button
                  type="button"
                  role="tab"
                  key={tab.id}
                  aria-selected={easyPanel === tab.id}
                  onClick={() => setEasyPanel(tab.id)}
                >
                  <Icon name={tab.icon} />
                  <span>{t(tab.label)}</span>
                </button>
              ))}
            </div>
            <div className="studio-library-content">
              {easyPanel === 'pages' && (
                <EasyPages
                  document={document}
                  scope={scope}
                  sections={sections}
                  selection={selection}
                  onScope={showScope}
                  onSelect={select}
                  onAdd={() => {
                    setEasyAddGroup('sections');
                    setEasyPanel('add');
                  }}
                  onMove={move}
                  onChange={changeDocument}
                  disabled={busy}
                />
              )}
              {easyPanel === 'add' && (
                <EasyLibrary
                  key={easyAddGroup}
                  initialGroup={easyAddGroup}
                  scope={scope}
                  document={document}
                  destination={
                    selected.block
                      ? selected.block.name || t(blockLabels[selected.block.type])
                      : selected.section?.name || t('New section')
                  }
                  disabled={busy}
                  onAdd={addReadySection}
                  onInsert={insert}
                  onImport={importMarkup}
                />
              )}
              {easyPanel === 'design' && (
                <EasyDesign
                  document={document}
                  onChange={changeDocument}
                  disabled={busy}
                  collections={studio.collections || []}
                  onClass={selectClass}
                />
              )}
              {easyPanel === 'sources' && (
                <DesignSettings
                  document={document}
                  panel="sources"
                  collections={studio.collections || []}
                  disabled={busy}
                  onChange={changeDocument}
                  onClass={selectClass}
                  friendly
                />
              )}
            </div>
            <footer className="easy-library-footer">
              <Icon name="check" />
              <span>{t('Your draft saves automatically. Publish when you are ready.')}</span>
            </footer>
          </aside>
        ) : (
          <>
            <aside className="studio-library" aria-label={t('Theme structure')}>
              <div className="studio-tabs" role="tablist" aria-label={t('Builder tools')}>
                {(['layers', 'add', 'design', 'sources'] as const).map((value) => (
                  <button
                    type="button"
                    role="tab"
                    key={value}
                    aria-selected={panel === value}
                    onClick={() => setPanel(value)}
                  >
                    <Icon
                      name={
                        value === 'layers'
                          ? 'layers'
                          : value === 'add'
                            ? 'plus'
                            : value === 'design'
                              ? 'palette'
                              : 'database'
                      }
                    />
                    {t(
                      value === 'layers'
                        ? 'Layers'
                        : value === 'add'
                          ? 'Add'
                          : value === 'design'
                            ? 'Design'
                            : 'Sources',
                    )}
                  </button>
                ))}
              </div>
              <div className="studio-library-content">
                <DesignScopeControls
                  document={document}
                  scope={scope}
                  disabled={busy}
                  onScope={showScope}
                  onChange={changeDocument}
                />
                {panel === 'layers' && (
                  <>
                    <div className="studio-panel-heading">
                      <h2>{t(labelFor(document, scope))}</h2>
                      <button
                        className="icon-button"
                        type="button"
                        aria-label={t('Add section')}
                        disabled={busy}
                        onClick={addSection}
                      >
                        <Icon name="plus" />
                      </button>
                    </div>
                    <p className="studio-help">
                      {t(
                        'Nest elements inside containers. Drop above, below or inside an element.',
                      )}
                    </p>
                    <DesignLayers
                      scope={scope}
                      sections={sections}
                      selection={selection}
                      onSelect={(target) => select(target)}
                      onDrop={move}
                    />
                    <button
                      className="studio-add-section"
                      type="button"
                      disabled={busy}
                      onClick={addSection}
                    >
                      <Icon name="plus" />
                      {t('Add section')}
                    </button>
                    {scope.startsWith('@') && (
                      <p className="studio-help">
                        {t('Changes to this component update every instance.')}
                      </p>
                    )}
                  </>
                )}
                {panel === 'add' && (
                  <DesignLibrary
                    document={document}
                    disabled={busy}
                    onInsert={insert}
                    onSection={addSection}
                  />
                )}
                {panel === 'add' && <DesignMarkupImport disabled={busy} onImport={importMarkup} />}
                {(panel === 'design' || panel === 'sources') && (
                  <DesignSettings
                    document={document}
                    panel={panel}
                    collections={studio.collections || []}
                    disabled={busy}
                    onChange={changeDocument}
                    onClass={selectClass}
                  />
                )}
              </div>
              <footer className="studio-library-footer">
                <span>{t('{count} elements', { count })}</span>
                {publishedVersion > 0 && !dirty && (
                  <Link href={`/admin/themes/${studio.id}/preview`}>
                    <Icon name="eye" />
                    {t(studio.enabled ? 'Preview published theme' : 'Preview and activate')}
                  </Link>
                )}
              </footer>
            </aside>
          </>
        )}
        <main ref={canvas} className="studio-canvas" aria-label={t('Theme canvas')}>
          <div className="studio-canvas-caption">
            <span>
              {t(mode === 'easy' ? easyPageName(document, template) : labelFor(document, template))}
            </span>
            <div>
              <>
                <select
                  aria-label={t('Preview collection')}
                  value={previewCollection}
                  onChange={(event) => setPreviewCollection(event.target.value)}
                >
                  <option value="">{t('Default content')}</option>
                  {(studio.collections || []).map((collection) => (
                    <option key={collection.key} value={collection.key}>
                      {collection.name}
                    </option>
                  ))}
                </select>
                <button
                  className="icon-button"
                  type="button"
                  aria-label={t('Refresh content')}
                  onClick={() => {
                    setRefresh((value) => value + 1);
                    frame.current?.contentWindow?.location.reload();
                  }}
                >
                  <Icon name="refresh" />
                </button>
              </>
              <span>
                {t(device.label)}
                {!ready ? ` · ${t('Loading…')}` : ''}
              </span>
            </div>
          </div>
          {mode === 'easy' && (
            <div className="easy-canvas-tip">
              <Icon name="cursor" />
              <span>{t('Click to choose. Double-click words to edit.')}</span>
            </div>
          )}
          {sourceStatus && (
            <p className="studio-source-status" role="status">
              {t(sourceStatus)}
            </p>
          )}
          <div className="studio-frame-viewport" style={{ width: device.width * frameScale }}>
            <iframe
              ref={frame}
              className="studio-frame"
              title={t('Theme canvas preview')}
              src={frameUrl}
              style={{
                width: device.width,
                height: `${100 / frameScale}%`,
                transform: `scale(${frameScale})`,
              }}
              onLoad={() =>
                frame.current?.contentWindow?.postMessage(
                  { type: designMessages.request, themeId: studio.id, session: studio.session },
                  location.origin,
                )
              }
            />
          </div>
        </main>
        <aside className="studio-inspector" aria-label={t('Properties')}>
          {mode === 'easy' ? (
            <EasyInspector
              {...inspectorProps}
              selection={selection}
              onQuickStyle={easyStyle}
              onStyles={updateStyles}
              onReset={resetAppearance}
              onMove={move}
              onAdd={() => {
                setEasyAddGroup('elements');
                setEasyPanel('add');
              }}
              onSelect={(block) => {
                if (selection) select({ ...selection, block });
              }}
            />
          ) : (
            <DesignInspector {...inspectorProps} />
          )}
        </aside>
      </div>
      <MediaPicker
        protectedUrls={protectedThemeImages}
        libraryUrl={`/admin/themes/${studio.id}/assets`}
        title="Theme images"
        description="These images belong to this theme and are included in its export."
        emptyMessage="No theme images yet. Upload an image to get started."
        onRemove={async (image) => {
          const response = await fetch(`/admin/themes/${studio.id}/assets/${image.id}/delete`, {
            method: 'POST',
            headers: { Accept: 'application/json', 'X-CSRF-TOKEN': csrfToken || '' },
          });
          if (!response.ok) {
            const result = await response.json();
            throw new Error(result.error || 'The image could not be deleted.');
          }
        }}
        open={picker}
        onClose={() => setPicker(false)}
        onPick={(image) => applyImage(image.url, image.alt || image.title)}
        onUpload={(file) => void upload(file)}
        uploading={uploading}
        idPrefix="studio-"
      />
      {aiPanel && (
        <ThemeAiPanel
          id={studio.id}
          csrfToken={csrfToken}
          onClose={() => setAiPanel(false)}
          collaboration={aiSync}
        />
      )}
    </div>
  );
}
