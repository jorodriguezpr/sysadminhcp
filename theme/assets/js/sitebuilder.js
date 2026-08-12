/**
 * SysAdminHCP Page Builder (WYSIWYG, GrapesJS) — shared client-side module.
 *
 * Loaded by both theme/index.html (admin) and theme/client.html (client portal), which used to
 * each carry a full, byte-for-byte duplicate copy of every sb* function (see
 * docs/PAGEBUILDER-V2-IMPROVEMENT-PLAN.md §15). This file is the single source of truth now;
 * each host page only sets two globals before loading it:
 *   window.SB_API_BASE     — '/site-builder' (admin) or '/client/site-builder' (client portal)
 *   window.SB_DOMAINS_PATH — '/domains' (admin) or '/client/domains' (client portal)
 * ...and provides the globals this file expects to already exist: api(), showAlert(), showModal(),
 * closeModal(), escHtml(), and the `token` variable — every one of those already has an identical
 * signature in both host pages, so nothing else needs to be injected.
 *
 * Plain global `function sbXxx(){}` declarations throughout (not an object/module) — matches the
 * rest of this codebase's convention, since onclick="..." HTML attributes need bare global names.
 */

// ── Config + state ──
const SB_API = window.SB_API_BASE || '/site-builder';
const SB_DOMAINS_PATH = window.SB_DOMAINS_PATH || '/domains';

let sbEditor = null, sbDomain = null, sbFile = null;
let sbOriginalHead = null, sbCurrentVersion = 0, sbLockToken = null;
let sbAutoSaveTimer = null, sbAutoSaveEnabled = true, sbSaving = false;
let sbPagesCache = [];

sbInjectStyles();

function sbInjectStyles() {
  if (document.getElementById('sb-styles')) return;
  const style = document.createElement('style');
  style.id = 'sb-styles';
  style.textContent = `
#gjs{height:calc(100vh - 340px);min-height:480px;border:1px solid #ddd;border-radius:6px}
.sb-page-tab{border:1px solid #ddd;background:#f7f7f9;border-radius:6px;padding:5px 12px;font-size:13px;cursor:pointer;color:#333}
.sb-page-tab:hover{background:#eee}
.sb-page-tab.active{background:#2563eb;border-color:#2563eb;color:#fff}
.sb-loading{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;background:rgba(255,255,255,0.85);border-radius:6px;color:#555;font-size:14px;z-index:5}
.sb-spinner{width:30px;height:30px;border:3px solid #ddd;border-top-color:#2563eb;border-radius:50%;animation:sb-spin 0.8s linear infinite}
@keyframes sb-spin{to{transform:rotate(360deg)}}
.sb-status-bar{display:flex;align-items:center;gap:10px;margin-top:8px;padding:6px 10px;background:#f7f7f9;border-radius:6px;font-size:12px;color:#666}
.sb-more-menu{position:absolute;right:0;top:100%;margin-top:4px;background:#fff;border:1px solid #ddd;border-radius:6px;box-shadow:0 4px 12px rgba(0,0,0,0.15);z-index:20;min-width:200px;overflow:hidden}
.sb-more-menu a{display:block;padding:9px 14px;color:#333;text-decoration:none;font-size:13px}
.sb-more-menu a:hover{background:#f2f2f2}
.sb-tpl-cats{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:10px}
.sb-tpl-cat-btn{border:1px solid #ddd;background:#fff;border-radius:14px;padding:4px 12px;font-size:12px;cursor:pointer}
.sb-tpl-cat-btn.active{background:#2563eb;border-color:#2563eb;color:#fff}
.sb-tpl-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(110px,1fr));gap:8px;max-height:220px;overflow-y:auto}
.sb-tpl-card{border:2px solid #ddd;border-radius:8px;padding:14px 8px;text-align:center;font-size:12px;cursor:pointer;background:#fafafa}
.sb-tpl-card:hover{border-color:#94a3d1}
.sb-tpl-card.active{border-color:#2563eb;background:#eef2ff;font-weight:bold}
/* Dark theme — mirrors body.theme-dark, the panel's own existing dark-mode class */
body.theme-dark .sb-page-tab{background:#16213e;border-color:#0f3460;color:#e0e0e0}
body.theme-dark .sb-page-tab:hover{background:#0f3460}
body.theme-dark .sb-status-bar{background:#16213e;color:#aaa}
body.theme-dark .sb-more-menu{background:#16213e;border-color:#0f3460}
body.theme-dark .sb-more-menu a{color:#e0e0e0}
body.theme-dark .sb-more-menu a:hover{background:#0f3460}
body.theme-dark .sb-loading{background:rgba(13,17,23,0.85);color:#ccc}
body.theme-dark .sb-tpl-card{background:#16213e;border-color:#0f3460;color:#e0e0e0}
body.theme-dark #gjs{border-color:#0f3460}
body.theme-dark .gjs-pn-panels,body.theme-dark .gjs-pn-panel{background:#16213e!important;border-color:#0f3460!important}
body.theme-dark .gjs-block{background:#1a1a2e!important;color:#e0e0e0!important;border-color:#0f3460!important}
body.theme-dark .gjs-block:hover{background:#0f3460!important}
body.theme-dark .gjs-sm-sector .gjs-sm-title,body.theme-dark .gjs-layer{background:#16213e!important;color:#e0e0e0!important}
body.theme-dark .gjs-field{background:#1a1a2e!important;color:#e0e0e0!important;border-color:#0f3460!important}
body.theme-dark .gjs-label{color:#aaa!important}
`;
  document.head.appendChild(style);
}

