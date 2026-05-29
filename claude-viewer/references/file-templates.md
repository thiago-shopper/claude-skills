# file-templates

Bodies of every file the skill writes into `.claude/viewer/`. Each
section header is the path **relative to `.claude/viewer/`**. The only
placeholder is `{{PORT}}` — substitute the user's chosen port before
writing.

If a file contains no `{{PORT}}`, write it verbatim.

---

## `.dockerignore`

```
node_modules
npm-debug.log
.git
.DS_Store
*.md.bak
```

---

## `Dockerfile`

```dockerfile
FROM node:20-alpine

WORKDIR /app

# Cache layer for deps
COPY package.json package-lock.json* ./
RUN npm install --omit=dev --no-audit --no-fund

# Source
COPY server.js ./
COPY lib ./lib
COPY views ./views
COPY public ./public

# Vendor the highlight.js theme out of node_modules so the browser can fetch it offline
RUN mkdir -p public/vendor \
 && cp node_modules/highlight.js/styles/github-dark.css public/vendor/

EXPOSE 3000

CMD ["node", "server.js"]
```

---

## `docker-compose.yml`

```yaml
services:
  viewer:
    build: .
    container_name: claude-viewer
    ports:
      - "${PORT:-{{PORT}}}:3000"
    volumes:
      - ../../:/project:ro
    environment:
      PROJECT_DIR: /project
      PORT: "3000"
      NODE_ENV: production
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/healthz"]
      interval: 30s
      timeout: 3s
      retries: 3
```

The host port defaults to the user's choice; an env var override (`PORT=9000 docker compose up`) still wins.

---

## `package.json`

```json
{
  "name": "claude-viewer",
  "private": true,
  "version": "0.1.0",
  "type": "commonjs",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.19.2",
    "ejs": "^3.1.10",
    "marked": "^12.0.2",
    "highlight.js": "^11.10.0",
    "chokidar": "^3.6.0",
    "ws": "^8.18.0"
  }
}
```

---

## `server.js`

