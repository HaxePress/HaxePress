// The references dialog of the media library. The server-rendered "References"
// buttons carry `data-media-references="ID"`; when a check finds that an image's
// deletion state changed, the server renders the gallery again. The island sits
// inside that gallery fragment, so each render mounts it with current props.
import { useEffect, useRef, useState } from 'react';
import MediaReferences from '../components/MediaReferences';
import { mountReact, type IslandContext } from '../island-react';
import type { MediaImage } from '../types';

interface ReferenceImage {
  id: number;
  filename: string;
  title: string;
  alt: string;
  url: string;
  canDelete: boolean;
  verified: boolean;
}

declare global {
  interface Window {
    Wellout?: { swap: (name: string, url: string, init?: RequestInit, push?: boolean) => void };
  }
}

function asMediaImage(image: ReferenceImage): MediaImage {
  return {
    id: image.id,
    filename: image.filename,
    title: image.title,
    alt: image.alt,
    url: image.url,
  } as MediaImage;
}

function MediaReferencesDialog({ images }: { images: ReferenceImage[] }) {
  const [image, setImage] = useState<ReferenceImage | null>(null);
  const changed = useRef(false);

  useEffect(() => {
    function open(event: MouseEvent) {
      const button = (event.target as Element | null)?.closest<HTMLElement>(
        '[data-media-references]',
      );
      if (!button) return;
      const id = Number(button.dataset.mediaReferences);
      const found = images.find((candidate) => candidate.id === id);
      if (found) setImage(found);
    }
    document.addEventListener('click', open);
    return () => document.removeEventListener('click', open);
  }, [images]);

  function close() {
    setImage(null);
    if (changed.current) {
      changed.current = false;
      if (window.Wellout) window.Wellout.swap('media-workspace', window.location.href);
      else window.location.reload();
    }
  }

  return (
    <MediaReferences
      image={image ? asMediaImage(image) : null}
      onClose={close}
      onChecked={(id, canDelete, verified) => {
        const checked = images.find((candidate) => candidate.id === id);
        if (checked && (checked.canDelete !== canDelete || checked.verified !== verified)) {
          changed.current = true;
        }
      }}
    />
  );
}

export function mount(element: HTMLElement, props: IslandContext & { images: ReferenceImage[] }) {
  const unmount = mountReact(element, props, <MediaReferencesDialog images={props.images} />);
  // A fragment swap replaces this island with a new one; stop listening for its buttons.
  const release = () => {
    if (element.isConnected) return;
    document.removeEventListener('well:swapped', release);
    void unmount.then((stop) => stop());
  };
  document.addEventListener('well:swapped', release);
  return unmount;
}