// ── Rendering ──

async function renderSiteBuilder(el) {
  const data = await api(SB_DOMAINS_PATH);
  const domains = data.domains || [];
  el.innerHTML = `
  <div class="card">
    <div class="card-title" style="display:flex;justify-content:space-between;align-items:center">🎨 Page Builder <button class="btn btn-sm btn-help" onclick="showModuleHelp('sitebuilder')">❓ Help</button></div>
    <p style="color:#666;margin:0 0 14px">Visually edit a domain's HTML pages — drag blocks, style them, and save. Best for new pages or pages already created here; opening an existing hand-written page shows a warning first since saving can restructure its markup.</p>
    <div class="form-row"><div class="form-group" style="flex:2"><label>Domain</label>
      <select id="sb-domain" onchange="sbLoadPages()"><option value="">Select domain...</option>${domains.map(d => `<option value="${escHtml(d.nname)}">${escHtml(d.nname)}</option>`).join('')}</select>
    </div></div>
    <div id="sb-pages-wrap" style="display:none;margin-top:10px">
      <div id="sb-page-tabs" style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:10px"></div>
      <button class="btn btn-sm btn-primary" id="sb-new-btn" onclick="sbShowTemplates()">+ New Page</button>
    </div>
  </div>
  <div id="sb-editor-card" class="card sb-card" style="display:none">
    <div id="sb-toolbar" style="display:flex;gap:6px;align-items:center;margin-bottom:8px;flex-wrap:wrap">
      <button class="btn btn-sm btn-primary" onclick="sbSave()" title="Save (Ctrl+S)">💾 Save</button>
      <button class="btn btn-sm" onclick="sbPreview()" title="Preview in a new tab">👁 Preview</button>
      <button class="btn btn-sm" onclick="sbUndo()" title="Undo">↩</button>
      <button class="btn btn-sm" onclick="sbRedo()" title="Redo">↪</button>
      <button class="btn btn-sm" onclick="sbViewCode()" title="View HTML/CSS">{ }</button>
      <button class="btn btn-sm" onclick="sbShowSeoPanel()" title="Title, meta description, Open Graph">🔍 SEO</button>
      <button class="btn btn-sm" onclick="sbShowHistory()" title="Version history">🕐 History</button>
      <span class="sb-menu-wrap" style="position:relative">
        <button class="btn btn-sm" onclick="sbToggleMoreMenu()" title="More">⋯</button>
        <div id="sb-more-menu" class="sb-more-menu" style="display:none">
          <a href="#" onclick="sbToggleMoreMenu();sbShowRename();return false">✏️ Rename Page</a>
          <a href="#" onclick="sbToggleMoreMenu();sbShowDuplicate();return false">📄 Duplicate Page</a>
          <a href="#" onclick="sbToggleMoreMenu();sbApplyNavbar();return false">🔀 Apply Navbar to All Pages</a>
          <a href="#" onclick="sbToggleMoreMenu();sbDeletePage();return false" style="color:#e17055">🗑 Delete Page</a>
        </div>
      </span>
      <span style="margin-left:auto;display:flex;gap:4px">
        <button class="btn btn-sm" onclick="sbSetDevice('Desktop')" title="Desktop preview">🖥</button>
        <button class="btn btn-sm" onclick="sbSetDevice('Tablet')" title="Tablet preview">📱</button>
        <button class="btn btn-sm" onclick="sbSetDevice('Mobile')" title="Mobile preview">📱</button>
      </span>
    </div>
    <div id="sb-gjs-wrap" style="position:relative">
      <div id="gjs"></div>
      <div id="sb-loading" class="sb-loading" style="display:none"><div class="sb-spinner"></div><div>Loading editor…</div></div>
    </div>
    <div id="sb-status-bar" class="sb-status-bar">
      <span id="sb-status-text">Not saved yet</span>
      <span id="sb-lock-warning" style="display:none;color:#e17055;margin-left:12px"></span>
      <label style="margin-left:auto;display:flex;align-items:center;gap:5px;font-weight:normal;cursor:pointer">
        <input type="checkbox" id="sb-autosave-toggle" checked onchange="sbAutoSaveEnabled=this.checked"> Auto-save
      </label>
    </div>
  </div>`;
}

