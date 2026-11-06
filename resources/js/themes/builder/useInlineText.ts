import { useEffect, useRef, useState, type HTMLAttributes, type KeyboardEvent } from 'react';
import { editableText } from './friendly-presets';
import type { DesignBlock, DesignSelection } from './types';

export default function useInlineText(
  enabled: boolean,
  onCommit: (target: DesignSelection, text: string) => void,
) {
  const [id, setId] = useState('');
  const [revisions, setRevisions] = useState<Record<string, number>>({});
  const active = useRef<{ target: DesignSelection; node: DesignBlock } | null>(null);
  const original = useRef('');
  const commit = useRef(onCommit);
  commit.current = onCommit;
  function finish(save: boolean) {
    const current = active.current;
    if (!current) return;
    const element = document.querySelector<HTMLElement>(`[data-design-node="${current.node.id}"]`);
    const text = (element?.innerText || '').slice(0, 16000);
    active.current = null;
    if (save && text !== original.current) commit.current(current.target, text);
    setId('');
    setRevisions((previous) => ({
      ...previous,
      [current.node.id]: (previous[current.node.id] || 0) + 1,
    }));
  }
  useEffect(() => {
    if (!id) return;
    const element = document.querySelector<HTMLElement>(`[data-design-node="${id}"]`);
    if (!element) return;
    element.focus();
    const range = document.createRange();
    range.selectNodeContents(element);
    const selection = window.getSelection();
    selection?.removeAllRanges();
    selection?.addRange(range);
  }, [id]);
  useEffect(() => {
    if (!enabled) finish(true);
  }, [enabled]);
  function start(node: DesignBlock, target: DesignSelection) {
    if (!enabled || !editableText(node) || (node.type === 'heading' && Boolean(node.href))) return;
    if (active.current) finish(true);
    active.current = { target, node };
    original.current = node.text;
    setId(node.id);
  }
  function attributes(
    node: DesignBlock,
  ): Pick<
    HTMLAttributes<Element>,
    'contentEditable' | 'suppressContentEditableWarning' | 'onBlur' | 'onKeyDown'
  > {
    if (node.id !== id) return {};
    return {
      contentEditable: 'plaintext-only',
      suppressContentEditableWarning: true,
      onBlur: () => finish(true),
      onKeyDown: (event: KeyboardEvent) => {
        if (event.key === 'Escape') {
          event.preventDefault();
          event.stopPropagation();
          finish(false);
        } else if (event.key === 'Enter' && !event.shiftKey && node.type !== 'text') {
          event.preventDefault();
          event.stopPropagation();
          event.currentTarget instanceof HTMLElement && event.currentTarget.blur();
        } else event.stopPropagation();
      },
    };
  }
  return { start, attributes, id, revisions };
}
