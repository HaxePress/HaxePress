import ContentEditor, { type ContentEditorData } from '../components/ContentEditor';
import { mountReact, type IslandContext } from '../island-react';

export function mount(
  element: HTMLElement,
  props: IslandContext & {
    csrfToken: string;
    siteUrl: string;
    error: string;
    editor: ContentEditorData;
  },
) {
  return mountReact(
    element,
    props,
    <ContentEditor
      editor={props.editor}
      csrfToken={props.csrfToken}
      siteUrl={props.siteUrl}
      error={props.error}
    />,
  );
}