// ── Page list / tabs ──

async function sbLoadPages() {
  sbDomain = document.getElementById('sb-domain').value;
  document.getElementById('sb-editor-card').style.display = 'none';
  if (!sbDomain) { document.getElementById('sb-pages-wrap').style.display = 'none'; return; }
  try {
    const data = await api(`${SB_API}/${sbDomain}/pages`);
    sbPagesCache = data.pages || [];
    const tabs = document.getElementById('sb-page-tabs');
    tabs.innerHTML = sbPagesCache.length
      ? sbPagesCache.map(p => `<button class="sb-page-tab${p.name === sbFile ? ' active' : ''}" onclick="sbOpenEditor('${escHtml(p.name)}')" title="${formatBytesShort(p.size)} · modified ${new Date(p.modified).toLocaleString()}">📄 ${escHtml(p.name)}</button>`).join('')
      : '<span style="color:#999;font-size:13px">No HTML pages yet — click "+ New Page" to create one.</span>';
    document.getElementById('sb-pages-wrap').style.display = 'block';
  } catch (e) { showAlert(e.message, 'error'); }
}
function formatBytesShort(n) { if (!n) return '0 B'; const k = 1024, sizes = ['B', 'KB', 'MB']; const i = Math.min(2, Math.floor(Math.log(n) / Math.log(k))); return (n / Math.pow(k, i)).toFixed(i ? 1 : 0) + ' ' + sizes[i]; }

// ── Templates / new page ──

function sbShowTemplates() {
  api(`${SB_API}/templates`).then(data => {
    const templates = data.templates || [];
    const categories = ['All', ...Array.from(new Set(templates.map(t => t.category || 'Other')))];
    const renderGrid = (cat) => templates.filter(t => cat === 'All' || t.category === cat)
      .map(t => `<div class="sb-tpl-card" onclick="document.getElementById('sb-new-template').value='${escHtml(t.id)}';document.querySelectorAll('.sb-tpl-card').forEach(c=>c.classList.remove('active'));event.currentTarget.classList.add('active')" title="${escHtml(t.description)}">${escHtml(t.name)}</div>`).join('');
    showModal('New Page', `
      <div class="form-group"><label>Page name</label><input id="sb-new-name" placeholder="newpage" value="newpage"> <small style="color:#888">.html will be added automatically</small></div>
      <div class="form-group"><label>Template</label>
        <div class="sb-tpl-cats">${categories.map((c, i) => `<button type="button" class="sb-tpl-cat-btn${i === 0 ? ' active' : ''}" onclick="document.querySelectorAll('.sb-tpl-cat-btn').forEach(b=>b.classList.remove('active'));this.classList.add('active');document.getElementById('sb-tpl-grid').innerHTML=sbRenderTplGrid('${escHtml(c)}')">${escHtml(c)}</button>`).join('')}</div>
        <div id="sb-tpl-grid" class="sb-tpl-grid">${renderGrid('All')}</div>
        <input type="hidden" id="sb-new-template" value="${templates[0] ? escHtml(templates[0].id) : 'blank'}">
      </div>`,
      [{ label: 'Create', cls: 'btn-primary', onclick: 'sbCreateFromTemplate()' }]);
    window.sbRenderTplGrid = (cat) => renderGrid(cat);
  }).catch(e => showAlert(e.message, 'error'));
}
async function sbCreateFromTemplate() {
  const fileName = document.getElementById('sb-new-name').value;
  const templateId = document.getElementById('sb-new-template').value;
  try {
    const result = await api(`${SB_API}/${sbDomain}/from-template`, { method: 'POST', body: JSON.stringify({ templateId, fileName }) });
    closeModal();
    showAlert('Page created', 'success');
    await sbLoadPages();
    sbOpenEditor(result.fileName);
  } catch (e) { showAlert(e.message, 'error'); }
}

