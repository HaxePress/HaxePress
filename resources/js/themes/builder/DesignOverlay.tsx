import { useLayoutEffect, useRef, useState, type PointerEvent } from 'react';
import { useTranslation } from '../../i18n';
import type { DesignSelection, ThemeDocument } from './types';

export default function DesignOverlay({
  selection,
  document: design,
  onResize,
  simple = false,
}: {
  selection: DesignSelection | null;
  document: ThemeDocument;
  simple?: boolean;
  onResize: (selection: DesignSelection, width: number, height: number) => void;
}) {
  const { t } = useTranslation();
  const [box, setBox] = useState<{
    left: number;
    top: number;
    width: number;
    height: number;
  } | null>(null);
  const drag = useRef<{ x: number; y: number; width: number; height: number } | null>(null);
  useLayoutEffect(() => {
    if (!selection) {
      setBox(null);
      return;
    }
    const id = selection.block || selection.section;
    const element = document.querySelector<HTMLElement>('[data-design-node="' + id + '"]');
    if (!element) {
      setBox(null);
      return;
    }
    const update = () => {
      if (drag.current) return;
      const rect = element.getBoundingClientRect();
      setBox({
        left: rect.left + window.scrollX,
        top: rect.top + window.scrollY,
        width: rect.width,
        height: rect.height,
      });
    };
    update();
    const observer = new ResizeObserver(update);
    observer.observe(element);
    window.addEventListener('scroll', update, true);
    window.addEventListener('resize', update);
    return () => {
      observer.disconnect();
      window.removeEventListener('scroll', update, true);
      window.removeEventListener('resize', update);
    };
  }, [selection, design]);
  if (!box || !selection) return null;
  function begin(event: PointerEvent<HTMLButtonElement>) {
    event.preventDefault();
    event.stopPropagation();
    event.currentTarget.setPointerCapture(event.pointerId);
    drag.current = { x: event.clientX, y: event.clientY, width: box!.width, height: box!.height };
  }
  function move(event: PointerEvent<HTMLButtonElement>) {
    const start = drag.current;
    if (!start) return;
    setBox((previous) =>
      previous
        ? {
            ...previous,
            width: Math.max(1, start.width + event.clientX - start.x),
            height: Math.max(1, start.height + event.clientY - start.y),
          }
        : previous,
    );
  }
  function end(event: PointerEvent<HTMLButtonElement>) {
    if (!drag.current) return;
    const start = drag.current;
    drag.current = null;
    event.currentTarget.releasePointerCapture(event.pointerId);
    onResize(
      selection!,
      Math.max(1, start.width + event.clientX - start.x),
      Math.max(1, start.height + event.clientY - start.y),
    );
  }
  return (
    <div className="hp-design-selection-overlay" style={box}>
      {!simple && (
        <span>
          {Math.round(box.width)} × {Math.round(box.height)}
        </span>
      )}
      <button
        type="button"
        className="hp-design-resize-handle"
        aria-label={t('Resize selected element')}
        title={t('Drag to resize')}
        onPointerDown={begin}
        onPointerMove={move}
        onPointerUp={end}
        onKeyDown={(event) => {
          const changes: Record<string, [number, number]> = {
            ArrowRight: [10, 0],
            ArrowLeft: [-10, 0],
            ArrowDown: [0, 10],
            ArrowUp: [0, -10],
          };
          const change = changes[event.key];
          if (!change) return;
          event.preventDefault();
          const step = event.shiftKey ? 5 : 1;
          onResize(
            selection,
            Math.max(1, box.width + change[0] * step),
            Math.max(1, box.height + change[1] * step),
          );
        }}
        onPointerCancel={() => {
          drag.current = null;
        }}
      />
    </div>
  );
}
