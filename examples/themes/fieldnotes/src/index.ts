import type { ThemeDefinition, ThemeRuntime } from '../../../../resources/js/themes/types';
import { createSiteLayout } from './layouts/SiteLayout';
import { createContentCard } from './components/ContentCard';
import { createHome } from './pages/Home';
import { createContentIndex } from './pages/ContentIndex';
import { createContentDetail } from './pages/ContentDetail';
import { createPage } from './pages/Page';
import { createAbout } from './pages/About';
import { createNotFound } from './pages/NotFound';

export function createTheme(runtime: ThemeRuntime): ThemeDefinition {
  const layout = createSiteLayout(runtime);
  const contentCard = createContentCard(runtime);
  return {
    pages: {
      Home: createHome(runtime, layout, contentCard),
      ContentIndex: createContentIndex(runtime, layout, contentCard),
      ContentDetail: createContentDetail(runtime, layout, contentCard),
      Page: createPage(runtime, layout),
      About: createAbout(runtime, layout),
      NotFound: createNotFound(runtime, layout),
    },
  };
}
