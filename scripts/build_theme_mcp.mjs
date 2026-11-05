import { build } from 'esbuild';
import { mkdir, readFile } from 'node:fs/promises';
import { resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const release = JSON.parse(await readFile(new URL('../cms.json', import.meta.url), 'utf8'));
const root = new URL('../', import.meta.url);
const publicRoot = process.env.CMS_PUBLIC_PATH
  ? pathToFileURL(resolve(process.env.CMS_PUBLIC_PATH) + sep)
  : new URL('public/', root);
await mkdir(new URL('mcp/', publicRoot), { recursive: true });
await build({
  entryPoints: [fileURLToPath(new URL('mcp/hosted.ts', root))],
  outfile: fileURLToPath(new URL('mcp/hosted.mjs', publicRoot)),
  platform: 'node',
  format: 'esm',
  target: 'node22',
  bundle: true,
  define: { __CMS_VERSION__: JSON.stringify(release.version) },
});
console.log('Built the site-hosted HaxePress MCP server.');