```js
'use strict';

const path = require('path');
const fs = require('fs');
const http = require('http');
const express = require('express');
const { WebSocketServer } = require('ws');
const { marked } = require('marked');
const hljs = require('highlight.js');

const { scanProject } = require('./lib/scanner');
const { categorize } = require('./lib/categorize');
const { searchFiles } = require('./lib/search');
const { startWatcher } = require('./lib/watcher');

const BASE = path.resolve(process.env.PROJECT_DIR || '/project');
const PORT = parseInt(process.env.PORT, 10) || 3000;

// --- markdown rendering ----------------------------------------------------

marked.use({
  gfm: true,
  breaks: false,
  renderer: {
    code({ text, lang }) {
      const valid = lang && hljs.getLanguage(lang) ? lang : 'plaintext';
      const out = hljs.highlight(text, { language: valid, ignoreIllegals: true }).value;
      return `<pre><code class="hljs language-${valid}">${out}</code></pre>\n`;
    }
  }
});

function renderMarkdown(src) {
  return marked.parse(src);
}

function renderJson(src) {
  let pretty;
  try {
    pretty = JSON.stringify(JSON.parse(src), null, 2);
  } catch {
    pretty = src; // not valid JSON; show raw
  }
  const out = hljs.highlight(pretty, { language: 'json' }).value;
  return `<pre><code class="hljs language-json">${out}</code></pre>`;
}

// --- tree assembly ---------------------------------------------------------

const ORDER = [
  'Memory', 'Project Docs', 'Docs',
  'Settings', 'MCP',
  'Plans', 'Skills', 'Agents', 'Commands', 'Hooks',
  '.claude (other)', 'Other'
];

function buildTree(files) {
  const buckets = new Map();
  for (const f of files) {
    const { category, group } = categorize(f.path);
    if (!buckets.has(category)) buckets.set(category, new Map());
    const groups = buckets.get(category);
    const key = group || '_';
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(f);
  }
  const categories = [];
  for (const name of ORDER) {
    if (!buckets.has(name)) continue;
    const groups = [];
    const sortedKeys = [...buckets.get(name).keys()].sort();
    for (const k of sortedKeys) {
      const fs = buckets.get(name).get(k).sort((a, b) => a.name.localeCompare(b.name));
      groups.push({ name: k === '_' ? null : k, files: fs });
    }
    categories.push({ name, groups });
  }
  return { categories };
}

// --- express app -----------------------------------------------------------

const app = express();
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use('/public', express.static(path.join(__dirname, 'public')));

app.get('/', (req, res) => {
  res.render('index');
});

app.get('/healthz', (req, res) => res.json({ ok: true }));

app.get('/api/tree', async (req, res) => {
  try {
    const files = await scanProject(BASE);
    res.json(buildTree(files));
  } catch (err) {
    res.status(500).json({ error: String(err) });
  }
});

function isAllowed(absPath, allowlist) {
  return allowlist.has(absPath);
}

app.get('/api/file', async (req, res) => {
  const rel = String(req.query.path || '');
  if (!rel) return res.status(400).json({ error: 'missing path' });

  const abs = path.resolve(BASE, rel);
  if (!abs.startsWith(BASE + path.sep) && abs !== BASE) {
    return res.status(400).json({ error: 'path outside project' });
  }

  const files = await scanProject(BASE);
  const allow = new Set(files.map(f => path.resolve(BASE, f.path)));
  if (!isAllowed(abs, allow)) {
    return res.status(404).json({ error: 'not in scope' });
  }

  let content;
  try {
    content = await fs.promises.readFile(abs, 'utf8');
  } catch (err) {
    return res.status(500).json({ error: 'read failed: ' + err.message });
  }

  const ext = path.extname(abs).toLowerCase();
  let rendered;
  if (ext === '.md') rendered = renderMarkdown(content);
  else if (ext === '.json') rendered = renderJson(content);
  else rendered = `<pre>${escapeHtml(content)}</pre>`;

  res.json({ path: rel, ext, content, rendered });
});

app.get('/api/search', async (req, res) => {
  const q = String(req.query.q || '').trim();
  if (!q) return res.json({ q, hits: [] });
  try {
    const files = await scanProject(BASE);
    const hits = await searchFiles(BASE, files, q);
    res.json({ q, hits });
  } catch (err) {
    res.status(500).json({ error: String(err) });
  }
});

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// --- http + ws -------------------------------------------------------------

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

const clients = new Set();
wss.on('connection', (ws) => {
  clients.add(ws);
  ws.send(JSON.stringify({ type: 'ready' }));
  ws.on('close', () => clients.delete(ws));
});

function broadcast(msg) {
  const data = JSON.stringify(msg);
  for (const c of clients) {
    if (c.readyState === 1) c.send(data);
  }
}

startWatcher(BASE, (relPath) => {
  broadcast({ type: 'change', path: relPath });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`claude-viewer listening on :${PORT}, BASE=${BASE}`);
});
```

---

## `lib/scanner.js`

