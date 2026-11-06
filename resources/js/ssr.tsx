import { createServer } from 'node:http';
import { createInertiaApp } from '@inertiajs/react';
import type { Page } from '@inertiajs/core';
import { renderToString } from 'react-dom/server';
import { resolvePage } from './resolve';
import { prepareTheme } from './themes/registry';
import { serverThemeModule } from './themes/server';
import type { SharedProps } from './types';

const port = Number(process.env.INERTIA_SSR_PORT || 13714);
createServer(async (request, response) => {
  response.setHeader('Content-Type', 'application/json');
  if (request.method === 'GET' && request.url === '/health') {
    response.end(JSON.stringify({ status: 'OK' }));
    return;
  }
  if (request.method !== 'POST' || request.url !== '/render') {
    response.writeHead(404);
    response.end(JSON.stringify({ error: 'Not found' }));
    return;
  }
  try {
    const chunks: Buffer[] = [];
    let size = 0;
    for await (const chunk of request) {
      const bytes = Buffer.from(chunk);
      size += bytes.length;
      if (size > 4 * 1024 * 1024) {
        response.writeHead(413);
        response.end(JSON.stringify({ error: 'Page data is too large' }));
        return;
      }
      chunks.push(bytes);
    }
    const page = JSON.parse(Buffer.concat(chunks).toString('utf8')) as Page<SharedProps>;
    const theme = page.component.startsWith('Admin/')
      ? null
      : await prepareTheme(page.props.theme, serverThemeModule);
    const rendered = await createInertiaApp({
      page,
      resolve: (name) => resolvePage(name, theme),
      render: renderToString,
      setup: ({ App, props }) => <App {...props} />,
    });
    response.end(JSON.stringify(rendered));
  } catch (error) {
    console.error('Inertia SSR failed:', error instanceof Error ? error.message : 'Invalid page');
    response.writeHead(500);
    response.end(JSON.stringify({ error: 'Unable to render page' }));
  }
}).listen(port, '127.0.0.1', () => console.log(`Inertia React SSR listening on 127.0.0.1:${port}`));
