import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { build } from 'esbuild';
import WebSocket from 'ws';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = new URL('../Export/tests/theme-browser.mjs', import.meta.url);
await mkdir(new URL('../Export/tests/', import.meta.url), { recursive: true });
await build({
  stdin: {
    contents: `export { ThemeDesignerConnection } from './resources/js/themes/builder/ThemeDesignerConnection';
      export { installBrowserTools } from './resources/js/themes/builder/browser-tools';`,
    resolveDir: root,
    sourcefile: 'theme-browser-test.ts',
    loader: 'ts',
  },
  outfile: fileURLToPath(output),
  bundle: true,
  packages: 'external',
  platform: 'node',
  format: 'esm',
});
const registered = new Map();
const context = {
  async registerTool(tool, options) {
    assert.ok(!registered.has(tool.name), 'Duplicate browser tool registration');
    registered.set(tool.name, tool);
    options.signal.addEventListener(
      'abort',
      () => {
        if (registered.get(tool.name) === tool) registered.delete(tool.name);
      },
      { once: true },
    );
  },
};
Object.defineProperty(globalThis, 'window', { value: {}, configurable: true });
Object.defineProperty(globalThis, 'document', {
  value: { modelContext: context },
  configurable: true,
});
Object.defineProperty(globalThis, 'navigator', { value: {}, configurable: true });
Object.defineProperty(globalThis, 'location', {
  value: new URL(process.env.TEST_URL),
  configurable: true,
});
class BrowserWebSocket extends WebSocket {
  constructor(url) {
    super(url, {
      headers: { Cookie: process.env.TEST_BROWSER_COOKIE, Origin: process.env.TEST_URL },
      maxPayload: 10 * 1024 * 1024,
    });
  }
}
Object.defineProperty(globalThis, 'WebSocket', { value: BrowserWebSocket, configurable: true });
const { ThemeDesignerConnection, installBrowserTools } = await import(
  pathToFileURL(fileURLToPath(output))
);
const connection = new ThemeDesignerConnection(process.env.TEST_THEME_ID);
let dirty = false;
let version = 1;
const changes = [];
const unsubscribe = connection.subscribe((event) => {
  if (event.type === 'design_changed') changes.push(event.change);
});
const dispose = installBrowserTools(
  connection,
  () => ({
    themeId: connection.themeId,
    version,
    dirty,
    scope: 'Home',
    selection: null,
  }),
  () => !dirty,
);
function data(result) {
  assert.ok(!result.isError, result.content?.[0]?.text);
  return result.structuredContent || JSON.parse(result.content[0].text);
}
async function waitFor(check, message) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (check()) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error(message);
}
async function permissions(read, edit, media) {
  const response = await fetch(
    new URL('/admin/themes/' + connection.themeId + '/ai/permissions', process.env.TEST_URL),
    {
      method: 'POST',
      headers: {
        Cookie: process.env.TEST_BROWSER_COOKIE,
        'X-CSRF-TOKEN': process.env.TEST_BROWSER_CSRF,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        read: read ? '1' : '0',
        edit: edit ? '1' : '0',
        media: media ? '1' : '0',
      }),
    },
  );
  assert.equal(response.status, 200);
}
try {
  await connection.ready();
  const api = window.haxePress.themeDesigner;
  assert.ok(Object.isFrozen(api));
  assert.ok(!('token' in api) && !('command' in api) && !('script' in api));
  assert.equal((await api.listTools()).length, 11);
  await waitFor(() => registered.size === 11, 'Browser tools were not registered');
  assert.ok(registered.has('haxepress_verify_theme_image'));
  const initial = data(await api.callTool('get_design'));
  version = initial.theme.version;
  assert.equal(initial.theme.id, connection.themeId);
  dirty = true;
  await assert.rejects(
    api.callTool('edit_design', {
      expectedVersion: version,
      operations: [{ action: 'tokens', values: { accent: '#134e4a' } }],
    }),
    /local changes/,
  );
  assert.equal(data(await api.callTool('get_design')).theme.version, version);
  dirty = false;
  const edit = registered.get('haxepress_edit_design');
  const saved = data(
    await edit.execute({
      expectedVersion: version,
      operations: [{ action: 'tokens', values: { accent: '#134e4a' } }],
    }),
  );
  version = saved.version;
  await waitFor(
    () => changes.some((change) => change.version === version),
    'The browser did not receive its saved change',
  );
  assert.equal(data(await api.callTool('get_design')).theme.document.tokens.accent, '#134e4a');
  await permissions(true, false, false);
  await waitFor(
    () =>
      registered.size === 5 &&
      !registered.has('haxepress_edit_design') &&
      !registered.has('haxepress_verify_theme_image'),
    'Revoked browser tools remained registered',
  );
  assert.equal(api.permissions.edit, false);
  assert.equal((await api.listTools()).length, 5);
  await assert.rejects(
    api.callTool('edit_design', {
      expectedVersion: version,
      operations: [{ action: 'tokens', values: { accent: '#ff0000' } }],
    }),
  );
  await permissions(false, false, false);
  await waitFor(() => registered.size === 0, 'Disabled tools remained registered');
  assert.equal((await api.listTools()).length, 0);
  await (await connection.ready()).discover();
  await assert.rejects(api.callTool('get_design'));
  await permissions(true, true, true);
  await waitFor(() => registered.size === 11, 'Restored browser tools were not registered');
  const snapshot = data(await api.callTool('get_design'));
  assert.equal(snapshot.theme.version, version);
  const response = await fetch(new URL('/admin/logout', process.env.TEST_URL), {
    method: 'POST',
    redirect: 'manual',
    headers: {
      Cookie: process.env.TEST_BROWSER_COOKIE,
      'X-CSRF-TOKEN': process.env.TEST_BROWSER_CSRF,
    },
  });
  assert.equal(response.status, 303);
  await assert.rejects(api.callTool('get_design'));
  await waitFor(
    () => connection.status === 'disconnected' && registered.size === 0,
    'Logout retained browser tool access',
  );
  process.stdout.write(
    JSON.stringify({ version, browserApi: true, webMcp: true, permissions: true, logout: true }) +
      '\n',
  );
} finally {
  unsubscribe();
  dispose();
  await connection.close();
  assert.equal(window.haxePress.themeDesigner, undefined);
  assert.equal(registered.size, 0);
}