```js
'use strict';

const path = require('path');
const fs = require('fs');

const EXCLUDES = new Set([
  'node_modules', '.git', 'dist', 'build',
  '.next', '.nuxt', '.venv', 'venv',
  'target', '.cache', 'coverage', '.turbo', '.parcel-cache'
]);

async function walk(dir, baseDir, predicate, out) {
  let entries;
  try {
    entries = await fs.promises.readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const ent of entries) {
    if (EXCLUDES.has(ent.name)) continue;
    const abs = path.join(dir, ent.name);
    const rel = path.relative(baseDir, abs);
    if (ent.isDirectory()) {
      await walk(abs, baseDir, predicate, out);
    } else if (ent.isFile() && predicate(rel)) {
      try {
        const stat = await fs.promises.stat(abs);
        out.push({
          path: rel.split(path.sep).join('/'),
          name: ent.name,
          ext: path.extname(ent.name).toLowerCase(),
          size: stat.size,
          mtime: stat.mtimeMs
        });
      } catch { /* ignore */ }
    }
  }
}

// Predicates
function isClaudeAsset(rel) {
  if (!rel.startsWith('.claude' + path.sep) && !rel.startsWith('.claude/')) return false;
  return rel.endsWith('.md') || rel.endsWith('.json');
}

function isProjectMd(rel) {
  if (rel.startsWith('.claude' + path.sep) || rel.startsWith('.claude/')) return false;
  return rel.endsWith('.md');
}

async function scanProject(baseDir) {
  const out = [];
  // .claude/ — md + json
  await walk(path.join(baseDir, '.claude'), baseDir, isClaudeAsset, out);
  // root — md only, excluding .claude/
  await walk(baseDir, baseDir, isProjectMd, out);
  // de-dupe by path
  const seen = new Set();
  return out.filter(f => (seen.has(f.path) ? false : (seen.add(f.path), true)));
}

module.exports = { scanProject, EXCLUDES };
```

---

## `lib/categorize.js`

```js
'use strict';

function categorize(relPath) {
  // Case 1: inside .claude/
  if (relPath.startsWith('.claude/')) {
    const rest = relPath.slice('.claude/'.length);
    const parts = rest.split('/');
    const top = parts[0];
    const map = {
      plans:    { category: 'Plans',    group: null },
      skills:   { category: 'Skills',   group: parts[1] || null },
      agents:   { category: 'Agents',   group: null },
      commands: { category: 'Commands', group: parts[1] || null },
      hooks:    { category: 'Hooks',    group: null },
      '.hooks': { category: 'Hooks',    group: null },
      memory:   { category: 'Memory',   group: null }
    };
    if (map[top]) return map[top];
    if (/^settings(\.local)?\.json$/.test(rest)) return { category: 'Settings', group: '.claude' };
    if (/^mcp\.json$/.test(rest))                return { category: 'MCP',      group: null };
    if (/^CLAUDE\.md$/i.test(rest))              return { category: 'Memory',   group: '.claude' };
    return { category: '.claude (other)', group: top || null };
  }

  // Case 2: CLAUDE.md at the project root → Memory
  if (/^CLAUDE\.md$/i.test(relPath)) return { category: 'Memory', group: null };

  // Case 3: top-level .md (README, ARCHITECTURE, CONTRIBUTING, CHANGELOG, ...)
  if (!relPath.includes('/') && relPath.endsWith('.md')) {
    return { category: 'Project Docs', group: null };
  }

  // Case 4: .md anywhere else
  if (relPath.endsWith('.md')) {
    return { category: 'Docs', group: relPath.split('/')[0] };
  }

  return { category: 'Other', group: null };
}

module.exports = { categorize };
```

---

## `lib/search.js`

```js
'use strict';

const path = require('path');
const fs = require('fs');

const MAX_HITS = 50;
const MAX_SNIPPETS_PER_FILE = 3;
const SNIPPET_LEN = 140;

async function searchFiles(baseDir, files, query) {
  const q = query.toLowerCase();
  const hits = [];

  for (const f of files) {
    if (hits.length >= MAX_HITS) break;

    // Name match — always include
    const nameMatch = f.name.toLowerCase().includes(q);

    let content;
    try {
      content = await fs.promises.readFile(path.resolve(baseDir, f.path), 'utf8');
    } catch {
      continue;
    }

    const lower = content.toLowerCase();
    const snippets = [];
    let from = 0;
    while (snippets.length < MAX_SNIPPETS_PER_FILE) {
      const idx = lower.indexOf(q, from);
      if (idx === -1) break;
      const lineStart = content.lastIndexOf('\n', idx) + 1;
      const lineEnd = content.indexOf('\n', idx);
      const lineNo = content.slice(0, idx).split('\n').length;
      const line = content.slice(lineStart, lineEnd === -1 ? undefined : lineEnd);
      const localStart = idx - lineStart;
      // Trim if line is too long
      let text = line;
      let off = 0;
      if (line.length > SNIPPET_LEN) {
        const center = localStart;
        off = Math.max(0, center - SNIPPET_LEN / 2);
        text = line.slice(off, off + SNIPPET_LEN);
      }
      snippets.push({
        line: lineNo,
        text,
        match: [localStart - off, localStart - off + q.length]
      });
      from = idx + q.length;
    }

    if (nameMatch || snippets.length > 0) {
      hits.push({ path: f.path, name: f.name, snippets });
    }
  }

  return hits;
}

module.exports = { searchFiles };
```

