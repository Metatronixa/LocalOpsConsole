/**
 * Capture LocalOpsConsole dashboard screenshots via Chrome CDP (no npm deps).
 * Usage: node tools/capture-screenshots.mjs [baseUrl]
 */
import { spawn } from 'node:child_process';
import { accessSync, constants } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');
const outDir = path.join(root, 'website', 'assets', 'img', 'screenshots');
const baseUrl = process.argv[2] || 'http://localhost:8787/';

const chromeCandidates = [
  process.env.CHROME_PATH,
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
].filter(Boolean);

const shots = [
  { file: 'overview.png', module: 'overview', category: 'Overview', caption: 'Overview — health, security, and incidents' },
  { file: 'incidents.png', module: 'incidents', category: 'Incidents', caption: 'Incident Center — correlated alerts' },
  { file: 'security-center.png', module: 'securitycenter', category: 'Security', caption: 'Security Center — posture at a glance' },
  { file: 'security-baseline.png', module: 'securitybaseline', category: 'Security', caption: 'Security Baseline — control audit' },
  { file: 'health-center.png', module: 'healthcenter', category: 'Health', caption: 'Health Center — host health score' },
  { file: 'alerts.png', module: 'alerts', category: 'Monitoring', caption: 'Notification Center — alerts' },
  { file: 'timeline.png', module: 'timeline', category: 'Monitoring', caption: 'Event timeline — correlation trail' },
  { file: 'services.png', module: 'services', category: 'Operations', caption: 'Services — inventory and critical profiles' },
  { file: 'storage.png', module: 'storage', category: 'Operations', caption: 'Storage — capacity and SMART' },
  { file: 'internet-health.png', module: 'internetslow', category: 'Operations', caption: 'Internet Health — connectivity diagnostics' },
  { file: 'system.png', module: 'system', category: 'Performance', caption: 'Live telemetry — CPU, RAM, disk, network' },
  { file: 'automation.png', module: 'automation', category: 'Automation', caption: 'Automation — opt-in playbooks' },
];

function findChrome() {
  for (const p of chromeCandidates) {
    try {
      accessSync(p, constants.X_OK);
      return p;
    } catch {
      try {
        accessSync(p, constants.F_OK);
        return p;
      } catch { /* continue */ }
    }
  }
  return null;
}

async function freePort() {
  return await new Promise((resolve) => {
    const s = createServer();
    s.listen(0, '127.0.0.1', () => {
      const { port } = s.address();
      s.close(() => resolve(port));
    });
  });
}

async function waitForJson(url, attempts = 40) {
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await fetch(url);
      if (res.ok) return await res.json();
    } catch { /* retry */ }
    await sleep(250);
  }
  throw new Error(`CDP endpoint not ready: ${url}`);
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    this.ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        if (msg.error) reject(new Error(msg.error.message || JSON.stringify(msg.error)));
        else resolve(msg.result);
      }
    });
  }

  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }
}

async function main() {
  const chromePath = findChrome();
  if (!chromePath) throw new Error('Chrome/Edge not found');

  await mkdir(outDir, { recursive: true });
  const port = await freePort();
  const userData = path.join(root, 'tools', '.chrome-capture-profile');
  await mkdir(userData, { recursive: true });

  const chrome = spawn(chromePath, [
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${userData}`,
    '--headless=new',
    '--disable-gpu',
    '--hide-scrollbars',
    '--window-size=1440,900',
    '--no-first-run',
    '--no-default-browser-check',
    'about:blank',
  ], { stdio: 'ignore' });

  try {
    await waitForJson(`http://127.0.0.1:${port}/json/version`);
    // Prefer a page target (browser-level WS does not expose Page.*).
    let pageWsUrl = null;
    for (let i = 0; i < 40; i++) {
      const targets = await waitForJson(`http://127.0.0.1:${port}/json/list`);
      const page = (targets || []).find((t) => t.type === 'page' && t.webSocketDebuggerUrl);
      if (page) {
        pageWsUrl = page.webSocketDebuggerUrl;
        break;
      }
      await sleep(250);
    }
    if (!pageWsUrl) throw new Error('No Chrome page target available');

    const ws = new WebSocket(pageWsUrl);
    await new Promise((resolve, reject) => {
      ws.addEventListener('open', resolve);
      ws.addEventListener('error', reject);
    });
    const cdp = new Cdp(ws);

    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: 1440,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false,
    });

    await cdp.send('Page.navigate', { url: baseUrl });
    // Wait for SPA shell + modules
    for (let i = 0; i < 50; i++) {
      const ready = await cdp.send('Runtime.evaluate', {
        expression: `Boolean(window.Router && typeof Router.loadModuleView === 'function' && document.getElementById('sidebar-nav') && document.getElementById('sidebar-nav').children.length > 0)`,
        returnByValue: true,
      });
      if (ready.result && ready.result.value) break;
      await sleep(400);
    }
    await sleep(1200);

    const manifest = [];
    for (const shot of shots) {
      await cdp.send('Runtime.evaluate', {
        expression: `Router.loadModuleView(${JSON.stringify(shot.module)})`,
        awaitPromise: true,
      });
      await sleep(1800);
      // Settle network/UI
      await cdp.send('Runtime.evaluate', {
        expression: `new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))`,
        awaitPromise: true,
      });

      const { data } = await cdp.send('Page.captureScreenshot', {
        format: 'png',
        fromSurface: true,
        captureBeyondViewport: false,
      });
      const filePath = path.join(outDir, shot.file);
      await writeFile(filePath, Buffer.from(data, 'base64'));
      console.log(`wrote ${shot.file}`);
      manifest.push({ ...shot, src: `assets/img/screenshots/${shot.file}` });
    }

    await writeFile(
      path.join(outDir, 'manifest.json'),
      JSON.stringify({ generatedAt: new Date().toISOString(), baseUrl, shots: manifest }, null, 2)
    );
    console.log(`done — ${manifest.length} screenshots in ${outDir}`);
    ws.close();
  } finally {
    chrome.kill();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
