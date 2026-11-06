// Captures theme previews in a headless Chrome or Chromium on the site's host,
// over the DevTools protocol, so an AI can look at the design it edits. The
// browser starts on the first capture and stops after two idle minutes.
import { spawn, type ChildProcess } from 'node:child_process';
import { existsSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { basename, join } from 'node:path';

export interface Viewport {
  width: number;
  height: number;
  mobile: boolean;
}

export interface Capture {
  image: string;
  status: number;
  title: string;
  height: number;
  headings: string[];
  links: { href: string; text: string }[];
}

const IDLE_MS = 120_000;
const MAX_HEIGHT = 8000;
const LOAD_MS = 20_000;

/**
 * The configured browser, else Chrome's headless shell cached by Puppeteer,
 * else an installed Chrome or Chromium. Browsers that relaunch themselves,
 * such as Brave or Edge, are not used: a relaunched process would outlive
 * the MCP host.
 */
function findBrowser(): string | null {
  const configured = process.env.HAXEPRESS_CHROME;
  if (configured) return existsSync(configured) ? configured : null;
  const cache = join(homedir(), '.cache', 'puppeteer', 'chrome-headless-shell');
  if (existsSync(cache)) {
    for (const version of readdirSync(cache).sort().reverse()) {
      for (const platform of readdirSync(join(cache, version))) {
        const shell = join(cache, version, platform, 'chrome-headless-shell');
        if (existsSync(shell)) return shell;
      }
    }
  }
  const installed = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/usr/bin/chrome-headless-shell',
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/snap/bin/chromium',
  ];
  return installed.find((path) => existsSync(path)) ?? null;
}

/** A DevTools protocol connection: commands with replies, and events. */
class DevTools {
  private next = 0;
  private readonly pending = new Map<
    number,
    { resolve: (value: any) => void; reject: (error: Error) => void }
  >();
  private readonly listeners = new Set<(method: string, params: any, session?: string) => void>();

  private constructor(private readonly socket: WebSocket) {
    socket.addEventListener('message', (event) => {
      const message = JSON.parse(String(event.data));
      if (message.id !== undefined) {
        const waiting = this.pending.get(message.id);
        this.pending.delete(message.id);
        if (message.error) waiting?.reject(new Error(message.error.message));
        else waiting?.resolve(message.result);
        return;
      }
      for (const listener of this.listeners)
        listener(message.method, message.params, message.sessionId);
    });
    socket.addEventListener('close', () => {
      for (const waiting of this.pending.values()) waiting.reject(new Error('The browser closed.'));
      this.pending.clear();
    });
  }

  static open(url: string): Promise<DevTools> {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(url);
      socket.addEventListener('open', () => resolve(new DevTools(socket)), { once: true });
      socket.addEventListener(
        'error',
        () => reject(new Error('The browser did not accept a connection.')),
        {
          once: true,
        },
      );
    });
  }

  send(method: string, params: object = {}, sessionId?: string): Promise<any> {
    const id = ++this.next;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.send(JSON.stringify({ id, method, params, ...(sessionId && { sessionId }) }));
    });
  }

  /** Resolves on the next `method` event of a session, or fails after `timeout` milliseconds. */
  event(method: string, sessionId: string, timeout: number): Promise<any> {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.listeners.delete(listener);
        reject(new Error('The preview page did not finish loading in time.'));
      }, timeout);
      const listener = (name: string, params: any, session?: string) => {
        if (name !== method || session !== sessionId) return;
        clearTimeout(timer);
        this.listeners.delete(listener);
        resolve(params);
      };
      this.listeners.add(listener);
    });
  }

  listen(listener: (method: string, params: any, session?: string) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  close() {
    this.socket.close();
  }
}

let running: { process: ChildProcess; tools: DevTools; profile: string } | null = null;
let starting: Promise<{ tools: DevTools }> | null = null;
let idle: ReturnType<typeof setTimeout> | null = null;
let queue: Promise<unknown> = Promise.resolve();

function stop() {
  if (!running) return;
  const { process: browser, tools, profile } = running;
  running = null;
  tools.close();
  // The browser has nothing to save; a graceful exit can outlast the MCP host's shutdown.
  browser.kill('SIGKILL');
  browser.stderr?.destroy();
  browser.unref();
  try {
    rmSync(profile, { recursive: true, force: true });
  } catch {
    // The browser may still be removing its own files; the system cleans its temporary folder.
  }
}

function launch(): Promise<{ tools: DevTools }> {
  const executable = findBrowser();
  if (!executable) {
    return Promise.reject(
      new Error(
        'Theme previews need Chrome or Chromium on the server. Install one, or set HAXEPRESS_CHROME to its executable.',
      ),
    );
  }
  const profile = mkdtempSync(join(tmpdir(), 'haxepress-preview-'));
  const shell = basename(executable) === 'chrome-headless-shell';
  const browser = spawn(
    executable,
    [
      ...(shell ? [] : ['--headless=new']),
      '--remote-debugging-port=0',
      `--user-data-dir=${profile}`,
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-extensions',
      '--disable-background-networking',
      '--disable-sync',
      '--hide-scrollbars',
      '--mute-audio',
      // Extra flags for hosts that need them, such as --no-sandbox in CI containers.
      ...(process.env.HAXEPRESS_CHROME_ARGS || '').split(/\s+/).filter(Boolean),
      'about:blank',
    ],
    { stdio: ['ignore', 'ignore', 'pipe'] },
  );
  return new Promise((resolve, reject) => {
    let output = '';
    const timer = setTimeout(() => {
      browser.kill();
      reject(new Error('The preview browser did not start.'));
    }, 15_000);
    browser.once('exit', () => {
      clearTimeout(timer);
      if (running?.process === browser) running = null;
      reject(new Error('The preview browser stopped while starting.'));
    });
    browser.stderr?.on('data', async (chunk: Buffer) => {
      if (running?.process === browser) return;
      output += chunk.toString();
      const address = /DevTools listening on (ws:\/\/\S+)/.exec(output);
      if (!address) return;
      clearTimeout(timer);
      try {
        const tools = await DevTools.open(address[1]);
        running = { process: browser, tools, profile };
        resolve({ tools });
      } catch (error) {
        browser.kill();
        reject(error);
      }
    });
  });
}