---

## `lib/watcher.js`

```js
'use strict';

const path = require('path');
const chokidar = require('chokidar');
const { EXCLUDES } = require('./scanner');

function startWatcher(baseDir, onChange) {
  const excludeRegex = new RegExp(
    '(^|[\\\\/])(' + [...EXCLUDES].map(e => e.replace(/\./g, '\\.')).join('|') + ')([\\\\/]|$)'
  );

  const watcher = chokidar.watch(baseDir, {
    ignored: (p) => excludeRegex.test(p),
    ignoreInitial: true,
    awaitWriteFinish: { stabilityThreshold: 200, pollInterval: 50 },
    persistent: true,
    depth: 99
  });

  const handle = (filePath) => {
    const rel = path.relative(baseDir, filePath).split(path.sep).join('/');
    if (!rel) return;
    // Only emit for files we'd serve
    const inClaude = rel.startsWith('.claude/');
    const isMd = rel.endsWith('.md');
    const isJson = rel.endsWith('.json');
    if (!((inClaude && (isMd || isJson)) || (!inClaude && isMd))) return;
    onChange(rel);
  };

  watcher.on('add', handle);
  watcher.on('change', handle);
  watcher.on('unlink', handle);

  return watcher;
}

module.exports = { startWatcher };
```

---

## `views/index.ejs`

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>.claude viewer</title>
  <link rel="stylesheet" href="/public/vendor/github-dark.css">
  <link rel="stylesheet" href="/public/style.css">
</head>
<body>
  <%- include('partials/topbar') %>
  <div class="layout">
    <aside id="sidebar" class="sidebar">
      <div class="sidebar-loading">loading…</div>
    </aside>
    <main id="viewer" class="viewer">
      <div class="empty">
        <h1>.claude viewer</h1>
        <p>Pick a file on the left, or hit <kbd>Ctrl</kbd>+<kbd>K</kbd> to search.</p>
      </div>
    </main>
  </div>
  <div id="toast" class="toast" hidden></div>
  <script src="/public/app.js"></script>
</body>
</html>
```

---

## `views/partials/topbar.ejs`

```html
<header class="topbar">
  <div class="topbar-left">
    <span class="logo">.claude</span>
    <span class="subtitle">viewer</span>
  </div>
  <div class="topbar-center">
    <input id="search" type="search" placeholder="search in .claude/ and project docs…  (Ctrl+K)" autocomplete="off">
  </div>
  <div class="topbar-right">
    <span id="ws-status" class="ws-status ws-connecting" title="live reload">●</span>
  </div>
</header>
```

---

## `views/partials/sidebar.ejs`

```html
<!-- The sidebar is rendered client-side from /api/tree. This file exists so EJS keeps a place to override later. -->
```

---

## `public/style.css`

```css
:root {
  --bg: #0d1117;
  --bg-elev: #161b22;
  --bg-hover: #21262d;
  --border: #30363d;
  --fg: #e6edf3;
  --fg-mute: #7d8590;
  --accent: #58a6ff;
  --accent-soft: #1f6feb33;
  --green: #3fb950;
  --red: #f85149;
  --yellow: #d29922;
  --mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
  --sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
}

* { box-sizing: border-box; }

html, body { margin: 0; padding: 0; height: 100%; }