// ── Editor open/close ──

async function sbOpenEditor(fileName) {
  try {
    if (sbAutoSaveTimer) { clearTimeout(sbAutoSaveTimer); sbAutoSaveTimer = null; }
    const data = await api(`${SB_API}/${sbDomain}/pages/${encodeURIComponent(fileName)}`);

    if (!data.hasBeenEditedHere || (data.warnings && data.warnings.length)) {
      const warnHtml = (data.warnings && data.warnings.length) ? `<ul>${data.warnings.map(w => `<li>${escHtml(w)}</li>`).join('')}</ul>` : '';
      const msg = data.hasBeenEditedHere
        ? `This page has some styling the visual editor can't fully see:${warnHtml}`
        : `This page wasn't created with Page Builder — opening it here lets you make visual edits, but saving may restructure some of its original HTML/CSS.${warnHtml}<p>A backup of the current file is saved automatically before your first save, so the original is always recoverable.</p>`;
      if (!confirm(msg.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim() + '\n\nContinue?')) return;
    }
    if (data.lock && data.lock.locked) {
      if (!confirm(`${data.lock.byUser} started editing this page ${data.lock.ageSeconds}s ago and may still be working on it. Opening it here too risks one of you overwriting the other's changes.\n\nOpen anyway?`)) return;
    }

    sbFile = fileName;
    document.getElementById('sb-editor-card').style.display = 'block';
    document.getElementById('sb-loading').style.display = 'flex';
    document.getElementById('gjs').style.visibility = 'hidden';
    document.getElementById('gjs').scrollIntoView({ behavior: 'smooth' });
    sbRenderPageTabsActive();

    let lockInfo = { token: null };
    try { lockInfo = await api(`${SB_API}/${sbDomain}/pages/${encodeURIComponent(fileName)}/lock`, { method: 'POST' }); } catch { /* non-fatal — save still works without a lock */ }
    sbLockToken = lockInfo.token || null;

    await sbEnsureGrapesJS();
    if (sbEditor) { sbEditor.destroy(); sbEditor = null; }

    const existingImages = await sbLoadExistingImages();
    sbOriginalHead = data.headContent || null;
    sbCurrentVersion = data.version || 0;

    const config = {
      // Height is controlled by CSS (#gjs{height:...} in sbInjectStyles()), not an init option.
      container: '#gjs',
      fromElement: false,
      storageManager: false,
      assetManager: {
        upload: `/api${SB_API}/${sbDomain}/upload-image`,
        uploadName: 'file',
        headers: { 'Authorization': `Bearer ${token}` },
        assets: existingImages,
      },
      plugins: ['grapesjs-preset-webpage', 'sysadminhcp-blocks'],
      pluginsOpts: { 'grapesjs-preset-webpage': {} },
    };

    if (data.projectData) {
      try {
        const rewritten = sbRewriteImageUrls(data.projectData, true);
        config.projectData = JSON.parse(rewritten);
      } catch { config.components = sbRewriteImageUrls(data.html, true); }
    } else {
      config.components = sbRewriteImageUrls(data.html, true);
    }

    sbEditor = grapesjs.init(config);
    sbSetupAutoSave();
    sbUpdateStatus(`Opened v${sbCurrentVersion || 1}`);
  } catch (e) {
    showAlert(e.message, 'error');
  } finally {
    document.getElementById('sb-loading').style.display = 'none';
    const gjsEl = document.getElementById('gjs');
    if (gjsEl) gjsEl.style.visibility = 'visible';
  }
}
function sbRenderPageTabsActive() {
  document.querySelectorAll('.sb-page-tab').forEach(t => t.classList.toggle('active', t.textContent.trim() === `📄 ${sbFile}`));
}

