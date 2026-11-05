import { createInertiaApp } from '@inertiajs/react';
import type { Page } from '@inertiajs/core';
import { createRoot, hydrateRoot } from 'react-dom/client';
import { resolvePage } from './resolve';
import { prepareTheme } from './themes/registry';
import { ThemePreviewCapture } from './themes/capture-preview';
import type { SharedProps } from './types';
import '../css/site.css';
import '../css/cms.css';
import '../css/admin.css';
import '../css/setup.css';
import '../css/themes/simple.css';
import '../css/themes/builder.css';
import '../css/theme-builder.css';
import '../css/easy-builder.css';

async function start() {
  const element = document.getElementById('app');
  if (!element?.dataset.page) throw new Error('Initial page data is missing.');
  const page = JSON.parse(element.dataset.page) as Page<SharedProps>;
  if (!page.component.startsWith('Admin/')) await prepareTheme(page.props.theme);
  await createInertiaApp({
    page,
    resolve: resolvePage,
    progress: { color: '#28533f' },
    setup({ el, App, props }) {
      const application = (
        <>
          <App {...props} />
          <ThemePreviewCapture stylesheet={page.props.theme?.stylesheet} />
        </>
      );
      if (el.hasChildNodes()) hydrateRoot(el, application);
      else createRoot(el).render(application);
    },
  });
}
void start();