body {
  background: var(--bg);
  color: var(--fg);
  font-family: var(--sans);
  font-size: 14px;
  line-height: 1.5;
}

a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
kbd {
  background: var(--bg-elev);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 1px 6px;
  font-family: var(--mono);
  font-size: 12px;
}

/* Topbar */
.topbar {
  position: sticky; top: 0; z-index: 10;
  display: flex; align-items: center;
  height: 48px;
  padding: 0 16px;
  background: var(--bg-elev);
  border-bottom: 1px solid var(--border);
  gap: 16px;
}
.topbar-left { display: flex; align-items: baseline; gap: 8px; min-width: 200px; }
.logo { font-family: var(--mono); font-weight: 600; color: var(--accent); }
.subtitle { color: var(--fg-mute); font-size: 12px; }
.topbar-center { flex: 1; }
#search {
  width: 100%; max-width: 560px;
  height: 32px;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 6px;
  color: var(--fg);
  padding: 0 10px;
  font-family: var(--sans);
}
#search:focus { outline: none; border-color: var(--accent); }
.topbar-right { min-width: 60px; text-align: right; }
.ws-status { font-size: 18px; }
.ws-connecting { color: var(--fg-mute); }
.ws-open { color: var(--green); }
.ws-error { color: var(--red); }

/* Layout */
.layout {
  display: grid;
  grid-template-columns: 280px 1fr;
  height: calc(100vh - 48px);
}
.sidebar {
  overflow-y: auto;
  background: var(--bg-elev);
  border-right: 1px solid var(--border);
  padding: 8px 0;
}
.sidebar-loading { padding: 12px 16px; color: var(--fg-mute); }
.viewer {
  overflow-y: auto;
  padding: 24px 32px;
}
.empty { color: var(--fg-mute); max-width: 600px; margin: 80px auto 0; text-align: center; }
.empty h1 { color: var(--fg); }

/* Sidebar tree */
.category {
  padding: 6px 12px 4px;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: var(--fg-mute);
  user-select: none;
  cursor: pointer;
}
.category::before { content: "▾ "; display: inline-block; width: 12px; }
.category.collapsed::before { content: "▸ "; }
.group {
  padding: 2px 12px 2px 24px;
  color: var(--fg-mute);
  font-size: 12px;
  cursor: pointer;
  user-select: none;
}
.group::before { content: "▾ "; display: inline-block; width: 12px; }
.group.collapsed::before { content: "▸ "; }
.file {
  display: flex; align-items: center;
  padding: 3px 12px 3px 36px;
  font-size: 13px;
  cursor: pointer;
  color: var(--fg);
  border-left: 2px solid transparent;
}
.file:hover { background: var(--bg-hover); }
.file.active {
  background: var(--accent-soft);
  border-left-color: var(--accent);
}
.file.changed::after {
  content: "●";
  color: var(--yellow);
  margin-left: auto;
  padding-left: 8px;
  font-size: 10px;
}
.file.no-group { padding-left: 24px; }
.hidden { display: none !important; }

/* Viewer content */
.viewer h1, .viewer h2, .viewer h3, .viewer h4 { margin-top: 24px; }
.viewer h1 { border-bottom: 1px solid var(--border); padding-bottom: 8px; }
.viewer h2 { border-bottom: 1px solid var(--border); padding-bottom: 6px; }
.viewer p { max-width: 900px; }
.viewer ul, .viewer ol { max-width: 900px; }
.viewer pre {
  background: var(--bg-elev);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 12px;
  overflow-x: auto;
  font-family: var(--mono);
  font-size: 13px;
}
.viewer code {
  font-family: var(--mono);
  font-size: 0.9em;
}
.viewer :not(pre) > code {
  background: var(--bg-elev);
  border: 1px solid var(--border);
  border-radius: 3px;
  padding: 1px 4px;
}
.viewer blockquote {
  border-left: 3px solid var(--border);
  margin: 12px 0;
  padding: 4px 12px;
  color: var(--fg-mute);
}
.viewer table {
  border-collapse: collapse;
  margin: 12px 0;
  max-width: 900px;
}
.viewer th, .viewer td {
  border: 1px solid var(--border);
  padding: 6px 12px;
  text-align: left;
}
.viewer th { background: var(--bg-elev); }