async function sbEnsureGrapesJS() {
  if (window.grapesjs && window.__sbBlocksLoaded) return;
  if (!window.grapesjs) {
    try {
      await Promise.all([
        new Promise((r, rej) => { const l = document.createElement('link'); l.rel = 'stylesheet'; l.href = '/theme/assets/grapesjs/css/grapes.min.css'; l.onload = r; l.onerror = () => rej(new Error('Failed to load the Page Builder stylesheet.')); document.head.appendChild(l); }),
        new Promise((r, rej) => { const s = document.createElement('script'); s.src = '/theme/assets/grapesjs/grapes.min.js'; s.onload = r; s.onerror = () => rej(new Error('Failed to load the Page Builder editor.')); document.head.appendChild(s); }),
      ]);
      await new Promise((r, rej) => { const s = document.createElement('script'); s.src = '/theme/assets/grapesjs/preset-webpage.min.js'; s.onload = r; s.onerror = () => rej(new Error('Failed to load the Page Builder preset plugin.')); document.head.appendChild(s); });
    } catch (e) {
      throw new Error(`${e.message} Self-hosted assets are missing from theme/assets/grapesjs/ — re-run scripts/build-grapesjs.sh and redeploy.`);
    }
  }
  if (!window.__sbBlocksLoaded) {
    await new Promise((r) => { const s = document.createElement('script'); s.src = '/theme/assets/grapesjs/blocks-custom.js'; s.onload = r; s.onerror = r; document.head.appendChild(s); }); // non-critical — continue even if custom blocks fail
    window.__sbBlocksLoaded = true;
  }
}

// ── Image URL rewriting (editor needs absolute URLs to preview images from the domain's own
//    site; the saved file must keep them relative so the live site works standalone) ──

function sbRewriteImageUrls(text, toAbsolute) {
  if (!text || !sbDomain) return text;
  if (toAbsolute) {
    // Every attribute this codebase's templates/blocks generate uses double quotes, and JSON
    // strings always use double quotes too — so `"/images/` is an unambiguous match for both a
    // raw-HTML `src="/images/x.jpg"` and a project-data JSON `"src":"/images/x.jpg"`, without
    // needing to parse either format.
    return text.split('"/images/').join(`"https://${sbDomain}/images/`);
  }
  const esc = sbDomain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return text.replace(new RegExp(`https?:\\/\\/${esc}\\/images\\/`, 'g'), '/images/');
}

async function sbLoadExistingImages() {
  try {
    const data = await api(`${SB_API}/${sbDomain}/images`);
    return (data.images || []).map(img => ({ src: `https://${sbDomain}${img.url}`, name: img.name }));
  } catch { return []; }
}

// ── Save ──

async function sbSave(silent) {
  if (!sbEditor || !sbFile || sbSaving) return;
  sbSaving = true;
  try {
    let html = sbEditor.getHtml();
    const css = sbEditor.getCss();
    html = html.replace(/__SB_DOMAIN__/g, sbDomain);
    html = sbRewriteImageUrls(html, false);
    let projectData = JSON.stringify(sbEditor.getProjectData ? sbEditor.getProjectData() : {});
    projectData = sbRewriteImageUrls(projectData, false);

    const result = await api(`${SB_API}/${sbDomain}/pages/${encodeURIComponent(sbFile)}`, {
      method: 'PUT',
      body: JSON.stringify({ html, css, headContent: sbOriginalHead, projectData, lockToken: sbLockToken }),
    });
    sbCurrentVersion = result.version || sbCurrentVersion;
    sbUpdateStatus(`${silent ? 'Auto-saved' : 'Saved'} · v${sbCurrentVersion} · ${new Date().toLocaleTimeString()}`);
    if (!silent) showAlert('Page saved', 'success');
  } catch (e) {
    showAlert(e.message, 'error');
  } finally {
    sbSaving = false;
  }
}
function sbUpdateStatus(text) {
  const el = document.getElementById('sb-status-text');
  if (el) el.textContent = text;
}
function sbSetupAutoSave() {
  if (!sbEditor) return;
  sbEditor.on('update', () => {
    if (!sbAutoSaveEnabled || !sbFile) return;
    clearTimeout(sbAutoSaveTimer);
    sbAutoSaveTimer = setTimeout(() => sbSave(true), 5000);
  });
}

