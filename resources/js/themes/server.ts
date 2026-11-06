import { realpath } from 'node:fs/promises';
import { resolve, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import type { ThemeModule } from './types';

/** Resolve installed theme code from the SSR process's configured storage root. */
export async function serverThemeModule(url: string): Promise<ThemeModule> {
  const match =
    /^\/(?:admin\/)?extension-assets\/(theme-[a-z0-9-]+)\/([A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*)\/([A-Za-z0-9_./-]+\.(?:mjs|js))$/.exec(
      url,
    );
  if (!match || match[3].split('/').some((part) => !part || part.startsWith('.'))) {
    throw new Error('Invalid theme renderer address.');
  }
  const storage = process.env.CMS_STORAGE_PATH || 'storage';
  const root = await realpath(resolve(storage, 'extensions/installed'));
  const file = await realpath(resolve(root, match[2], 'public', match[3]));
  if (!file.startsWith(`${root}${sep}`))
    throw new Error('Theme renderer is outside installed storage.');
  return import(/* @vite-ignore */ pathToFileURL(file).href);
}