.viewer-header {
  display: flex; align-items: center;
  gap: 12px;
  padding-bottom: 12px;
  border-bottom: 1px solid var(--border);
  margin-bottom: 16px;
}
.viewer-path {
  font-family: var(--mono);
  font-size: 12px;
  color: var(--fg-mute);
}
.viewer-meta {
  margin-left: auto;
  color: var(--fg-mute);
  font-size: 12px;
}

/* Search results panel */
.search-panel {
  position: absolute;
  top: 48px; left: 0; right: 0; bottom: 0;
  background: var(--bg);
  z-index: 5;
  padding: 24px 32px;
  overflow-y: auto;
}
.search-panel.hidden { display: none; }
.search-hit {
  padding: 12px 16px;
  border: 1px solid var(--border);
  border-radius: 6px;
  margin-bottom: 12px;
  cursor: pointer;
  background: var(--bg-elev);
}
.search-hit:hover { border-color: var(--accent); }
.search-hit-path {
  font-family: var(--mono);
  font-size: 12px;
  color: var(--accent);
  margin-bottom: 6px;
}
.search-snippet {
  font-family: var(--mono);
  font-size: 12px;
  color: var(--fg-mute);
  margin: 2px 0;
  white-space: pre-wrap;
}
.search-snippet mark {
  background: var(--yellow);
  color: var(--bg);
  padding: 0 2px;
  border-radius: 2px;
}
.search-empty { color: var(--fg-mute); }

/* Toast */
.toast {
  position: fixed;
  bottom: 16px; right: 16px;
  background: var(--bg-elev);
  border: 1px solid var(--border);
  color: var(--fg);
  padding: 8px 12px;
  border-radius: 6px;
  font-size: 12px;
  z-index: 20;
  box-shadow: 0 4px 12px rgba(0,0,0,0.5);
}
```

---

## `public/app.js`

```js
'use strict';

const state = {
  tree: null,
  current: null,        // current open path
  changedSinceView: new Set(),
  ws: null,
  wsRetries: 0
};

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

// --- bootstrap -------------------------------------------------------------

document.addEventListener('DOMContentLoaded', () => {
  loadTree();
  bindSearch();
  bindShortcuts();
  connectWs();
});

// --- tree ------------------------------------------------------------------

async function loadTree() {
  try {
    const res = await fetch('/api/tree');
    state.tree = await res.json();
    renderSidebar();
  } catch (err) {
    $('#sidebar').innerHTML = '<div class="sidebar-loading">failed to load tree</div>';
    console.error(err);
  }
}

function renderSidebar() {
  const sidebar = $('#sidebar');
  sidebar.innerHTML = '';

  const collapsed = JSON.parse(localStorage.getItem('collapsed') || '{}');

  for (const cat of state.tree.categories) {
    const catEl = document.createElement('div');
    catEl.className = 'category' + (collapsed['cat:' + cat.name] ? ' collapsed' : '');
    catEl.textContent = cat.name;
    catEl.dataset.key = 'cat:' + cat.name;
    sidebar.appendChild(catEl);

    const catBody = document.createElement('div');
    catBody.dataset.parent = 'cat:' + cat.name;
    if (collapsed['cat:' + cat.name]) catBody.classList.add('hidden');
    sidebar.appendChild(catBody);

    catEl.addEventListener('click', () => toggle(catEl, catBody, 'cat:' + cat.name));

    for (const group of cat.groups) {
      if (group.name) {
        const groupKey = 'grp:' + cat.name + '/' + group.name;
        const grpEl = document.createElement('div');
        grpEl.className = 'group' + (collapsed[groupKey] ? ' collapsed' : '');
        grpEl.textContent = group.name;
        catBody.appendChild(grpEl);

        const grpBody = document.createElement('div');
        if (collapsed[groupKey]) grpBody.classList.add('hidden');
        catBody.appendChild(grpBody);

        grpEl.addEventListener('click', () => toggle(grpEl, grpBody, groupKey));

        for (const f of group.files) grpBody.appendChild(fileNode(f, false));
      } else {
        for (const f of group.files) catBody.appendChild(fileNode(f, true));
      }
    }
  }

  if (state.current) markActive(state.current);
}