async function browser(): Promise<DevTools> {
  if (idle) clearTimeout(idle);
  if (running) return running.tools;
  starting ||= launch().finally(() => (starting = null));
  return (await starting).tools;
}

async function evaluate(tools: DevTools, sessionId: string, expression: string): Promise<any> {
  const reply = await tools.send(
    'Runtime.evaluate',
    { expression, awaitPromise: true, returnByValue: true },
    sessionId,
  );
  return reply.result?.value;
}

/**
 * Loads `url` with `headers` at a viewport size and returns a JPEG of the
 * first screen, or of the whole page up to 8,000 pixels, with the page's
 * title, HTTP status, height and links. One capture runs at a time.
 */
export function capture(
  url: string,
  headers: Record<string, string>,
  viewport: Viewport,
  fullPage: boolean,
): Promise<Capture> {
  const run = queue.then(() => captureNow(url, headers, viewport, fullPage));
  queue = run.catch(() => undefined);
  return run.finally(() => {
    if (idle) clearTimeout(idle);
    idle = setTimeout(stop, IDLE_MS);
    // An idle browser never keeps the MCP host running.
    idle.unref();
  });
}

async function captureNow(
  url: string,
  headers: Record<string, string>,
  viewport: Viewport,
  fullPage: boolean,
): Promise<Capture> {
  const tools = await browser();
  const { targetId } = await tools.send('Target.createTarget', { url: 'about:blank' });
  try {
    const { sessionId } = await tools.send('Target.attachToTarget', { targetId, flatten: true });
    let status = 0;
    const unlisten = tools.listen((method, params, session) => {
      if (
        method === 'Network.responseReceived' &&
        session === sessionId &&
        params.type === 'Document'
      )
        status = params.response.status;
    });
    try {
      await tools.send('Page.enable', {}, sessionId);
      await tools.send('Network.enable', {}, sessionId);
      await tools.send('Network.setExtraHTTPHeaders', { headers }, sessionId);
      await tools.send(
        'Emulation.setDeviceMetricsOverride',
        {
          width: viewport.width,
          height: viewport.height,
          deviceScaleFactor: 1,
          mobile: viewport.mobile,
        },
        sessionId,
      );
      await tools.send(
        'Emulation.setTouchEmulationEnabled',
        { enabled: viewport.mobile },
        sessionId,
      );
      const loaded = tools.event('Page.loadEventFired', sessionId, LOAD_MS);
      const navigation = await tools.send('Page.navigate', { url }, sessionId);
      if (navigation.errorText)
        throw new Error(`The preview could not load: ${navigation.errorText}`);
      await loaded;
      await evaluate(
        tools,
        sessionId,
        `document.querySelectorAll('img[loading="lazy"]').forEach((image) => { image.loading = 'eager'; });
        Promise.race([
          Promise.all([
            document.fonts ? document.fonts.ready : null,
            ...[...document.images].filter((image) => !image.complete).map(
              (image) => new Promise((done) => { image.onload = image.onerror = done; })
            )
          ]),
          new Promise((done) => setTimeout(done, 4000))
        ]).then(() => new Promise((done) => requestAnimationFrame(() => setTimeout(done, 100))))`,
      );
      const page = await evaluate(
        tools,
        sessionId,
        `({
          title: document.title,
          height: Math.ceil(Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)),
          headings: [...document.querySelectorAll('h1, h2, h3')].map((heading) => heading.textContent.trim().replace(/\\s+/g, ' ').slice(0, 120)).filter(Boolean).slice(0, 30),
          links: [...new Map([...document.querySelectorAll('a[href]')].map((link) => {
            const target = new URL(link.href, location.href);
            return [target.pathname + target.search, (link.textContent || link.getAttribute('aria-label') || '').trim().replace(/\\s+/g, ' ').slice(0, 80)];
          }).filter(([href]) => href)).entries()].slice(0, 60).map(([href, text]) => ({ href, text }))
        })`,
      );
      const height = fullPage
        ? Math.min(Math.max(page.height, viewport.height), MAX_HEIGHT)
        : viewport.height;
      const shot = await tools.send(
        'Page.captureScreenshot',
        {
          format: 'jpeg',
          quality: 78,
          captureBeyondViewport: fullPage,
          clip: { x: 0, y: 0, width: viewport.width, height, scale: 1 },
        },
        sessionId,
      );
      return {
        image: shot.data,
        status,
        title: page.title,
        height: page.height,
        headings: page.headings,
        links: page.links,
      };
    } finally {
      unlisten();
    }
  } finally {
    await tools.send('Target.closeTarget', { targetId }).catch(() => undefined);
  }
}

/** Stops the preview browser, as the MCP host does when it shuts down. */
export function closeBrowser() {
  if (idle) clearTimeout(idle);
  idle = null;
  stop();
}

process.once('exit', stop);
