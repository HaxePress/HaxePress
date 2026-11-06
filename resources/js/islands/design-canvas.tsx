import DesignPage from '../themes/builder/DesignPage';
import { PageProvider } from '../page';
import { mountReact, type IslandContext } from '../island-react';

/** The editable design canvas inside the theme builder's preview frame. */
export function mount(
  element: HTMLElement,
  props: IslandContext & {
    name: string;
    url: string;
    pageProps: Record<string, unknown>;
    shared: Record<string, unknown>;
  },
) {
  const page = { props: props.shared, url: props.url, component: props.name };
  return mountReact(
    element,
    props,
    <PageProvider value={page}>
      <DesignPage name={props.name} pageProps={props.pageProps} />
    </PageProvider>,
  );
}