function fileNode(file, noGroup) {
  const el = document.createElement('div');
  el.className = 'file' + (noGroup ? ' no-group' : '');
  el.dataset.path = file.path;
  el.textContent = file.name;
  if (state.changedSinceView.has(file.path)) el.classList.add('changed');
  el.addEventListener('click', () => openFile(file.path));
  return el;
}

function toggle(headerEl, bodyEl, key) {
  const collapsed = JSON.parse(localStorage.getItem('collapsed') || '{}');
  if (headerEl.classList.contains('collapsed')) {
    headerEl.classList.remove('collapsed');
    bodyEl.classList.remove('hidden');
    delete collapsed[key];
  } else {
    headerEl.classList.add('collapsed');
    bodyEl.classList.add('hidden');
    collapsed[key] = true;
  }
  localStorage.setItem('collapsed', JSON.stringify(collapsed));
}

function markActive(path) {
  $$('.file').forEach(el => el.classList.remove('active'));
  const el = document.querySelector(`.file[data-path="${cssEscape(path)}"]`);
  if (el) el.classList.add('active');
}

function cssEscape(s) {
  return s.replace(/["\\]/g, '\\$&');
}

// --- file view -------------------------------------------------------------

async function openFile(relPath) {
  state.current = relPath;
  state.changedSinceView.delete(relPath);
  markActive(relPath);
  const dot = document.querySelector(`.file[data-path="${cssEscape(relPath)}"]`);
  if (dot) dot.classList.remove('changed');

  hideSearch();

  const viewer = $('#viewer');
  viewer.innerHTML = `<div class="viewer-header"><span class="viewer-path">${escapeHtml(relPath)}</span><span class="viewer-meta">loading…</span></div>`;

  try {
    const res = await fetch('/api/file?path=' + encodeURIComponent(relPath));
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const data = await res.json();
    viewer.innerHTML =
      `<div class="viewer-header">
         <span class="viewer-path">${escapeHtml(data.path)}</span>
         <span class="viewer-meta">${data.ext.replace('.', '').toUpperCase()} · ${formatBytes(data.content.length)}</span>
       </div>` +
      data.rendered;
  } catch (err) {
    viewer.innerHTML = `<div class="empty"><h1>error</h1><p>${escapeHtml(String(err))}</p></div>`;
  }
}

function formatBytes(n) {
  if (n < 1024) return n + ' B';
  if (n < 1024 * 1024) return (n / 1024).toFixed(1) + ' KB';
  return (n / 1024 / 1024).toFixed(1) + ' MB';
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// --- search ----------------------------------------------------------------

function bindSearch() {
  const input = $('#search');
  let timer = null;
  input.addEventListener('input', () => {
    clearTimeout(timer);
    timer = setTimeout(() => doSearch(input.value), 250);
  });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      input.value = '';
      hideSearch();
    }
  });
}

async function doSearch(q) {
  if (!q.trim()) { hideSearch(); return; }
  const res = await fetch('/api/search?q=' + encodeURIComponent(q));
  const data = await res.json();
  showSearch(data);
}

