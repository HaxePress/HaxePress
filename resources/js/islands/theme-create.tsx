import ThemeCreate from '../pages/Admin/ThemeCreate';
import { PageProvider } from '../page';
import { mountReact, type IslandContext } from '../island-react';

export function mount(
  element: HTMLElement,
  props: IslandContext & {
    baseDocument: Parameters<typeof ThemeCreate>[0]['baseDocument'];
    csrfToken: string;
  },
) {
  const page = {
    props: { csrfToken: props.csrfToken },
    url: `${window.location.pathname}${window.location.search}`,
    component: 'Admin/ThemeCreate',
  };
  return mountReact(
    element,
    props,
    <PageProvider value={page}>
      <ThemeCreate baseDocument={props.baseDocument} />
    </PageProvider>,
  );
}
