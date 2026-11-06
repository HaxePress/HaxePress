import assert from 'node:assert/strict';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
import WebSocket from 'ws';

const environment = {
  HXPRESS_URL: process.env.TEST_URL,
  HXPRESS_THEME_ID: process.env.TEST_THEME_ID,
  HXPRESS_MCP_TOKEN: process.env.TEST_MCP_TOKEN,
};
class WebSocketTransport {
  async start() {
    const url = new URL(
      '/mcp/themes/' + environment.HXPRESS_THEME_ID + '/ws',
      environment.HXPRESS_URL,
    );
    url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
    this.socket = new WebSocket(url, {
      headers: { Authorization: 'Bearer ' + environment.HXPRESS_MCP_TOKEN },
      maxPayload: 10 * 1024 * 1024,
    });
    this.socket.on('message', (source) => {
      try {
        this.onmessage?.(JSON.parse(source.toString()));
      } catch (error) {
        this.onerror?.(error);
      }
    });
    this.socket.on('error', (error) => this.onerror?.(error));
    this.socket.on('close', () => this.onclose?.());
    await new Promise((resolve, reject) => {
      this.socket.once('open', resolve);
      this.socket.once('error', reject);
    });
  }
  send(message) {
    return new Promise((resolve, reject) => {
      this.socket.send(JSON.stringify(message), (error) => (error ? reject(error) : resolve()));
    });
  }
  async close() {
    if (!this.socket || this.socket.readyState === WebSocket.CLOSED) return;
    const closed = new Promise((resolve) => this.socket.once('close', resolve));
    const timeout = setTimeout(() => this.socket.terminate(), 1000);
    this.socket.close();
    await closed;
    clearTimeout(timeout);
  }
}
let latestVersion;
for (const kind of ['http', 'websocket']) {
  for (const mode of ['legacy', { pin: '2026-07-28' }]) {
    const client = new Client(
      { name: 'haxepress-integration', version: '1.0.0' },
      {
        versionNegotiation: { mode },
      },
    );
    let transport;
    if (kind === 'http') {
      transport = new StreamableHTTPClientTransport(
        new URL('/mcp/themes/' + environment.HXPRESS_THEME_ID, environment.HXPRESS_URL),
        { requestInit: { headers: { Authorization: 'Bearer ' + environment.HXPRESS_MCP_TOKEN } } },
      );
    } else {
      transport = new WebSocketTransport();
    }
    let errors = '';
    transport.stderr?.on('data', (data) => {
      errors += data.toString();
    });
    async function call(name, args = {}) {
      return client.callTool({ name, arguments: args });
    }
    function data(value) {
      assert.ok(!value.isError, value.content?.[0]?.text);
      return value.structuredContent || JSON.parse(value.content[0].text);
    }
    try {
      await client.connect(transport);
      if (client.getProtocolEra() === 'modern') await client.discover();
      else await client.ping();
      const { tools } = await client.listTools();
      assert.deepEqual(
        tools.map((tool) => tool.name),
        [
          'get_design_guide',
          'get_design',
          'edit_design',
          'replace_design',
          'search_media',
          'get_collection_schema',
          'read_media_image',
          'search_theme_assets',
          'read_theme_asset_image',
          'upload_theme_image',
          'verify_theme_image',
        ],
      );
      assert.ok(!tools.some((tool) => /publish|activate|shell|execute|grant/i.test(tool.name)));
      const guide = data(await call('get_design_guide'));
      assert.equal(guide.schema, 2);
      assert.equal(guide.limits.nodes, 2048);
      const resources = await client.listResources();
      assert.equal(resources.resources[0].uri, 'haxepress://theme/design-guide');
      const read = await client.readResource({ uri: 'haxepress://theme/design-guide' });
      assert.equal(JSON.parse(read.contents[0].text).schema, 2);
      let snapshot = data(await call('get_design'));
      const collection = data(
        await call('get_collection_schema', { key: snapshot.collections[0].key }),
      );
      assert.ok(Array.isArray(collection.collection.fields));
      const before = snapshot.theme.version;
      assert.equal(snapshot.theme.id, environment.HXPRESS_THEME_ID);
      let saved = data(
        await call('edit_design', {
          expectedVersion: before,
          operations: [
            {
              action: 'section',
              target: { scope: 'Home', section: '' },
              preset: 'welcome',
              name: 'AI introduction',
            },
          ],
        }),
      );
      const section = saved.created[0].section;
      assert.equal(saved.version, before + 1);
      snapshot = data(await call('get_design'));
      const heading = snapshot.theme.document.templates.Home.find((entry) => entry.id === section)
        .blocks[0].children[0];
      saved = data(
        await call('edit_design', {
          expectedVersion: snapshot.theme.version,
          operations: [
            {
              action: 'update',
              target: { scope: 'Home', section, block: heading.id },
              values: { text: 'Designed through MCP' },
            },
            {
              action: 'style',
              target: { scope: 'Home', section, block: heading.id },
              breakpoint: 'mobile',
              values: { 'font-size': '34px' },
            },
            { action: 'tokens', values: { accent: '#225599' } },
          ],
        }),
      );
      assert.equal(saved.version, before + 2);
      const stale = await call('edit_design', {
        expectedVersion: before,
        operations: [{ action: 'tokens', values: { accent: '#ff0000' } }],
      });
      assert.equal(stale.isError, true);
      const invalid = await call('edit_design', {
        expectedVersion: saved.version,
        operations: [
          { action: 'tokens', values: { accent: '#ff0000' } },
          {
            action: 'move',
            target: { scope: 'Home', section, block: heading.id },
            destination: { scope: 'Home', section, block: heading.id, position: 'inside' },
          },
        ],
      });
      assert.equal(invalid.isError, true);
      snapshot = data(await call('get_design'));
      assert.equal(snapshot.theme.version, saved.version);
      assert.equal(snapshot.theme.document.tokens.accent, '#225599');
      assert.equal(
        snapshot.theme.document.templates.Home.find((entry) => entry.id === section).blocks[0]
          .children[0].styles.mobile.normal['font-size'],
        '34px',
      );
      const scoped = data(await call('get_design', { scope: 'Home' }));
      assert.equal(
        scoped.sections.find((entry) => entry.id === section).blocks[0].children[0].text,
        'Designed through MCP',
      );
      assert.equal(scoped.document, undefined);
      const replacement = structuredClone(snapshot.theme.document);
      replacement.templates.AIPage = [];
      replacement.templateMeta.AIPage = { label: 'AI page', fallback: 'Page' };
      saved = data(
        await call('replace_design', {
          expectedVersion: saved.version,
          name: 'MCP generated draft',
          document: replacement,
        }),
      );
      snapshot = data(await call('get_design'));
      assert.equal(snapshot.theme.document.templateMeta.AIPage.label, 'AI page');
      const invalidDocument = structuredClone(snapshot.theme.document);
      invalidDocument.templates.Home[0].blocks[0].href = 'javascript:alert(1)';
      assert.equal(
        (
          await call('replace_design', {
            expectedVersion: saved.version,
            document: invalidDocument,
          })
        ).isError,
        true,
      );
      const media = data(await call('search_media', { query: '' }));
      assert.ok(media.items.length > 0 && media.items.length <= 24);
      const image = await call('read_media_image', {
        id: Number(process.env.TEST_MCP_IMAGE_ID),
      });
      assert.ok(!image.isError);
      assert.equal(image.content[0].type, 'image');
      assert.equal(
        Buffer.from(image.content[0].data, 'base64').length,
        Number(process.env.TEST_MCP_IMAGE_BYTES),
      );
      const stagedImage = await call('upload_theme_image', {
        data: image.content[0].data,
        name: 'AI theme image.png',
      });
      const pending = data(stagedImage);
      const preview = stagedImage.content.find((entry) => entry.type === 'image');
      assert.equal(preview?.data, image.content[0].data);
      const png = Buffer.from(preview.data, 'base64');
      const ownedImage = data(
        await call('verify_theme_image', {
          ...pending,
          width: png.readUInt32BE(16),
          height: png.readUInt32BE(20),
        }),
      );
      assert.ok(ownedImage.url.startsWith('/theme-assets/' + environment.HXPRESS_THEME_ID + '/'));
      const ownedLibrary = data(await call('search_theme_assets'));
      assert.ok(ownedLibrary.images.some((item) => item.id === ownedImage.id));
      const ownedRead = await call('read_theme_asset_image', { id: ownedImage.id });
      assert.ok(!ownedRead.isError);
      assert.equal(ownedRead.content[0].data, image.content[0].data);
      latestVersion = saved.version;
    } catch (error) {
      throw new Error(
        kind + ' / ' + JSON.stringify(mode) + ': ' + error.message + '\n' + errors.slice(-1000),
      );
    } finally {
      await client.close();
    }
  }
}
process.stdout.write(
  JSON.stringify({
    modern: true,
    legacy: true,
    hosted: true,
    websocket: true,
    version: latestVersion,
    imageRead: true,
  }) + '\n',
);