function showSearch(data) {
  let panel = $('#search-panel');
  if (!panel) {
    panel = document.createElement('div');
    panel.id = 'search-panel';
    panel.className = 'search-panel';
    document.body.appendChild(panel);
  }
  panel.classList.remove('hidden');

  if (!data.hits.length) {
    panel.innerHTML = `<div class="search-empty">no matches for <code>${escapeHtml(data.q)}</code></div>`;
    return;
  }

  panel.innerHTML = data.hits.map(h => {
    const snippets = h.snippets.map(s => {
      const before = escapeHtml(s.text.slice(0, s.match[0]));
      const hit = escapeHtml(s.text.slice(s.match[0], s.match[1]));
      const after = escapeHtml(s.text.slice(s.match[1]));
      return `<div class="search-snippet">L${s.line}: ${before}<mark>${hit}</mark>${after}</div>`;
    }).join('');
    return `<div class="search-hit" data-path="${escapeHtml(h.path)}">
      <div class="search-hit-path">${escapeHtml(h.path)}</div>
      ${snippets}
    </div>`;
  }).join('');

  panel.querySelectorAll('.search-hit').forEach(el => {
    el.addEventListener('click', () => openFile(el.dataset.path));
  });
}

function hideSearch() {
  const panel = $('#search-panel');
  if (panel) panel.classList.add('hidden');
}

function bindShortcuts() {
  window.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
      e.preventDefault();
      $('#search').focus();
      $('#search').select();
    }
  });
}

// --- websocket -------------------------------------------------------------

function connectWs() {
  setWsStatus('connecting');
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  const ws = new WebSocket(`${proto}://${location.host}/ws`);
  state.ws = ws;

  ws.addEventListener('open', () => {
    setWsStatus('open');
    state.wsRetries = 0;
  });

  ws.addEventListener('message', (evt) => {
    let msg;
    try { msg = JSON.parse(evt.data); } catch { return; }
    if (msg.type === 'change') handleChange(msg.path);
  });

  ws.addEventListener('close', () => {
    setWsStatus(state.wsRetries >= 5 ? 'error' : 'connecting');
    if (state.wsRetries < 10) {
      state.wsRetries++;
      setTimeout(connectWs, Math.min(1000 * state.wsRetries, 5000));
    }
  });

  ws.addEventListener('error', () => {
    try { ws.close(); } catch {}
  });
}

function setWsStatus(s) {
  const el = $('#ws-status');
  el.classList.remove('ws-connecting', 'ws-open', 'ws-error');
  el.classList.add('ws-' + s);
  el.title = 'live reload: ' + s;
}

let treeReloadTimer = null;
function handleChange(relPath) {
  // Re-fetch tree (debounced) — new file may have appeared/disappeared
  clearTimeout(treeReloadTimer);
  treeReloadTimer = setTimeout(loadTree, 300);

  if (relPath === state.current) {
    // Re-fetch current file
    openFile(relPath);
    showToast(`reloaded ${relPath}`);
  } else {
    state.changedSinceView.add(relPath);
    const el = document.querySelector(`.file[data-path="${cssEscape(relPath)}"]`);
    if (el) el.classList.add('changed');
    showToast(`changed: ${relPath}`);
  }
}

let toastTimer = null;
function showToast(msg) {
  const t = $('#toast');
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, 2000);
}
```

---

## `README.md` (inside `.claude/viewer/`)

```markdown
# .claude viewer

Local, read-only web browser for `.claude/` and the project's `.md`
files. Generated by the `claude-viewer` skill.

## Run

```bash
docker compose up
```

Then open <http://localhost:{{PORT}}>.

## Stop

```bash
docker compose down
```

## Change the port

Edit `docker-compose.yml` (line under `ports:`) or run with an env override:

```bash
PORT=8081 docker compose up
```

## What's exposed

- All `.md` and `.json` files inside `.claude/`
- All `.md` files anywhere in the project root (excluding `node_modules/`,
  `.git/`, `dist/`, `build/`, `.next/`, `.nuxt/`, `.venv/`, `venv/`,
  `target/`, `.cache/`, `coverage/`)

The mount is **read-only** — the viewer cannot write to your project.

## Rebuild

If you bump a dependency or edit code:

```bash
docker compose up --build
```
```
