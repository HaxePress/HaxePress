import ThemeBuilder from '../pages/Admin/ThemeBuilder';
import { PageProvider } from '../page';
import { mountReact, type IslandContext } from '../island-react';

export function mount(
  element: HTMLElement,
  props: IslandContext & {
    studio: Parameters<typeof ThemeBuilder>[0]['studio'];
    csrfToken: string;
    auth: unknown;
  },
) {
  const page = {
    props: { csrfToken: props.csrfToken, auth: props.auth },
    url: `${window.location.pathname}${window.location.search}`,
    component: 'Admin/ThemeBuilder',
  };
  return mountReact(
    element,
    props,
    <PageProvider value={page}>
      <ThemeBuilder studio={props.studio} />
    </PageProvider>,
  );
}