function sbPreview() {
  if (!sbEditor) return;
  const html = sbEditor.getHtml(), css = sbEditor.getCss();
  const full = `<!DOCTYPE html><html><head><style>${css}</style></head><body>${sbRewriteImageUrls(html, true)}</body></html>`;
  const blob = new Blob([full], { type: 'text/html' });
  window.open(URL.createObjectURL(blob), '_blank');
}
function sbUndo() { if (sbEditor) sbEditor.UndoManager.undo(); }
function sbRedo() { if (sbEditor) sbEditor.UndoManager.redo(); }
function sbSetDevice(d) { if (sbEditor) sbEditor.setDevice(d); }
function sbViewCode() {
  if (!sbEditor) return;
  const code = sbEditor.getHtml() + '\n<style>\n' + sbEditor.getCss() + '\n</style>';
  showModal('Page Code', `<textarea rows="20" style="width:100%;font-family:monospace" readonly>${escHtml(code)}</textarea>`, []);
}
function sbToggleMoreMenu() {
  const m = document.getElementById('sb-more-menu');
  m.style.display = m.style.display === 'none' ? 'block' : 'none';
}

// ── SEO panel ──

function sbShowSeoPanel() {
  if (!sbEditor) return;
  const headHtml = sbOriginalHead || '';
  const titleMatch = headHtml.match(/<title>([\s\S]*?)<\/title>/i);
  const descMatch = headHtml.match(/<meta\s+name=["']description["']\s+content=["']([\s\S]*?)["']/i);
  const keywordsMatch = headHtml.match(/<meta\s+name=["']keywords["']\s+content=["']([\s\S]*?)["']/i);
  const ogTitleMatch = headHtml.match(/<meta\s+property=["']og:title["']\s+content=["']([\s\S]*?)["']/i);
  const ogDescMatch = headHtml.match(/<meta\s+property=["']og:description["']\s+content=["']([\s\S]*?)["']/i);
  const canonicalMatch = headHtml.match(/<link\s+rel=["']canonical["']\s+href=["']([\s\S]*?)["']/i);

  showModal('SEO Settings', `
    <div style="display:grid;gap:15px;padding:4px">
      <div class="form-group"><label><b>Page Title</b> <small style="color:#888">shown in browser tab + search results, 50-60 chars recommended</small></label>
        <input type="text" id="seo-title" value="${escHtml(titleMatch ? titleMatch[1] : '')}" maxlength="70"></div>
      <div class="form-group"><label><b>Meta Description</b> <small style="color:#888">shown in search results, 150-160 chars recommended</small></label>
        <textarea id="seo-desc" rows="3" maxlength="200">${escHtml(descMatch ? descMatch[1] : '')}</textarea></div>
      <div class="form-group"><label><b>Meta Keywords</b> <small style="color:#888">optional, most search engines ignore this</small></label>
        <input type="text" id="seo-keywords" value="${escHtml(keywordsMatch ? keywordsMatch[1] : '')}"></div>
      <div class="form-group"><label><b>Open Graph Title</b> <small style="color:#888">shown when shared on social media</small></label>
        <input type="text" id="seo-og-title" value="${escHtml(ogTitleMatch ? ogTitleMatch[1] : '')}"></div>
      <div class="form-group"><label><b>Open Graph Description</b></label>
        <textarea id="seo-og-desc" rows="2">${escHtml(ogDescMatch ? ogDescMatch[1] : '')}</textarea></div>
      <div class="form-group"><label><b>Canonical URL</b> <small style="color:#888">optional</small></label>
        <input type="text" id="seo-canonical" placeholder="https://${sbDomain || 'example.com'}/page" value="${escHtml(canonicalMatch ? canonicalMatch[1] : '')}"></div>
    </div>`,
    [{ label: 'Save', cls: 'btn-primary', onclick: 'sbSaveSeo()' }, { label: 'Cancel', cls: 'btn', onclick: 'closeModal()' }]);
}
function sbSaveSeo() {
  const v = id => document.getElementById(id).value.trim();
  const title = v('seo-title'), desc = v('seo-desc'), keywords = v('seo-keywords');
  const ogTitle = v('seo-og-title'), ogDesc = v('seo-og-desc'), canonical = v('seo-canonical');

  let head = (sbOriginalHead || '')
    .replace(/<title>[\s\S]*?<\/title>/i, '')
    .replace(/<meta\s+name=["']description["'][^>]*>/i, '')
    .replace(/<meta\s+name=["']keywords["'][^>]*>/i, '')
    .replace(/<meta\s+property=["']og:title["'][^>]*>/i, '')
    .replace(/<meta\s+property=["']og:description["'][^>]*>/i, '')
    .replace(/<link\s+rel=["']canonical["'][^>]*>/i, '')
    .trim();
  if (!/charset=/i.test(head)) head = `<meta charset="UTF-8">\n${head}`;
  if (!/viewport/i.test(head)) head = `<meta name="viewport" content="width=device-width, initial-scale=1.0">\n${head}`;
  if (title) head += `\n<title>${escHtml(title)}</title>`;
  if (desc) head += `\n<meta name="description" content="${escHtml(desc)}">`;
  if (keywords) head += `\n<meta name="keywords" content="${escHtml(keywords)}">`;
  if (ogTitle) head += `\n<meta property="og:title" content="${escHtml(ogTitle)}">`;
  if (ogDesc) head += `\n<meta property="og:description" content="${escHtml(ogDesc)}">`;
  if (canonical) head += `\n<link rel="canonical" href="${escHtml(canonical)}">`;

  sbOriginalHead = head;
  closeModal();
  showAlert('SEO settings updated — click Save to apply them to the page.', 'info');
}

// ── Version history ──

async function sbShowHistory() {
  if (!sbFile) return;
  try {
    const data = await api(`${SB_API}/${sbDomain}/pages/${encodeURIComponent(sbFile)}/history`);
    const versions = data.versions || [];
    const rows = versions.length
      ? versions.map(v => `<tr><td>v${v.version}${v.version === data.currentVersion ? ' (current)' : ''}</td><td>${new Date(v.savedAt).toLocaleString()}</td><td>${escHtml(v.savedBy)}</td><td>${formatBytesShort(v.size)}</td><td>${escHtml(v.note || '')}</td><td>${v.version === data.currentVersion ? '' : `<button class="btn btn-xs" onclick="sbRestoreVersion(${v.version})">Restore</button>`}</td></tr>`).join('')
      : '<tr><td colspan="6" style="color:#999">No saved versions yet.</td></tr>';
    showModal(`Page History: ${sbFile}`, `<div style="max-height:60vh;overflow-y:auto"><table class="data-table"><thead><tr><th>Version</th><th>Date</th><th>User</th><th>Size</th><th>Note</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`, [{ label: 'Close', cls: 'btn', onclick: 'closeModal()' }]);
  } catch (e) { showAlert(e.message, 'error'); }
}
async function sbRestoreVersion(version) {
  if (!confirm(`Restore v${version}? This creates a new version from the old content — nothing already saved is deleted.`)) return;
  try {
    await api(`${SB_API}/${sbDomain}/pages/${encodeURIComponent(sbFile)}/restore/${version}`, { method: 'POST' });
    closeModal();
    showAlert(`Restored v${version}`, 'success');
    sbOpenEditor(sbFile);
  } catch (e) { showAlert(e.message, 'error'); }
}

// ── Page operations: delete / rename / duplicate ──

async function sbDeletePage() {
  if (!sbFile) return;
  if (!confirm(`Delete "${sbFile}"? This also removes its saved history. This cannot be undone.`)) return;
  try {
    await api(`${SB_API}/${sbDomain}/pages/${encodeURIComponent(sbFile)}`, { method: 'DELETE' });
    showAlert('Page deleted', 'success');
    sbFile = null;
    if (sbEditor) { sbEditor.destroy(); sbEditor = null; }
    document.getElementById('sb-editor-card').style.display = 'none';
    sbLoadPages();
  } catch (e) { showAlert(e.message, 'error'); }
}
function sbShowRename() {
  if (!sbFile) return;
  showModal('Rename Page', `<div class="form-group"><label>New file name</label><input id="sb-rename-input" value="${escHtml(sbFile)}"></div>`,
    [{ label: 'Rename', cls: 'btn-primary', onclick: 'sbDoRename()' }, { label: 'Cancel', cls: 'btn', onclick: 'closeModal()' }]);
}
async function sbDoRename() {
  const newName = document.getElementById('sb-rename-input').value;
  try {
    const result = await api(`${SB_API}/${sbDomain}/pages/${encodeURIComponent(sbFile)}/rename`, { method: 'POST', body: JSON.stringify({ newName }) });
    closeModal();
    showAlert('Page renamed', 'success');
    sbFile = result.fileName;
    await sbLoadPages();
    sbOpenEditor(sbFile);
  } catch (e) { showAlert(e.message, 'error'); }
}
function sbShowDuplicate() {
  if (!sbFile) return;
  const suggested = sbFile.replace(/\.html?$/i, '') + '-copy.html';
  showModal('Duplicate Page', `<div class="form-group"><label>New file name</label><input id="sb-dup-input" value="${escHtml(suggested)}"></div>`,
    [{ label: 'Duplicate', cls: 'btn-primary', onclick: 'sbDoDuplicate()' }, { label: 'Cancel', cls: 'btn', onclick: 'closeModal()' }]);
}
async function sbDoDuplicate() {
  const newName = document.getElementById('sb-dup-input').value;
  try {
    const result = await api(`${SB_API}/${sbDomain}/pages/${encodeURIComponent(sbFile)}/duplicate`, { method: 'POST', body: JSON.stringify({ newName }) });
    closeModal();
    showAlert('Page duplicated', 'success');
    await sbLoadPages();
    sbOpenEditor(result.fileName);
  } catch (e) { showAlert(e.message, 'error'); }
}

// ── Shared navbar ──

async function sbApplyNavbar() {
  if (!sbEditor || !sbFile) return;
  const html = sbEditor.getHtml();
  if (!/<nav[\s>]/i.test(html)) { showAlert('This page has no <nav> element to share — add the "Navigation Bar" block first.', 'error'); return; }
  if (!confirm('Apply this page\'s navigation bar to every other page on this domain? Existing <nav> elements on those pages will be replaced (pages with no <nav> at all are left untouched).')) return;
  const navMatch = html.match(/<nav[\s>][\s\S]*?<\/nav>/i);
  if (!navMatch) return;
  try {
    const result = await api(`${SB_API}/${sbDomain}/apply-navbar`, { method: 'POST', body: JSON.stringify({ navbarHtml: navMatch[0], sourceFileName: sbFile }) });
    showAlert(`Navbar applied to ${(result.updated || []).length} other page(s)`, 'success');
  } catch (e) { showAlert(e.message, 'error'); }
}

// ── File Manager integration ──

/** Called from the File Manager's "🎨 Open in Page Builder" button with a real absolute path
 *  (e.g. /home/<client>/<domain>/public_html/<file>) — switches to the Page Builder tab, waits
 *  for it to render (renderSiteBuilder() is async), then selects the domain and opens the file. */
function sbOpenFromFileManager(filePath) {
  const match = filePath.match(/\/home\/[^/]+\/([^/]+)\/public_html\/(.+)$/);
  if (!match) { showAlert('Page Builder can only open files directly inside a domain\'s public_html.', 'error'); return; }
  const domain = match[1], fileName = match[2];
  const navItem = document.querySelector('.nav-item[data-page="sitebuilder"]');
  if (!navItem) return;
  navItem.click();

  let attempts = 0;
  const tryOpen = () => {
    attempts++;
    const domainSelect = document.getElementById('sb-domain');
    if (!domainSelect) { if (attempts < 30) return setTimeout(tryOpen, 100); return; }
    if (!domainSelect.querySelector(`option[value="${CSS.escape(domain)}"]`)) { showAlert(`"${domain}" not found in the domain list.`, 'error'); return; }
    domainSelect.value = domain;
    sbLoadPages().then(() => sbOpenEditor(fileName));
  };
  setTimeout(tryOpen, 100);
}
