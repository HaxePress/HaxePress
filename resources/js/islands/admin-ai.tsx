import AdminAiControl from '../components/AdminAiControl';
import { mountReact, type IslandContext } from '../island-react';

export function mount(
  element: HTMLElement,
  props: IslandContext & { adminId: number; csrfToken: string },
) {
  return mountReact(
    element,
    props,
    <AdminAiControl adminId={props.adminId} csrfToken={props.csrfToken} />,
  );
}
