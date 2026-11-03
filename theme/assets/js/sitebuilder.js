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
// Site Builder S1 — draft/publish state of the open page (see SiteBuilderService.publishPage()).
let sbStatus = null, sbHasDraft = false, sbLiveExists = false;
// CSS GrapesJS can't represent (shorthands with var()) — kept verbatim in <style data-sb-preserve>.
let sbPreservedCss = '';
// The site's design tokens (sb-site.css as it will be after the next publish) — shown in the canvas.
let sbSiteCss = '';
let sbGlobals = { header: '', footer: '' };   // current global header/footer markup for the open page
let sbQuietUntil = 0;                         // ignore 'update' events from programmatic header/footer swaps

sbInjectStyles();

function sbInjectStyles() {
  if (document.getElementById('sb-styles')) return;
  const style = document.createElement('style');
  style.id = 'sb-styles';
  style.textContent = `
#gjs{height:calc(100vh - 340px);min-height:480px;border:1px solid rgba(0,0,0,0.08);border-radius:10px;overflow:hidden}
/* ── Page/Site Builder front page (matches the panel theme: glass cards, primary→accent2 gradient) ── */
.sbx{display:flex;flex-direction:column;gap:16px;margin-bottom:16px}
.sbx-hero{position:relative;overflow:hidden;display:flex;flex-wrap:wrap;gap:20px;align-items:flex-end;justify-content:space-between;padding:28px 28px 26px;border-radius:var(--radius-card,14px);color:#fff;background:linear-gradient(135deg,var(--primary,#4361ee) 0%,var(--accent2,#7b2ff7) 100%);box-shadow:var(--shadow-lg,0 8px 40px rgba(0,0,0,.12))}
.sbx-hero::after{content:'';position:absolute;right:-60px;top:-80px;width:280px;height:280px;border-radius:50%;background:radial-gradient(circle,rgba(76,201,240,.45),rgba(76,201,240,0) 70%);pointer-events:none}
.sbx-hero-text{position:relative;z-index:1;max-width:620px}
.sbx-eyebrow{display:inline-block;font-size:12px;font-weight:600;letter-spacing:.06em;text-transform:uppercase;background:rgba(255,255,255,.16);padding:4px 10px;border-radius:20px;margin-bottom:10px}
.sbx-hero h2{margin:0 0 8px;font-size:clamp(22px,3vw,30px);font-weight:700;line-height:1.2;color:#fff}
.sbx-hero p{margin:0;opacity:.9;font-size:14px;line-height:1.55}
.sbx-hero-side{position:relative;z-index:1;display:flex;flex-wrap:wrap;align-items:center;gap:8px;min-width:260px}
.sbx-hero-side label{width:100%;font-size:12px;font-weight:600;opacity:.85;text-transform:uppercase;letter-spacing:.05em}
.sbx-hero-side select{flex:1;min-width:200px;padding:10px 12px;border-radius:10px;border:1px solid rgba(255,255,255,.35);background:rgba(255,255,255,.95);color:#1a1a2e;font-size:14px;font-weight:500;box-shadow:0 4px 14px rgba(0,0,0,.12)}
.sbx-hero-side select:focus{outline:none;box-shadow:0 0 0 3px rgba(255,255,255,.35)}
.sbx-help{padding:9px 14px;border-radius:10px;border:1px solid rgba(255,255,255,.4);background:rgba(255,255,255,.12);color:#fff;font-size:13px;font-weight:500;cursor:pointer;transition:background .2s}
.sbx-help:hover{background:rgba(255,255,255,.24)}
.sbx-intro{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px}
.sbx-feature{display:flex;flex-direction:column;gap:4px;padding:18px;border-radius:var(--radius-card,14px);background:var(--card-bg,rgba(255,255,255,.85));border:1px solid var(--card-border,rgba(255,255,255,.2));box-shadow:var(--shadow,0 4px 24px rgba(0,0,0,.08));backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px)}
.sbx-feature span{font-size:24px}
.sbx-feature b{font-size:14px;color:var(--text-primary,#1a1a2e)}
.sbx-feature small{font-size:12.5px;color:var(--text-secondary,#6c757d);line-height:1.5}
.sbx-overview{display:flex;flex-wrap:wrap;gap:14px;align-items:stretch;margin-top:0 !important}
.sbx-stats{flex:3;min-width:280px;display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:12px}
.sbx-stat{padding:16px 12px !important}
.sbx-overview-actions{flex:1;min-width:220px;display:flex;flex-direction:column;justify-content:center;gap:10px;padding:16px;border-radius:var(--radius-card,14px);background:var(--card-bg,rgba(255,255,255,.85));border:1px solid var(--card-border,rgba(255,255,255,.2));box-shadow:var(--shadow,0 4px 24px rgba(0,0,0,.08))}
.sbx-site-link{font-size:13px;font-weight:600;color:var(--primary,#4361ee);text-decoration:none;word-break:break-all}
.sbx-site-link:hover{text-decoration:underline}
.sbx-publish{padding:10px 16px;font-size:14px}
#sb-pages-wrap > * + *{margin-top:12px}
.sbx-section-head{display:flex;align-items:baseline;gap:10px;margin:22px 2px 0 !important}
.sbx-section-head h3{margin:0;font-size:15px;font-weight:700;color:var(--text-primary,#1a1a2e)}
.sbx-section-note{font-size:12px;color:var(--text-secondary,#6c757d)}
.sbx-pages{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,160px),1fr));gap:12px}
.sbx-page{all:unset;box-sizing:border-box;display:flex;flex-direction:column;gap:6px;padding:14px;border-radius:12px;cursor:pointer;background:var(--card-bg,rgba(255,255,255,.85));border:1px solid var(--card-border,rgba(255,255,255,.2));box-shadow:var(--shadow,0 4px 24px rgba(0,0,0,.08));transition:transform .15s,box-shadow .15s,border-color .15s;min-height:98px}
.sbx-page:hover,.sbx-page:focus-visible{transform:translateY(-2px);box-shadow:var(--shadow-lg,0 8px 40px rgba(0,0,0,.12));border-color:rgba(67,97,238,.35)}
.sbx-page.active{border-color:var(--primary,#4361ee);box-shadow:0 0 0 2px rgba(67,97,238,.25),var(--shadow,0 4px 24px rgba(0,0,0,.08))}
.sbx-page-top{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:6px}
.sbx-page-ico{font-size:20px}
.sbx-page-top .sb-pill{font-size:10.5px;padding:2px 8px}
.sbx-page-name{font-size:14px;font-weight:600;color:var(--text-primary,#1a1a2e);word-break:break-all}
.sbx-page-meta{font-size:12px;color:var(--text-secondary,#6c757d)}
.sbx-page-new{align-items:center;justify-content:center;text-align:center;border:2px dashed rgba(67,97,238,.35);background:rgba(67,97,238,.04);box-shadow:none}
.sbx-page-new:hover{background:rgba(67,97,238,.08)}
.sbx-plus{width:34px;height:34px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:20px;color:#fff;background:linear-gradient(135deg,var(--primary,#4361ee),var(--accent2,#7b2ff7))}
.sbx-empty{grid-column:1/-1;font-size:13px;color:var(--text-secondary,#6c757d);padding:4px 2px}
.sbx-tools{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px}
.sbx-tool{all:unset;box-sizing:border-box;display:flex;align-items:center;gap:12px;padding:14px;border-radius:12px;cursor:pointer;background:var(--card-bg,rgba(255,255,255,.85));border:1px solid var(--card-border,rgba(255,255,255,.2));box-shadow:var(--shadow,0 4px 24px rgba(0,0,0,.08));transition:transform .15s,box-shadow .15s}
.sbx-tool:hover,.sbx-tool:focus-visible{transform:translateY(-2px);box-shadow:var(--shadow-lg,0 8px 40px rgba(0,0,0,.12))}
.sbx-tool-ico{flex:0 0 40px;height:40px;border-radius:11px;display:flex;align-items:center;justify-content:center;font-size:18px;font-weight:700;color:#fff;background:linear-gradient(135deg,var(--primary,#4361ee),var(--accent2,#7b2ff7));box-shadow:0 4px 12px rgba(67,97,238,.3)}
.sbx-tool-txt{display:flex;flex-direction:column;gap:2px;min-width:0}
.sbx-tool-txt b{font-size:14px;color:var(--text-primary,#1a1a2e)}
.sbx-tool-txt small{font-size:12px;color:var(--text-secondary,#6c757d)}
.sbx-editor-head{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:10px;margin:-4px 0 10px;padding-bottom:10px;border-bottom:1px solid rgba(0,0,0,.06)}
.sbx-editor-title{display:flex;align-items:center;gap:10px;min-width:0}
.sbx-editor-title b{font-size:16px;color:var(--text-primary,#1a1a2e);word-break:break-all}
.sbx-editor-ico{font-size:20px}
.sbx-editor-main{display:flex;gap:8px}
.sbx-toolbar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:10px}
.sbx-group{display:inline-flex;flex-wrap:wrap;gap:4px;padding:3px;border-radius:10px;background:rgba(67,97,238,.06)}
.sbx-group .btn{background:transparent;box-shadow:none}
.sbx-group .btn:hover{background:rgba(67,97,238,.12)}
.sbx-devices{margin-left:auto}
@media (max-width:640px){.sbx-hero{padding:20px}.sbx-hero-side{min-width:0;width:100%}.sbx-devices{margin-left:0}}
.sb-page-tab:not(.sbx-page){border:1px solid #ddd;background:#f7f7f9;border-radius:6px;padding:5px 12px;font-size:13px;cursor:pointer;color:#333}
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
.sb-pill{display:inline-block;padding:3px 10px;border-radius:12px;font-size:12px;font-weight:600;white-space:nowrap}
.sb-pill-draft{background:#fef3c7;color:#92400e}
.sb-pill-live{background:#dcfce7;color:#166534}
.sb-pill-pending{background:#dbeafe;color:#1e40af}
.sb-pill-off{background:#e5e7eb;color:#374151}
.sb-dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-left:6px;vertical-align:middle}
.sb-dot-draft{background:#f59e0b}.sb-dot-live{background:#22c55e}.sb-dot-pending{background:#3b82f6}.sb-dot-off{background:#9ca3af}
.sb-pub-table{width:100%;border-collapse:collapse;font-size:13px}
.sb-pub-table td,.sb-pub-table th{padding:6px 8px;border-bottom:1px solid #eee;text-align:left;vertical-align:top}
.sb-pub-warn{color:#b45309;font-size:12px;margin-top:3px}
.sb-sec-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(266px,1fr));gap:14px;max-height:62vh;overflow-y:auto;padding:2px}
.sb-sec-card{border:1px solid #e5e7eb;border-radius:8px;cursor:pointer;background:#fff;overflow:hidden;transition:box-shadow .15s,border-color .15s}
.sb-sec-card:hover,.sb-sec-card:focus{border-color:#3b82f6;box-shadow:0 4px 14px rgba(59,130,246,.18);outline:none}
.sb-sec-thumb{width:100%;height:176px;overflow:hidden;position:relative;background:#f8fafc;border-bottom:1px solid #eee}
.sb-sec-thumb iframe{width:1200px;height:800px;border:0;transform:scale(.22);transform-origin:0 0;pointer-events:none;position:absolute;left:0;top:0}
.sb-sec-label{font-weight:600;font-size:13px;padding:8px 10px 2px}
.sb-sec-desc{font-size:12px;color:#888;padding:0 10px 10px}
.sbc-pane .CodeMirror{height:58vh;font-size:13px}
.sb-ai-box{border-top:1px solid #eee;padding-top:10px;margin-top:10px}
.sb-ai-presets{display:flex;flex-wrap:wrap;gap:6px;margin:6px 0}
.sb-ai-out{border:1px solid #c7d2fe;background:#eef2ff;border-radius:8px;padding:10px;margin:8px 0;font-size:13px;line-height:1.5}
.sb-ai-quote{border-left:3px solid #ddd;padding:4px 8px;color:#555;font-size:12px;max-height:5.5em;overflow:hidden}
.sb-ai-brief{margin-bottom:10px}
.sb-ai-brief textarea{width:100%;box-sizing:border-box;font-size:13px}
.sb-sec-card.sb-busy{opacity:.5;pointer-events:none}
.sb-checks{list-style:none;padding:0;margin:0;font-size:13px}
.sb-checks li{padding:6px 0;border-bottom:1px solid #eee;line-height:1.45}
.sb-checks-sum{font-size:12px;margin-top:4px}
.sb-checks-sum summary{cursor:pointer;color:#b45309}
.sb-code-area{width:100%;min-height:90px;font-family:ui-monospace,Consolas,monospace;font-size:12px}
/* Dark theme — mirrors body.theme-dark, the panel's own existing dark-mode class */
body.theme-dark .sb-page-tab:not(.sbx-page){background:#16213e;border-color:#0f3460;color:#e0e0e0}
body.theme-dark .sbx-feature,body.theme-dark .sbx-page,body.theme-dark .sbx-tool,body.theme-dark .sbx-overview-actions{background:rgba(22,27,34,0.9);border-color:rgba(255,255,255,0.06);color:#e6edf3}
body.theme-dark .sbx-feature b,body.theme-dark .sbx-page-name,body.theme-dark .sbx-tool-txt b,body.theme-dark .sbx-section-head h3,body.theme-dark .sbx-editor-title b{color:#e6edf3}
body.theme-dark .sbx-feature small,body.theme-dark .sbx-page-meta,body.theme-dark .sbx-tool-txt small,body.theme-dark .sbx-section-note{color:#8b949e}
body.theme-dark .sbx-page-new{background:rgba(67,97,238,0.10);border-color:rgba(99,125,255,0.45)}
body.theme-dark .sbx-group{background:rgba(255,255,255,0.05)}
body.theme-dark .sbx-group .btn{color:#e6edf3}
body.theme-dark .sbx-editor-head{border-color:rgba(255,255,255,0.08)}
body.theme-dark .sbx-site-link{color:#8ea2ff}
body.theme-dark #gjs{border-color:rgba(255,255,255,0.08)}
body.theme-dark .sb-status-bar{background:#16213e;color:#aaa}
body.theme-dark .sb-more-menu{background:#16213e;border-color:#0f3460}
body.theme-dark .sb-more-menu a{color:#e0e0e0}
body.theme-dark .sb-more-menu a:hover{background:#0f3460}
body.theme-dark .sb-loading{background:rgba(13,17,23,0.85);color:#ccc}
body.theme-dark .sb-tpl-card{background:#16213e;border-color:#0f3460;color:#e0e0e0}
body.theme-dark .sb-sec-card{background:#16213e;border-color:#0f3460;color:#e0e0e0}
body.theme-dark .sb-ai-out{background:#1a1a2e;border-color:#3b4a8a;color:#e0e0e0}
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
  const isAdmin = SB_API === '/site-builder';
  const tool = (icon, title, desc, onclick) => `<button type="button" class="sbx-tool" onclick="${onclick}"><span class="sbx-tool-ico">${icon}</span><span class="sbx-tool-txt"><b>${title}</b><small>${desc}</small></span></button>`;
  el.innerHTML = `
  <div class="sbx">
    <div class="sbx-hero">
      <div class="sbx-hero-text">
        <div class="sbx-eyebrow">🎨 Page/Site Builder</div>
        <h2>Build and publish your website</h2>
        <p>Design pages visually, start from a complete site kit, write with AI, and publish when you are ready — visitors only see what you publish.</p>
      </div>
      <div class="sbx-hero-side">
        <label for="sb-domain">Website</label>
        <select id="sb-domain" onchange="sbLoadPages()"><option value="">Choose a domain…</option>${domains.map(d => `<option value="${escHtml(d.nname)}">${escHtml(d.nname)}</option>`).join('')}</select>
        <button class="sbx-help" onclick="showModuleHelp('sitebuilder')">❓ Help</button>
      </div>
    </div>

    <div id="sb-intro" class="sbx-intro">
      <div class="sbx-feature"><span>🖱️</span><b>Visual editor</b><small>Drag sections, click any text to edit it, switch to code whenever you like.</small></div>
      <div class="sbx-feature"><span>🏗</span><b>Site kits</b><small>A complete 5-page site for your kind of business in one step.</small></div>
      <div class="sbx-feature"><span>📨</span><b>Forms that work</b><small>Contact and booking forms, emailed to you and kept in the panel.</small></div>
      <div class="sbx-feature"><span>✨</span><b>AI assistant</b><small>Rewrite texts, write sections and SEO titles in seconds.</small></div>
    </div>

    <div id="sb-pages-wrap" style="display:none">
      <div class="sbx-overview">
        <div class="sbx-stats" id="sb-stats"></div>
        <div class="sbx-overview-actions">
          <a id="sb-site-link" class="sbx-site-link" href="#" target="_blank" rel="noopener"></a>
          <button class="btn btn-primary sbx-publish" onclick="sbShowPublishSite()" title="Review and publish every page with unpublished changes">🚀 Publish site…</button>
        </div>
      </div>

      <div class="sbx-section-head"><h3>Pages</h3><span class="sbx-section-note">Click a page to edit it</span></div>
      <div id="sb-page-tabs" class="sbx-pages"></div>

      <div class="sbx-section-head"><h3>Site tools</h3></div>
      <div class="sbx-tools">
        ${tool('🏗', 'Site kits', 'A complete site for your business', 'sbShowKits()')}
        ${tool('🎨', 'Design', 'Colours, fonts and spacing', 'sbShowDesign()')}
        ${tool('🧭', 'Header &amp; menu', 'Site name, logo, menu, footer', 'sbShowGlobals()')}
        ${tool('📨', 'Forms', 'Messages from your visitors', 'sbShowForms()')}
        ${tool('⟨/⟩', 'Site code', 'Analytics and tracking codes', 'sbShowCustomCode(true)')}
        ${tool('⚙', 'Site settings', 'Sitemap, robots.txt, page listing', 'sbShowSiteSettings()')}
        ${isAdmin ? tool('🧩', 'Plugins', 'Built-ins and section packs', 'sbShowPlugins()') : ''}
      </div>
    </div>
  </div>
  <div id="sb-editor-card" class="card sb-card" style="display:none">
    <div class="sbx-editor-head">
      <div class="sbx-editor-title"><span class="sbx-editor-ico">📄</span><b id="sb-editor-file"></b><span id="sb-state-pill" class="sb-pill sb-pill-off"></span></div>
      <div class="sbx-editor-main">
        <button class="btn btn-sm" onclick="sbSave()" title="Save your changes as a draft — the live site doesn't change">💾 Save draft</button>
        <button class="btn btn-sm btn-primary" onclick="sbPublish()" title="Make this page's draft live">🚀 Publish</button>
      </div>
    </div>
    <div id="sb-toolbar" class="sbx-toolbar">
      <span class="sbx-group">
        <button class="btn btn-sm" onclick="sbShowSections()" title="Insert a ready-made section below the selected one">➕ Section</button>
        <button class="btn btn-sm" onclick="sbShowAi()" title="AI: rewrite the selected text, suggest SEO title &amp; description">✨ AI</button>
      </span>
      <span class="sbx-group">
        <button class="btn btn-sm" onclick="sbUndo()" title="Undo">↩</button>
        <button class="btn btn-sm" onclick="sbRedo()" title="Redo">↪</button>
        <button class="btn btn-sm" onclick="sbPreview()" title="Preview in a new tab">👁 Preview</button>
        <button class="btn btn-sm" onclick="sbViewCode()" title="Edit the page's HTML and CSS">{ } Code</button>
      </span>
      <span class="sbx-group">
        <button class="btn btn-sm" onclick="sbShowSeoPanel()" title="Title, meta description, Open Graph">🔍 SEO</button>
        <button class="btn btn-sm" onclick="sbShowDesign()" title="Site colours, fonts and spacing">🎨 Design</button>
        <button class="btn btn-sm" onclick="sbShowGlobals()" title="Site name, logo, menu and footer shared by every page">🧭 Header &amp; menu</button>
        <button class="btn btn-sm" onclick="sbShowHistory()" title="Version history">🕐 History</button>
      </span>
      <span class="sb-menu-wrap" style="position:relative">
        <button class="btn btn-sm" onclick="sbToggleMoreMenu()" title="More">⋯</button>
        <div id="sb-more-menu" class="sb-more-menu" style="display:none">
          <a href="#" onclick="sbToggleMoreMenu();sbShowRename();return false">✏️ Rename Page</a>
          <a href="#" onclick="sbToggleMoreMenu();sbShowDuplicate();return false">📄 Duplicate Page</a>
          <a href="#" onclick="sbToggleMoreMenu();sbShowChecks();return false">🩺 Check page</a>
          <a href="#" onclick="sbToggleMoreMenu();sbShowCustomCode();return false">⟨/⟩ Custom code (page &amp; site)</a>
          <a href="#" onclick="sbToggleMoreMenu();sbShowForms();return false">📨 Forms &amp; messages</a>
          <a href="#" onclick="sbToggleMoreMenu();sbApplyNavbar();return false">🔀 Apply Navbar to All Pages</a>
          <a href="#" onclick="sbToggleMoreMenu();sbDiscardDraft();return false">↩ Discard Draft</a>
          <a href="#" onclick="sbToggleMoreMenu();sbUnpublish();return false">⏸ Unpublish (take offline)</a>
          <a href="#" onclick="sbToggleMoreMenu();sbDeletePage();return false" style="color:#e17055">🗑 Delete Page</a>
        </div>
      </span>
      <span class="sbx-group sbx-devices">
        <button class="btn btn-sm" onclick="sbSetDevice('Desktop')" title="Desktop view">🖥</button>
        <button class="btn btn-sm" onclick="sbSetDevice('Tablet')" title="Tablet view">⬜</button>
        <button class="btn btn-sm" onclick="sbSetDevice('Mobile')" title="Phone view">📱</button>
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
  const intro = document.getElementById('sb-intro');
  if (!sbDomain) { document.getElementById('sb-pages-wrap').style.display = 'none'; if (intro) intro.style.display = ''; return; }
  try {
    const data = await api(`${SB_API}/${sbDomain}/pages`);
    sbPagesCache = data.pages || [];
    sbRenderTabs();
    if (intro) intro.style.display = 'none';
    document.getElementById('sb-pages-wrap').style.display = 'block';
  } catch (e) { showAlert(e.message, 'error'); }
}

/** "5 min ago" style times for the page cards. */
function sbAgo(iso) {
  const t = new Date(iso).getTime();
  if (!t) return '';
  const s = Math.max(0, (Date.now() - t) / 1000);
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  if (s < 86400 * 30) return `${Math.floor(s / 86400)} d ago`;
  return new Date(t).toLocaleDateString();
}

function sbRenderTabs() {
  const tabs = document.getElementById('sb-page-tabs');
  if (!tabs) return;
  const pages = sbPagesCache || [];
  // Overview: counts + the site's address.
  const count = f => pages.filter(f).length;
  const stats = [
    [pages.length, 'Pages'],
    [count(p => p.liveExists), 'Live'],
    [count(p => p.status === 'live-with-draft'), 'Unpublished changes'],
    [count(p => !p.liveExists), 'Drafts / offline'],
  ];
  const statsEl = document.getElementById('sb-stats');
  if (statsEl) statsEl.innerHTML = stats.map(([n, l]) => `<div class="stat-card sbx-stat"><div class="stat-value">${n}</div><div class="stat-label">${l}</div></div>`).join('');
  const link = document.getElementById('sb-site-link');
  if (link && sbDomain) { link.href = `https://${sbDomain}/`; link.textContent = `🌐 ${sbDomain} ↗`; }
  // Page cards (names go through data-name, never into the onclick string).
  const order = p => (/^index\.html?$/i.test(p.name) ? '' : p.name);
  const cards = [...pages].sort((a, b) => order(a).localeCompare(order(b))).map(p => {
    const st = SB_STATE[p.status] || SB_STATE.live;
    return `<button type="button" class="sb-page-tab sbx-page${p.name === sbFile ? ' active' : ''}" data-name="${escHtml(p.name)}" onclick="sbOpenEditor(this.dataset.name)" title="Edit ${escHtml(p.name)}">
      <span class="sbx-page-top"><span class="sbx-page-ico">${/^index\.html?$/i.test(p.name) ? '🏠' : '📄'}</span><span class="sb-pill sb-pill-${st.cls}" title="${escHtml(st.label)}">${escHtml(SB_STATE_SHORT[p.status] || st.label)}</span></span>
      <span class="sbx-page-name">${escHtml(p.name)}</span>
      <span class="sbx-page-meta">${escHtml(sbAgo(p.modified))} · ${formatBytesShort(p.size)}</span>
    </button>`;
  }).join('');
  tabs.innerHTML = `<button type="button" class="sbx-page sbx-page-new" id="sb-new-btn" onclick="sbShowTemplates()"><span class="sbx-plus">＋</span><span class="sbx-page-name">New page</span><span class="sbx-page-meta">From a template</span></button>${cards}`
    + (pages.length ? '' : '<div class="sbx-empty">No pages yet — create one, or start a complete site with <a href="#" onclick="sbShowKits();return false">🏗 Site kits</a>.</div>');
}
// Short labels for the page cards (the editor pill keeps the long ones).
const SB_STATE_SHORT = { 'draft': '📝 Draft', 'live': '🟢 Live', 'live-with-draft': '✏️ Changes pending', 'unpublished': '⏸ Offline' };
const SB_STATE = {
  'draft': { label: '📝 Draft — not published yet', cls: 'draft' },
  'live': { label: '🟢 Live', cls: 'live' },
  'live-with-draft': { label: '✏️ Live · unpublished changes', cls: 'pending' },
  'unpublished': { label: '⏸ Offline — kept as draft', cls: 'off' },
};
function sbRenderStatePill() {
  const el = document.getElementById('sb-state-pill');
  if (!el) return;
  const st = SB_STATE[sbStatus] || SB_STATE.live;
  el.className = `sb-pill sb-pill-${st.cls}`;
  el.textContent = st.label;
  const entry = sbPagesCache.find(p => p.name === sbFile);
  if (entry && entry.status !== sbStatus) { entry.status = sbStatus; sbRenderTabs(); }
}
/** POST that keeps the HTTP status (api() turns every error into a message) — publish needs 409. */
async function sbPost(pathSuffix, body) {
  const res = await fetch(`${API}${SB_API}/${sbDomain}${pathSuffix}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
    body: JSON.stringify(body || {}),
  });
  let data = {};
  try { data = await res.json(); } catch { /* empty */ }
  return { ok: res.ok, status: res.status, data };
}
function sbSiteFilesNote(siteFiles) {
  if (!siteFiles) return '';
  const parts = [];
  if (siteFiles.sitemap === 'written') parts.push('sitemap.xml updated');
  if (siteFiles.sitemap === 'custom') parts.push('your own sitemap.xml was left unchanged');
  if (siteFiles.robots === 'written') parts.push('robots.txt updated');
  if (siteFiles.robots === 'custom') parts.push('your own robots.txt was left unchanged');
  if (siteFiles.siteCss === 'written') parts.push('site design (sb-site.css) updated');
  if (siteFiles.siteCss === 'custom') parts.push('your own sb-site.css was left unchanged');
  return parts.length ? ` (${parts.join(', ')})` : '';
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
    showAlert('Page created as a draft — click Publish when it\'s ready to go live', 'success');
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
        : `This page wasn't created with the Page/Site Builder — opening it here lets you make visual edits, but saving may restructure some of its original HTML/CSS.${warnHtml}<p>Your edits are saved as a draft: the live page only changes when you click Publish, and the current live copy is backed up first.</p>`;
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
    sbCurrentVersion = data.version || 0;
    // Head CSS: GrapesJS only ever receives the <body>. Without passing the page's <head> <style>
    // CSS in, a page (every template, most hand-written pages) opened unstyled and its CSS was
    // dropped by the first save. Pages that already have GrapesJS project data carry their own
    // styles; for the rest, load the head CSS — splitting off what GrapesJS can't keep.
    const head = data.headContent || '';
    const preserveMatch = head.match(/<style[^>]*data-sb-preserve[^>]*>([\s\S]*?)<\/style>/i);
    let preserved = preserveMatch ? preserveMatch[1].trim() : '';
    let editorCss = '';
    if (!data.projectData && data.headCss) {
      const split = sbSplitPreservedCss(data.headCss);
      editorCss = split.editorCss;
      if (split.preservedCss) preserved = preserved ? `${preserved}\n${split.preservedCss}` : split.preservedCss;
    }
    sbPreservedCss = preserved;
    sbSiteCss = data.siteCss || '';
    sbGlobals = data.globals || { header: '', footer: '' };
    const headNoStyles = head.replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '').trim();
    sbOriginalHead = (headNoStyles || preserved)
      ? `${headNoStyles}${preserved ? `\n<style data-sb-preserve>\n${preserved}\n</style>` : ''}`.trim()
      : null;
    sbStatus = data.status || 'live';
    sbHasDraft = !!data.hasDraft;
    sbLiveExists = data.liveExists !== false;
    sbRenderStatePill();

    const config = {
      // Height is controlled by CSS (#gjs{height:...} in sbInjectStyles()), not an init option.
      container: '#gjs',
      fromElement: false,
      storageManager: false,
      // Keep CSS rules whose selectors aren't on the page right now (classes added by scripts such
      // as .open/.active, or a rule written in { } Code before the class is used) — by default
      // GrapesJS drops them from getCss(), so saving silently deleted them.
      keepUnusedStyles: true,
      assetManager: {
        upload: `/api${SB_API}/${sbDomain}/upload-image`,
        uploadName: 'file',
        headers: { 'Authorization': `Bearer ${token}` },
        assets: existingImages,
      },
      plugins: ['grapesjs-preset-webpage', 'sysadminhcp-blocks'],
      pluginsOpts: { 'grapesjs-preset-webpage': {} },
      // Preserved rules are shown in the canvas too (re-applied by GrapesJS on every frame load),
      // without ever entering the editor's own CSS — so the canvas matches the published page.
      // Site tokens first (like the <link> in published pages), then preserved page rules.
      canvas: { styles: [sbSiteCss, sbPreservedCss].filter(Boolean).map(css => `data:text/css;charset=utf-8,${encodeURIComponent(css)}`) },
    };
    if (editorCss) config.style = editorCss;

    if (data.projectData) {
      try {
        const rewritten = sbRewriteImageUrls(data.projectData, true);
        config.projectData = JSON.parse(rewritten);
      } catch { config.components = sbRewriteImageUrls(data.html, true); }
    } else {
      config.components = sbRewriteImageUrls(data.html, true);
    }

    sbEditor = grapesjs.init(config);
    sbSetupGlobals(sbEditor);
    sbSetupAutoSave();
    sbUpdateStatus(sbHasDraft ? 'Opened your draft' : (sbCurrentVersion ? `Opened live page (published v${sbCurrentVersion})` : 'Opened live page'));
  } catch (e) {
    showAlert(e.message, 'error');
  } finally {
    document.getElementById('sb-loading').style.display = 'none';
    const gjsEl = document.getElementById('gjs');
    if (gjsEl) gjsEl.style.visibility = 'visible';
  }
}
function sbRenderPageTabsActive() {
  document.querySelectorAll('.sb-page-tab').forEach(t => t.classList.toggle('active', t.dataset.name === sbFile));
  const title = document.getElementById('sb-editor-file');
  if (title) title.textContent = sbFile || '';
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
    // Plugins (S6): the built-in ones are the builder's own scripts, loaded in registry order —
    // plugin #1 is the original blocks-custom.js, unchanged. Installed packs are static JSON
    // (window.__sbPacks), never scripts. If the registry can't be fetched, load the same two scripts.
    let scripts = ['/theme/assets/grapesjs/sb-sections.js', '/theme/assets/grapesjs/blocks-custom.js'];
    try {
      const reg = await api(`${SB_API}/plugins`);
      const own = (reg.plugins || []).map(p => p.script).filter(s => /^\/theme\/assets\/grapesjs\/[a-z0-9-]+\.js$/.test(s));
      if (own.length) scripts = own;
      window.__sbPacks = reg.packs || [];
    } catch { window.__sbPacks = []; }
    for (const src of scripts) {
      if (src.endsWith('/sb-sections.js') && window.SB_SECTIONS) continue;
      await new Promise((r) => { const s = document.createElement('script'); s.src = src; s.onload = r; s.onerror = r; document.head.appendChild(s); }); // non-critical — continue even if one fails
    }
    window.__sbBlocksLoaded = true;
  }
}

/** Library sections + sections of installed packs (one list for the picker and AI fill). */
function sbAllSections() {
  const lib = window.SB_SECTIONS || { SECTIONS: [], GROUPS: [] };
  const packs = window.__sbPacks || [];
  const packSections = packs.flatMap(p => (p.sections || []).map(s => ({ ...s, id: `pack--${p.id}--${s.id}`, group: s.group || p.name, pack: p.name })));
  const groups = [...lib.GROUPS, ...new Set(packSections.map(s => s.group))];
  return { SECTIONS: [...lib.SECTIONS, ...packSections], GROUPS: groups };
}

function sbRegisterPacks(ed) {
  for (const p of window.__sbPacks || []) {
    for (const s of p.sections || []) {
      ed.BlockManager.add(`pack--${p.id}--${s.id}`, { label: `▦ ${s.label}`, category: `${p.name} (pack)`, content: s.html, attributes: { title: s.description || '' } });
    }
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
    sbHasDraft = true;
    sbStatus = sbLiveExists ? 'live-with-draft' : (sbStatus === 'unpublished' ? 'unpublished' : 'draft');
    sbRenderStatePill();
    sbUpdateStatus(`${silent ? 'Draft auto-saved' : 'Draft saved'} · ${new Date().toLocaleTimeString()} · not live until you Publish`);
    if (!silent) showAlert('Draft saved — the live site is unchanged until you click Publish', 'success');
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
    if (!sbAutoSaveEnabled || !sbFile || Date.now() < sbQuietUntil) return;
    clearTimeout(sbAutoSaveTimer);
    sbAutoSaveTimer = setTimeout(() => sbSave(true), 5000);
  });
}

function sbPreview() {
  if (!sbEditor) return;
  const html = sbEditor.getHtml(), css = sbEditor.getCss();
  const full = `<!DOCTYPE html><html><head>${sbSiteCss ? `<style>${sbSiteCss}</style>` : ''}${sbPreservedCss ? `<style>${sbPreservedCss}</style>` : ''}<style>${css}</style></head><body>${sbRewriteImageUrls(html, true)}</body></html>`;
  const blob = new Blob([full], { type: 'text/html' });
  window.open(URL.createObjectURL(blob), '_blank');
}
function sbUndo() { if (sbEditor) sbEditor.UndoManager.undo(); }
function sbRedo() { if (sbEditor) sbEditor.UndoManager.redo(); }
function sbSetDevice(d) { if (sbEditor) sbEditor.setDevice(d); }
// ── Code mode (S3): edit the page's HTML/CSS — the SAME document the visual editor shows. Apply
// parses it back into GrapesJS (setComponents/setStyle), so code and visual views always agree. ──

const SB_BLOCK_TAGS = new Set(['section', 'div', 'header', 'footer', 'nav', 'main', 'article', 'aside', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'ul', 'ol', 'li', 'figure', 'figcaption', 'blockquote', 'details', 'summary', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th', 'form', 'fieldset', 'hr']);

/** Readable HTML: block elements on their own indented lines. Never adds whitespace inside an element
 *  that only holds text/inline content, so formatting doesn't change what the page shows. */
function sbFormatHtml(html) {
  const parts = html.split(/(<\/?[a-zA-Z][a-zA-Z0-9]*\b[^>]*>)/);
  const stack = [];
  let out = '', raw = 0;
  for (const part of parts) {
    if (!part) continue;
    const m = part.match(/^<(\/?)([a-zA-Z][a-zA-Z0-9]*)/);
    const tag = m && m[2].toLowerCase();
    if (m && (tag === 'pre' || tag === 'textarea')) raw += m[1] ? -1 : 1;
    if (!m || raw > 0 || !SB_BLOCK_TAGS.has(tag)) { out += part; continue; }
    if (!m[1]) {
      if (stack.length) stack[stack.length - 1].hasBlock = true;
      out += `${out ? '\n' : ''}${'  '.repeat(stack.length)}${part}`;
      if (tag !== 'hr' && !/\/>$/.test(part)) stack.push({ tag, hasBlock: false });
    } else {
      const top = stack.pop();
      out += top && top.hasBlock ? `\n${'  '.repeat(stack.length)}${part}` : part;
    }
  }
  return out.trim();
}

/** Non-void structural tags that are opened and closed a different number of times. */
function sbUnbalancedTags(html) {
  const text = html.replace(/<!--[\s\S]*?-->/g, '');
  return ['div', 'section', 'main', 'header', 'footer', 'nav', 'article', 'ul', 'ol', 'table', 'form', 'a', 'p']
    .map(tag => [tag, (text.match(new RegExp(`<${tag}\\b`, 'gi')) || []).length, (text.match(new RegExp(`</${tag}\\s*>`, 'gi')) || []).length])
    .filter(([, o, c]) => o !== c).map(([t, o, c]) => `<${t}> ${o} opened / ${c} closed`);
}

function sbMakeCodeViewer(id, mode, value) {
  const cm = sbEditor.CodeManager;
  // autoFormat off: GrapesJS's formatter breaks lines inside inline content, which changes the page
  // on Apply; sbFormatHtml() formats safely instead.
  const model = cm.createViewer({ codeName: mode, theme: 'hopscotch', readOnly: false, autoFormat: false, lineNumbers: true, lineWrapping: true, autoCloseTags: true, autoCloseBrackets: true });
  const el = new cm.EditorView({ model, config: cm.getConfig() }).render().el;
  document.getElementById(id).appendChild(el);
  model.setContent(value);
  setTimeout(() => { try { model.editor.refresh(); } catch { /* not visible yet */ } }, 0);
  return model;
}

function sbViewCode() {
  if (!sbEditor) return;
  const html = sbFormatHtml(sbRewriteImageUrls(sbEditor.getHtml(), false));
  const editorCss = sbEditor.getCss().replace(/^\s*\*\s*\{\s*box-sizing:\s*border-box;?\s*\}\s*body\s*\{\s*margin:\s*0;?\s*\}\s*/, '');
  const css = sbPreservedCss ? `${editorCss}\n${sbPreservedCss}` : editorCss;
  showModal('Page code', `
    <p style="margin:0 0 8px;color:#666;font-size:13px">Edit the HTML or CSS, then <b>Apply</b> — the visual editor updates to match, and you can keep refining either way. The shared site header/footer (🧭) are managed in <b>Header &amp; menu</b>; scripts and tracking codes go in <b>⟨/⟩ Custom code</b>.</p>
    <div class="sb-tpl-cats"><button type="button" id="sbc-tab-html" class="sb-tpl-cat-btn active" onclick="sbCodeTab('html')">HTML</button><button type="button" id="sbc-tab-css" class="sb-tpl-cat-btn" onclick="sbCodeTab('css')">CSS</button></div>
    <div id="sbc-html" class="sbc-pane"></div><div id="sbc-css" class="sbc-pane" style="display:none"></div>
    <div id="sbc-msg" class="sb-pub-warn" style="margin-top:6px"></div>`,
    [{ label: 'Apply', cls: 'btn-primary', onclick: 'sbApplyCode()' }]);
  const modal = document.querySelector('#modalContainer .modal');
  if (modal) modal.style.width = 'min(1100px, 96vw)';
  window.__sbCode = { html: sbMakeCodeViewer('sbc-html', 'htmlmixed', html), css: sbMakeCodeViewer('sbc-css', 'css', css), confirmed: false };
}

function sbCodeTab(which) {
  for (const k of ['html', 'css']) {
    document.getElementById(`sbc-${k}`).style.display = k === which ? '' : 'none';
    document.getElementById(`sbc-tab-${k}`).classList.toggle('active', k === which);
  }
  try { window.__sbCode[which].editor.refresh(); } catch { /* fine */ }
}

/** Replaces the preserved (GrapesJS-unparseable) CSS: kept in the page head and shown in the canvas. */
function sbSetPreservedCss(css) {
  sbPreservedCss = css || '';
  const head = (sbOriginalHead || '').replace(/\s*<style[^>]*data-sb-preserve[^>]*>[\s\S]*?<\/style>/gi, '').trim();
  sbOriginalHead = (head || sbPreservedCss) ? `${head}${sbPreservedCss ? `\n<style data-sb-preserve>\n${sbPreservedCss}\n</style>` : ''}`.trim() : null;
  try {
    const doc = sbEditor.Canvas.getDocument();
    let el = doc.getElementById('sb-preserved-live');
    if (!el) { el = doc.createElement('style'); el.id = 'sb-preserved-live'; doc.head.appendChild(el); }
    el.textContent = sbPreservedCss;
  } catch { /* canvas not ready */ }
}

function sbApplyCode() {
  const c = window.__sbCode;
  if (!c || !sbEditor) return;
  const html = c.html.editor.getValue(), css = c.css.editor.getValue();
  const problems = [];
  if (/<script\b/i.test(html)) problems.push('Scripts can\'t run inside page content and will be removed — put them in ⟨/⟩ Custom code instead.');
  const unbalanced = sbUnbalancedTags(html);
  if (unbalanced.length) problems.push(`Unbalanced HTML: ${unbalanced.join(', ')} — the editor will guess where elements end.`);
  if (problems.length && !c.confirmed) {
    c.confirmed = true;
    document.getElementById('sbc-msg').innerHTML = `⚠ ${problems.map(escHtml).join('<br>⚠ ')}<br>Fix it, or click <b>Apply</b> again to apply anyway.`;
    return;
  }
  const split = sbSplitPreservedCss(css);
  sbEditor.setComponents(sbRewriteImageUrls(html, true));
  sbEditor.setStyle(split.editorCss);
  sbSetPreservedCss(split.preservedCss);
  sbSyncGlobals();   // the shared header/footer always show the current version, locked
  closeModal();
  sbSave(true);
  showAlert('Code applied — the visual editor shows your changes (saved as a draft)', 'success');
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
    [{ label: 'Save', cls: 'btn-primary', onclick: 'sbSaveSeo()' }]);
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
    showModal(`Page History: ${sbFile}`, `<div style="max-height:60vh;overflow-y:auto"><table class="data-table"><thead><tr><th>Version</th><th>Date</th><th>User</th><th>Size</th><th>Note</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`, []);
  } catch (e) { showAlert(e.message, 'error'); }
}
async function sbRestoreVersion(version) {
  if (!confirm(`Restore v${version} into your draft? The live page doesn't change until you Publish.`)) return;
  try {
    await api(`${SB_API}/${sbDomain}/pages/${encodeURIComponent(sbFile)}/restore/${version}`, { method: 'POST' });
    closeModal();
    showAlert(`v${version} restored into your draft — review it, then Publish to make it live`, 'success');
    sbOpenEditor(sbFile);
  } catch (e) { showAlert(e.message, 'error'); }
}

// ── Page operations: delete / rename / duplicate ──

async function sbDeletePage() {
  if (!sbFile) return;
  if (!confirm(`Delete "${sbFile}"? This removes the live page, its draft and its saved history. This cannot be undone.`)) return;
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
    [{ label: 'Rename', cls: 'btn-primary', onclick: 'sbDoRename()' }]);
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
    [{ label: 'Duplicate', cls: 'btn-primary', onclick: 'sbDoDuplicate()' }]);
}
async function sbDoDuplicate() {
  const newName = document.getElementById('sb-dup-input').value;
  try {
    const result = await api(`${SB_API}/${sbDomain}/pages/${encodeURIComponent(sbFile)}/duplicate`, { method: 'POST', body: JSON.stringify({ newName }) });
    closeModal();
    showAlert('Copy created as a draft', 'success');
    await sbLoadPages();
    sbOpenEditor(result.fileName);
  } catch (e) { showAlert(e.message, 'error'); }
}

// ── Shared navbar ──

async function sbApplyNavbar() {
  if (!sbEditor || !sbFile) return;
  const html = sbEditor.getHtml();
  if (/data-sb-global=/.test(html)) { showAlert('This page uses the shared site header — change the menu with 🧭 Header & menu instead; it applies to every page that uses it.', 'info'); sbShowGlobals(); return; }
  if (!/<nav[\s>]/i.test(html)) { showAlert('This page has no <nav> element to share — add the "Navigation Bar" block first.', 'error'); return; }
  if (!confirm('Apply this page\'s navigation bar to every other page on this domain? It goes into each page\'s draft (existing <nav> elements are replaced) — nothing goes live until you use "Publish site".')) return;
  const navMatch = html.match(/<nav[\s>][\s\S]*?<\/nav>/i);
  if (!navMatch) return;
  try {
    const result = await api(`${SB_API}/${sbDomain}/apply-navbar`, { method: 'POST', body: JSON.stringify({ navbarHtml: navMatch[0], sourceFileName: sbFile }) });
    showAlert(`Navbar added to ${(result.updated || []).length} page draft(s) — use "🚀 Publish site…" to make them live`, 'success');
    sbLoadPages();
  } catch (e) { showAlert(e.message, 'error'); }
}

// ── File Manager integration ──

/** Called from the File Manager's "🎨 Open in Page Builder" button with a real absolute path
 *  (e.g. /home/<client>/<domain>/public_html/<file>) — switches to the Page Builder tab, waits
 *  for it to render (renderSiteBuilder() is async), then selects the domain and opens the file. */
function sbOpenFromFileManager(filePath) {
  const match = filePath.match(/\/home\/[^/]+\/([^/]+)\/public_html\/(.+)$/);
  if (!match) { showAlert('The Page/Site Builder can only open files directly inside a domain\'s public_html.', 'error'); return; }
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

// ── Site Builder S1: publish / discard / unpublish / site settings ──

async function sbPublish(skipChecks) {
  if (!sbEditor || !sbFile) return;
  try {
    if (skipChecks === true) closeModal();
    await sbSave(true); // publish exactly what's on screen
    if (!sbHasDraft) { showAlert('Nothing to publish — this page has no unpublished changes.', 'info'); return; }
    if (skipChecks !== true) {
      // Pre-publish checks: a warning card, never a blocker ("Publish anyway").
      let checks = [];
      try { checks = (await api(`${SB_API}/${sbDomain}/pages/${encodeURIComponent(sbFile)}/checks`)).checks || []; } catch { /* checks are advisory */ }
      if (checks.some(c => c.level === 'warn')) {
        showModal('Before you publish', `<p style="margin:0 0 8px;color:#666;font-size:13px">A few things worth a look on <b>${escHtml(sbFile)}</b>. You can fix them first or publish anyway.</p>${sbChecksList(checks)}`,
          [{ label: '🚀 Publish anyway', cls: 'btn-success', onclick: 'sbPublish(true)' }]);
        return;
      }
    }
    let r = await sbPost(`/pages/${encodeURIComponent(sbFile)}/publish`, {});
    if (r.status === 409) {
      if (!confirm(`${r.data.error}\n\nOverwrite the live page with your draft? (The current live copy is backed up first.)`)) return;
      r = await sbPost(`/pages/${encodeURIComponent(sbFile)}/publish`, { overwriteExternal: true });
    }
    if (!r.ok) throw new Error(r.data.error || 'Publish failed');
    sbHasDraft = false;
    sbLiveExists = true;
    sbStatus = 'live';
    sbCurrentVersion = r.data.version || sbCurrentVersion;
    sbRenderStatePill();
    sbUpdateStatus(`Published v${sbCurrentVersion} · ${new Date().toLocaleTimeString()}`);
    showAlert(`${sbFile} is live (v${sbCurrentVersion})${sbSiteFilesNote(r.data.siteFiles)}`, 'success');
    sbLoadPagesKeepEditor();
  } catch (e) { showAlert(e.message, 'error'); }
}

/** Refreshes the tab list without closing the open editor (sbLoadPages() hides it). */
async function sbLoadPagesKeepEditor() {
  try {
    const data = await api(`${SB_API}/${sbDomain}/pages`);
    sbPagesCache = data.pages || [];
    sbRenderTabs();
  } catch { /* non-fatal */ }
}

async function sbShowPublishSite() {
  if (!sbDomain) return;
  try {
    if (sbEditor && sbFile) await sbSave(true);
    const d = await api(`${SB_API}/${sbDomain}/publish/preview`);
    const pages = d.pages || [];
    const designLine = d.siteCss === 'write' ? '<br>🎨 site design changed — sb-site.css will be updated' : d.siteCss === 'custom' ? '<br>ℹ️ your own sb-site.css is kept' : '';
    const siteLine = (name, state) => state === 'write' ? `✅ ${name} will be regenerated`
      : state === 'custom' ? `ℹ️ your own ${name} is kept (not generated by the builder)` : `— ${name} generation is off`;
    const rows = pages.map(p => {
      const st = SB_STATE[p.status] || SB_STATE.draft;
      const when = p.draftUpdatedAt ? new Date(p.draftUpdatedAt).toLocaleString() : '';
      return `<tr>
        <td><input type="checkbox" class="sb-pub-page" value="${escHtml(p.fileName)}" checked></td>
        <td><b>${escHtml(p.fileName)}</b><div style="font-size:11px;color:#888">${escHtml(st.label)}</div>
          ${p.externalChange ? `<div class="sb-pub-warn">⚠ The live page was changed outside the builder (FTP / File Manager).<br><label><input type="checkbox" class="sb-pub-overwrite" value="${escHtml(p.fileName)}"> Overwrite it anyway (live copy is backed up)</label></div>` : ''}
          ${sbChecksSummary(p.checks)}</td>
        <td style="font-size:12px">${p.liveExists ? `${formatBytesShort(p.liveSize)} → ${formatBytesShort(p.draftSize)}` : `new · ${formatBytesShort(p.draftSize)}`}</td>
        <td style="font-size:12px">${escHtml(when)}${p.draftBy ? `<br>${escHtml(p.draftBy)}` : ''}</td>
      </tr>`;
    }).join('');
    const gp = d.globalPages || [];
    const globalsBlock = gp.length ? `<div class="sb-pub-globals" style="margin-top:12px;font-size:13px;line-height:1.6">
        <label><input type="checkbox" id="sb-pub-globals" checked> 🧭 <b>Shared header/menu or site code changed</b> — update it on ${gp.length} live page(s): ${gp.map(p => escHtml(p.fileName)).join(', ')}</label>
        ${gp.filter(p => p.externalChange).map(p => `<div class="sb-pub-warn">⚠ ${escHtml(p.fileName)} was changed outside the builder — only its header/footer would be replaced.<br><label><input type="checkbox" class="sb-pub-overwrite" value="${escHtml(p.fileName)}"> Update it anyway (live copy is backed up)</label></div>`).join('')}
      </div>` : '';
    const body = pages.length
      ? `<p style="margin:0 0 10px;color:#555">These pages have changes that aren't live yet on <b>${escHtml(d.siteUrl)}</b>. Nothing changes for visitors until you publish.</p>
         <div style="max-height:45vh;overflow-y:auto"><table class="sb-pub-table"><thead><tr><th></th><th>Page</th><th>Size</th><th>Last edit</th></tr></thead><tbody>${rows}</tbody></table></div>
         <div style="margin-top:12px;font-size:12px;color:#555;line-height:1.7">${siteLine('sitemap.xml', d.sitemap)}<br>${siteLine('robots.txt', d.robots)}${designLine}</div>${globalsBlock}`
      : (d.siteCss === 'write' || gp.length)
        ? `<p>No page drafts on <b>${escHtml(d.siteUrl)}</b>, but:</p>${d.siteCss === 'write' ? '<p>🎨 the <b>site design</b> changed — publishing updates <code>sb-site.css</code>, which restyles every page that uses the Site style blocks.</p>' : ''}${globalsBlock}`
        : `<p>✅ Everything on <b>${escHtml(d.siteUrl)}</b> is published — no pending drafts.</p>`;
    window.__sbDesignPending = d.siteCss === 'write';
    showModal('Publish Site', body, (pages.length || d.siteCss === 'write' || gp.length)
      ? [{ label: '🚀 Publish selected', cls: 'btn-success', onclick: 'sbDoPublishSite()' }]
      : []);
  } catch (e) { showAlert(e.message, 'error'); }
}

async function sbDoPublishSite() {
  const pages = [...document.querySelectorAll('.sb-pub-page:checked')].map(c => c.value);
  const overwriteExternal = [...document.querySelectorAll('.sb-pub-overwrite:checked')].map(c => c.value);
  const globalsBox = document.getElementById('sb-pub-globals');
  const refreshGlobals = !!(globalsBox && globalsBox.checked);
  if (!pages.length && !window.__sbDesignPending && !refreshGlobals) { showAlert('Select at least one page to publish.', 'info'); return; }
  try {
    const r = await sbPost('/publish', { pages, overwriteExternal, refreshGlobals });
    if (!r.ok) throw new Error(r.data.error || 'Publish failed');
    closeModal();
    const { published = [], refreshed = [], conflicts = [], errors = [], siteFiles } = r.data;
    let msg = published.length ? `Published ${published.length} page(s)${sbSiteFilesNote(siteFiles)}.` : `Published${sbSiteFilesNote(siteFiles) || (refreshed.length ? '' : ' — nothing changed')}.`;
    if (refreshed.length) msg += ` Header/menu updated on ${refreshed.length} live page(s).`;
    if (conflicts.length) msg += ` Skipped (changed outside the builder): ${conflicts.join(', ')}.`;
    if (errors.length) msg += ` Failed: ${errors.map(e => `${e.fileName} (${e.error})`).join('; ')}.`;
    showAlert(escHtml(msg), conflicts.length || errors.length ? 'warning' : 'success');
    if (sbFile && published.includes(sbFile)) {
      sbHasDraft = false; sbLiveExists = true; sbStatus = 'live';
      sbRenderStatePill();
      sbUpdateStatus(`Published · ${new Date().toLocaleTimeString()}`);
    }
    sbLoadPagesKeepEditor();
  } catch (e) { showAlert(e.message, 'error'); }
}

async function sbDiscardDraft() {
  if (!sbFile) return;
  if (!sbHasDraft) { showAlert('This page has no draft to discard.', 'info'); return; }
  const msg = sbLiveExists
    ? `Discard your unpublished changes to "${sbFile}" and go back to the live version?`
    : `"${sbFile}" was never published — discarding its draft deletes the page. Continue?`;
  if (!confirm(msg)) return;
  try {
    if (sbAutoSaveTimer) { clearTimeout(sbAutoSaveTimer); sbAutoSaveTimer = null; }
    const r = await sbPost(`/pages/${encodeURIComponent(sbFile)}/discard-draft`, {});
    if (!r.ok) throw new Error(r.data.error || 'Discard failed');
    if (r.data.pageRemoved) {
      showAlert('Draft discarded — the page was removed', 'success');
      sbFile = null;
      if (sbEditor) { sbEditor.destroy(); sbEditor = null; }
      document.getElementById('sb-editor-card').style.display = 'none';
      sbLoadPages();
    } else {
      showAlert('Draft discarded — showing the live page', 'success');
      sbOpenEditor(sbFile);
      sbLoadPagesKeepEditor();
    }
  } catch (e) { showAlert(e.message, 'error'); }
}

async function sbUnpublish() {
  if (!sbFile) return;
  if (!sbLiveExists) { showAlert('This page is not live.', 'info'); return; }
  if (!confirm(`Take "${sbFile}" offline? Visitors will no longer see it. Its content is kept as a draft (and in History), so you can publish it again any time.`)) return;
  try {
    const r = await sbPost(`/pages/${encodeURIComponent(sbFile)}/unpublish`, {});
    if (!r.ok) throw new Error(r.data.error || 'Unpublish failed');
    showAlert(`${sbFile} is offline — kept as a draft`, 'success');
    sbOpenEditor(sbFile);
    sbLoadPagesKeepEditor();
  } catch (e) { showAlert(e.message, 'error'); }
}

const SB_SITEMAP_DEFAULT_EXCLUDE = /^(404|maintenance|coming-soon|.*-copy)\.html?$/i;

async function sbShowSiteSettings() {
  if (!sbDomain) return;
  try {
    const d = await api(`${SB_API}/${sbDomain}/site`);
    const m = d.manifest || {};
    const settings = m.settings || { sitemap: true, robots: true };
    const live = (d.pages || []).filter(p => p.liveExists);
    const rows = live.map(p => {
      const cfg = (m.pages || {})[p.name] || {};
      const included = cfg.inSitemap ?? !SB_SITEMAP_DEFAULT_EXCLUDE.test(p.name);
      return `<label style="display:block;font-size:13px;margin:3px 0"><input type="checkbox" class="sb-sitemap-page" value="${escHtml(p.name)}" ${included ? 'checked' : ''}> ${escHtml(p.name)}</label>`;
    }).join('') || '<span style="color:#999;font-size:13px">No live pages yet.</span>';
    showModal('Site Settings', `
      <div class="form-group"><label style="font-weight:normal"><input type="checkbox" id="sb-set-sitemap" ${settings.sitemap ? 'checked' : ''}> Generate <b>sitemap.xml</b> when publishing</label></div>
      <div class="form-group"><label style="font-weight:normal"><input type="checkbox" id="sb-set-robots" ${settings.robots ? 'checked' : ''}> Generate <b>robots.txt</b> when publishing</label>
        <small style="color:#888;display:block">A sitemap.xml or robots.txt you wrote yourself is never overwritten.</small></div>
      <div class="form-group"><label><b>Pages listed in the sitemap</b></label>
        <div style="max-height:30vh;overflow-y:auto;border:1px solid #eee;border-radius:6px;padding:6px 10px">${rows}</div>
        <a href="#" onclick="sbPreviewSitemap();return false" style="font-size:12px">Preview sitemap.xml</a></div>`,
      [{ label: 'Save', cls: 'btn-primary', onclick: 'sbSaveSiteSettings()' }]);
    window.__sbSitemapPages = live.map(p => p.name);
  } catch (e) { showAlert(e.message, 'error'); }
}

async function sbSaveSiteSettings() {
  const checked = new Set([...document.querySelectorAll('.sb-sitemap-page:checked')].map(c => c.value));
  const pages = {};
  for (const name of window.__sbSitemapPages || []) pages[name] = { inSitemap: checked.has(name) };
  try {
    await api(`${SB_API}/${sbDomain}/site`, { method: 'PUT', body: JSON.stringify({
      settings: { sitemap: document.getElementById('sb-set-sitemap').checked, robots: document.getElementById('sb-set-robots').checked },
      pages,
    }) });
    closeModal();
    showAlert('Site settings saved — they apply on the next publish', 'success');
  } catch (e) { showAlert(e.message, 'error'); }
}

async function sbPreviewSitemap() {
  try {
    const res = await fetch(`${API}${SB_API}/${sbDomain}/sitemap`, { headers: { 'Authorization': `Bearer ${token}` } });
    const xml = await res.text();
    if (!res.ok) throw new Error('Could not build the sitemap preview');
    window.open(URL.createObjectURL(new Blob([xml], { type: 'text/plain' })), '_blank');
  } catch (e) { showAlert(e.message, 'error'); }
}

// ── CSS: keep what GrapesJS's parser would silently drop ──
// GrapesJS parses CSS through the browser's CSSOM, which can't split a SHORTHAND property whose
// value contains var() (background, padding, border, …) into longhands — so GrapesJS gets nothing
// and the declaration vanishes (verified in headless Chrome against the shipped grapes.min.js).
// sbSplitPreservedCss() expands the shorthands it fully understands into longhands GrapesJS keeps,
// and copies anything else containing a var() shorthand VERBATIM into `preservedCss`, which is saved
// in <style data-sb-preserve> (never stripped) and placed before the editor's CSS, so later edits
// of the same property in the editor still win.

const SB_VAR_SHORTHANDS = new Set(['background', 'padding', 'margin', 'inset', 'border', 'border-top', 'border-right', 'border-bottom',
  'border-left', 'border-radius', 'border-width', 'border-style', 'border-color', 'font', 'outline', 'gap', 'flex', 'grid', 'grid-area',
  'grid-template', 'transition', 'animation', 'list-style', 'columns', 'text-decoration', 'place-items', 'place-content', 'overflow']);
const SB_BORDER_STYLES = new Set(['none', 'hidden', 'dotted', 'dashed', 'solid', 'double', 'groove', 'ridge', 'inset', 'outset']);

function sbSplitTop(str, sep) {
  const out = []; let depth = 0, cur = '', quote = '';
  for (const ch of str) {
    if (quote) { cur += ch; if (ch === quote) quote = ''; continue; }
    if (ch === '"' || ch === "'") { quote = ch; cur += ch; continue; }
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (depth === 0 && (sep === ' ' ? /\s/.test(ch) : ch === sep)) { if (cur.trim()) out.push(cur.trim()); cur = ''; continue; }
    cur += ch;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}

/** Returns longhand declarations for a var() shorthand, or null when it can't be expanded safely. */
function sbExpandShorthand(prop, value) {
  let important = '';
  const m = value.match(/^(.*?)\s*!important\s*$/i);
  if (m) { value = m[1]; important = ' !important'; }
  const parts = sbSplitTop(value, ' ');
  const four = (names) => {
    if (parts.length < 1 || parts.length > 4) return null;
    const [t, r = t, b = t, l = r] = parts;
    return names.map((n, i) => `${n}:${[t, r, b, l][i]}${important}`);
  };
  if (prop === 'padding' || prop === 'margin') return four(['top', 'right', 'bottom', 'left'].map(s => `${prop}-${s}`));
  if (prop === 'inset') return four(['top', 'right', 'bottom', 'left']);
  if (prop === 'border-radius') {
    if (value.includes('/')) return null;
    return four(['border-top-left-radius', 'border-top-right-radius', 'border-bottom-right-radius', 'border-bottom-left-radius']);
  }
  if (prop === 'border-width' || prop === 'border-style' || prop === 'border-color') {
    const kind = prop.split('-')[1];
    return four(['top', 'right', 'bottom', 'left'].map(s => `border-${s}-${kind}`));
  }
  if (prop === 'border' || /^border-(top|right|bottom|left)$/.test(prop)) {
    if (parts.length > 3) return null;
    let width = null, style = null, color = null;
    for (const p of parts) {
      if (SB_BORDER_STYLES.has(p.toLowerCase())) { if (style) return null; style = p; }
      else if (/^(thin|medium|thick|0|[\d.]+[a-z%]*)$/i.test(p)) { if (width) return null; width = p; }
      else { if (color) return null; color = p; } // var(...) / color — a var() is treated as the colour
    }
    // border-width/-style/-color are shorthands themselves (4 sides) — a var() inside them is
    // dropped too, so always expand to per-side longhands (border-top-color, …).
    const sides = prop === 'border' ? ['top', 'right', 'bottom', 'left'] : [prop.slice('border-'.length)];
    const out = [];
    for (const side of sides) {
      if (width) out.push(`border-${side}-width:${width}${important}`);
      if (style) out.push(`border-${side}-style:${style}${important}`);
      if (color) out.push(`border-${side}-color:${color}${important}`);
    }
    return out.length ? out : null;
  }
  if (prop === 'background' && parts.length === 1 && !/url\(|gradient\(/i.test(value)) return [`background-color:${value}${important}`];
  return null;
}

function sbSplitPreservedCss(css) {
  css = (css || '').replace(/\/\*[\s\S]*?\*\//g, '');
  const editorParts = [], preservedParts = [];
  let i = 0;
  while (i < css.length) {
    const open = css.indexOf('{', i);
    if (open < 0) { if (css.slice(i).trim()) editorParts.push(css.slice(i).trim()); break; }
    let depth = 0, j = open;
    for (; j < css.length; j++) { if (css[j] === '{') depth++; else if (css[j] === '}') { depth--; if (depth === 0) break; } }
    const selector = css.slice(i, open).trim();
    const block = css.slice(open + 1, j);
    i = j + 1;
    if (selector.startsWith('@')) {
      // At-rules (media/supports/keyframes/font-face): kept whole for the editor; if any var()
      // shorthand is inside, the whole at-rule is also preserved verbatim.
      const text = `${selector}{${block}}`;
      editorParts.push(text);
      if (/(^|[;{\s])(background|padding|margin|border[a-z-]*|font|inset|outline|gap|flex|grid[a-z-]*|transition|animation)\s*:[^;}]*var\(/i.test(block)) preservedParts.push(text);
      continue;
    }
    const kept = [], dropped = [];
    for (const decl of sbSplitTop(block, ';')) {
      const k = decl.indexOf(':');
      if (k < 0) continue;
      const prop = decl.slice(0, k).trim().toLowerCase();
      const value = decl.slice(k + 1).trim();
      if (!SB_VAR_SHORTHANDS.has(prop) || !/var\(/i.test(value)) { kept.push(`${prop}:${value}`); continue; }
      const expanded = sbExpandShorthand(prop, value);
      if (expanded) kept.push(...expanded); else dropped.push(`${prop}:${value}`);
    }
    if (kept.length) editorParts.push(`${selector}{${kept.join(';')}}`);
    if (dropped.length) preservedParts.push(`${selector}{${dropped.join(';')}}`);
  }
  return { editorCss: editorParts.join('\n'), preservedCss: preservedParts.join('\n') };
}

// ── Design tokens (Site Builder S2) ──

const SB_COLOR_TOKENS = [
  ['primary', 'Primary (buttons, links)'], ['onPrimary', 'Text on primary'], ['secondary', 'Secondary (headings, dark sections)'],
  ['accent', 'Accent'], ['text', 'Body text'], ['muted', 'Muted text'], ['background', 'Background'], ['surface', 'Alternate background'], ['border', 'Borders'],
];

async function sbShowDesign() {
  if (!sbDomain) return;
  try {
    const d = await api(`${SB_API}/${sbDomain}/site`);
    const t = (d.manifest && d.manifest.tokens) || {};
    const fonts = d.fonts || [];
    window.__sbFonts = fonts;
    const fontSelect = (id, val) => `<select id="${id}" onchange="sbDesignPreview()">${fonts.map(f => `<option value="${escHtml(f.key)}" ${f.key === val ? 'selected' : ''}>${escHtml(f.label)}</option>`).join('')}</select>`;
    const colors = SB_COLOR_TOKENS.map(([k, label]) =>
      `<label style="display:flex;align-items:center;gap:8px;font-size:13px;margin:3px 0"><input type="color" id="sbt-${k}" value="${escHtml((t.colors || {})[k] || '#000000')}" oninput="sbDesignPreview()" style="width:38px;height:26px;padding:0;border:none;background:none"> ${escHtml(label)}</label>`).join('');
    const num = (id, label, val, min, max) => `<label style="font-size:13px;display:block;margin:4px 0">${label} <input type="number" id="${id}" value="${val}" min="${min}" max="${max}" style="width:80px" oninput="sbDesignPreview()"> px</label>`;
    showModal('Site Design', `
      <p style="margin:0 0 10px;color:#666;font-size:13px">These colours and fonts are used by the <b>Site style</b> blocks (Blocks panel → "Site style"). Change them once and every page using those blocks follows — on the live site after <b>Publish site</b>. Pages that don't use Site style blocks are never changed.</p>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
        <div><b style="font-size:13px">Colours</b>${colors}</div>
        <div>
          <b style="font-size:13px">Fonts</b>
          <label style="font-size:13px;display:block;margin:4px 0">Headings ${fontSelect('sbt-fontHeading', t.fontHeading)}</label>
          <label style="font-size:13px;display:block;margin:4px 0">Text ${fontSelect('sbt-fontBody', t.fontBody)}</label>
          <b style="font-size:13px;display:block;margin-top:10px">Layout</b>
          ${num('sbt-fontSize', 'Text size', t.fontSize, 12, 24)}
          ${num('sbt-radius', 'Corner radius', t.radius, 0, 48)}
          ${num('sbt-spacing', 'Spacing unit', t.spacing, 4, 48)}
          ${num('sbt-maxWidth', 'Content width', t.maxWidth, 600, 2000)}
          <div id="sbt-preview" style="margin-top:12px;padding:14px;border-radius:8px;border:1px solid #ddd"></div>
        </div>
      </div>`,
      [{ label: 'Save design', cls: 'btn-primary', onclick: 'sbSaveDesign()' }, { label: 'Reset to defaults', cls: 'btn', onclick: 'sbResetDesign()' }]);
    sbDesignPreview();
  } catch (e) { showAlert(e.message, 'error'); }
}

function sbReadDesignForm() {
  const v = id => document.getElementById(id).value;
  const colors = {};
  for (const [k] of SB_COLOR_TOKENS) colors[k] = v(`sbt-${k}`);
  return { colors, fontHeading: v('sbt-fontHeading'), fontBody: v('sbt-fontBody'),
    fontSize: Number(v('sbt-fontSize')), radius: Number(v('sbt-radius')), spacing: Number(v('sbt-spacing')), maxWidth: Number(v('sbt-maxWidth')) };
}

function sbDesignPreview() {
  const el = document.getElementById('sbt-preview');
  if (!el) return;
  const t = sbReadDesignForm();
  const font = k => ((window.__sbFonts || []).find(f => f.key === k) || {}).css || 'sans-serif';
  el.style.background = t.colors.background;
  el.innerHTML = `<div style="font-family:${escHtml(font(t.fontHeading))};color:${escHtml(t.colors.secondary)};font-size:18px;font-weight:bold;margin-bottom:6px">Heading preview</div>
    <div style="font-family:${escHtml(font(t.fontBody))};color:${escHtml(t.colors.text)};font-size:${t.fontSize}px;margin-bottom:8px">Body text <span style="color:${escHtml(t.colors.muted)}">and muted text</span>.</div>
    <span style="display:inline-block;background:${escHtml(t.colors.primary)};color:${escHtml(t.colors.onPrimary)};padding:8px 16px;border-radius:${t.radius}px;font-family:${escHtml(font(t.fontBody))};font-weight:600">Button</span>
    <span style="display:inline-block;background:${escHtml(t.colors.accent)};color:${escHtml(t.colors.onPrimary)};padding:8px 16px;border-radius:${t.radius}px;margin-left:6px">Accent</span>`;
}

async function sbSaveDesign(tokens) {
  try {
    await api(`${SB_API}/${sbDomain}/site`, { method: 'PUT', body: JSON.stringify({ tokens: tokens || sbReadDesignForm() }) });
    closeModal();
    showAlert('Design saved — use "🚀 Publish site…" to apply it to the live site', 'success');
    if (sbEditor && sbFile) { await sbSave(true); sbOpenEditor(sbFile); } // reload the canvas with the new tokens
  } catch (e) { showAlert(e.message, 'error'); }
}

function sbResetDesign() {
  if (!confirm('Reset colours, fonts and spacing to the defaults?')) return;
  sbSaveDesign({});
}

// ── Site Builder S2: global header/footer + menus ──
// Pages opt in by containing a <header|footer data-sb-global="…"> placeholder (the "Site header +
// menu" / "Site footer" blocks). In the editor those are the current rendering, locked: they are
// edited once in the Header & menu panel, and the server re-renders them on every save and publish.

function sbLockGlobal(comp) {
  const kind = comp.getAttributes()['data-sb-global'];
  comp.set({ editable: false, droppable: false, copyable: false, stylable: false, name: kind === 'footer' ? 'Site footer (🧭 Header & menu)' : 'Site header (🧭 Header & menu)' });
  comp.find('*').forEach(c => c.set({ editable: false, droppable: false, selectable: false, hoverable: false, draggable: false, removable: false, copyable: false, stylable: false, layerable: false }));
}

/** Replaces every global placeholder in the canvas with the current markup and locks it. */
function sbSyncGlobals(ed) {
  ed = ed || sbEditor;
  if (!ed) return;
  sbQuietUntil = Date.now() + 1500;   // a programmatic swap is not a user edit — no auto-save draft
  for (const kind of ['header', 'footer']) {
    const markup = sbRewriteImageUrls(sbGlobals[kind] || '', true);
    ed.getWrapper().find(`[data-sb-global="${kind}"]`).forEach(c => {
      if (markup && c.toHTML() !== markup) {
        const added = c.replaceWith(markup);
        (Array.isArray(added) ? added : [added]).forEach(sbLockGlobal);
      } else {
        sbLockGlobal(c);
      }
    });
  }
}

function sbRegisterGlobalBlocks(ed) {
  ed = ed || sbEditor;
  if (!ed) return;
  const bm = ed.BlockManager;
  const add = (id, label, kind) => {
    if (bm.get(id)) bm.remove(id);
    bm.add(id, { label, category: 'Site style', content: sbRewriteImageUrls(sbGlobals[kind] || '', true), attributes: { title: 'Shared by every page — edit it with 🧭 Header & menu' } });
  };
  add('sb-global-header', '🧭 Site header + menu', 'header');
  add('sb-global-footer', '🧭 Site footer', 'footer');
}

function sbSetupGlobals(ed) {
  ed.on('load', () => { sbRegisterGlobalBlocks(ed); sbRegisterPacks(ed); sbSyncGlobals(ed); });
  ed.on('component:add', c => {
    if (c.getAttributes && c.getAttributes()['data-sb-global']) setTimeout(() => sbLockGlobal(c), 0);
  });
  ed.on('component:selected', c => {
    if (c && c.getAttributes && c.getAttributes()['data-sb-global']) sbUpdateStatus('This is the shared site header/footer — change it with 🧭 Header & menu; it updates on every page that uses it.');
  });
}

async function sbShowGlobals() {
  if (!sbDomain) return;
  try {
    const d = await api(`${SB_API}/${sbDomain}/site`);
    const g = (d.manifest && d.manifest.globals) || {};
    window.__sbMenus = { menu: (g.menu || []).map(i => ({ ...i })), footerLinks: (g.footerLinks || []).map(i => ({ ...i })) };
    const pages = (d.pages || []).map(p => p.name);
    const field = (id, label, val, ph, hint) => `<div class="form-group" style="margin-bottom:8px"><label>${label}</label><input id="${id}" value="${escHtml(val || '')}" placeholder="${escHtml(ph)}">${hint ? `<small style="color:#888">${hint}</small>` : ''}</div>`;
    showModal('Header & menu', `
      <p style="margin:0 0 10px;color:#666;font-size:13px">Shared by every page that contains the <b>🧭 Site header + menu</b> or <b>🧭 Site footer</b> block (Blocks → "Site style"). Change it here once; <b>Publish site</b> updates it on all those pages. Other pages are never changed.</p>
      <datalist id="sb-page-list">${['/', ...pages].map(p => `<option value="${escHtml(p)}">`).join('')}</datalist>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
        ${field('sbg-siteName', 'Site name', g.siteName, sbDomain, 'Shown next to the logo')}
        ${field('sbg-logoUrl', 'Logo (optional)', g.logoUrl, '/images/logo.png', 'An uploaded image path or https:// URL')}
      </div>
      <b style="font-size:13px">Menu</b>
      <div id="sbg-menu"></div>
      <button type="button" class="btn btn-sm" onclick="sbMenuAdd('menu')">+ Add link</button>
      <div style="margin-top:14px">${field('sbg-footerText', 'Footer text', g.footerText, '© {year} {site}', '{year} and {site} are filled in automatically')}</div>
      <b style="font-size:13px">Footer links</b>
      <div id="sbg-footerLinks"></div>
      <button type="button" class="btn btn-sm" onclick="sbMenuAdd('footerLinks')">+ Add link</button>`,
      [{ label: 'Save', cls: 'btn-primary', onclick: 'sbSaveGlobals()' }]);
    sbRenderMenu('menu');
    sbRenderMenu('footerLinks');
  } catch (e) { showAlert(e.message, 'error'); }
}

/** Reads the menu rows currently in the form back into window.__sbMenus[key]. */
function sbReadMenu(key) {
  const el = document.getElementById(`sbg-${key}`);
  if (el) window.__sbMenus[key] = [...el.querySelectorAll('.sbg-row')].map(r => ({ label: r.querySelector('.sbg-label').value, href: r.querySelector('.sbg-href').value }));
  return window.__sbMenus[key];
}

function sbRenderMenu(key) {
  const el = document.getElementById(`sbg-${key}`);
  if (!el) return;
  const items = window.__sbMenus[key];
  el.innerHTML = items.length ? items.map((i, n) => `<div class="sbg-row" style="display:flex;gap:6px;align-items:center;margin:4px 0">
      <input class="sbg-label" value="${escHtml(i.label)}" placeholder="Label" style="flex:1" maxlength="60">
      <input class="sbg-href" value="${escHtml(i.href)}" placeholder="about.html, #contact, https://…" list="sb-page-list" style="flex:1.4">
      <button type="button" class="btn btn-sm" title="Move up" onclick="sbMenuMove('${key}',${n},-1)" ${n === 0 ? 'disabled' : ''}>↑</button>
      <button type="button" class="btn btn-sm" title="Move down" onclick="sbMenuMove('${key}',${n},1)" ${n === items.length - 1 ? 'disabled' : ''}>↓</button>
      <button type="button" class="btn btn-sm" title="Remove" onclick="sbMenuRemove('${key}',${n})">✕</button>
    </div>`).join('') : '<div style="color:#999;font-size:12px;margin:4px 0">No links</div>';
}

function sbMenuAdd(key) {
  const items = sbReadMenu(key);
  if (items.length >= 12) { showAlert('At most 12 links.', 'info'); return; }
  items.push({ label: '', href: '' });
  sbRenderMenu(key);
  const labels = document.querySelectorAll(`#sbg-${key} .sbg-label`);
  if (labels.length) labels[labels.length - 1].focus();
}
function sbMenuMove(key, n, dir) {
  const items = sbReadMenu(key);
  const m = n + dir;
  if (m < 0 || m >= items.length) return;
  [items[n], items[m]] = [items[m], items[n]];
  sbRenderMenu(key);
}
function sbMenuRemove(key, n) {
  sbReadMenu(key).splice(n, 1);
  sbRenderMenu(key);
}

async function sbSaveGlobals() {
  const v = id => document.getElementById(id).value.trim();
  const clean = key => sbReadMenu(key).map(i => ({ label: i.label.trim(), href: i.href.trim() })).filter(i => i.label || i.href);
  const globals = { siteName: v('sbg-siteName'), logoUrl: sbRewriteImageUrls(v('sbg-logoUrl'), false), footerText: v('sbg-footerText'), menu: clean('menu'), footerLinks: clean('footerLinks') };
  try {
    await api(`${SB_API}/${sbDomain}/site`, { method: 'PUT', body: JSON.stringify({ globals }) });
    closeModal();
    if (sbEditor && sbFile) {
      sbGlobals = await api(`${SB_API}/${sbDomain}/pages/${encodeURIComponent(sbFile)}/globals`);
      sbRegisterGlobalBlocks();
      sbSyncGlobals();
    }
    const onPage = sbEditor && sbEditor.getWrapper().find('[data-sb-global]').length;
    showAlert(onPage || !sbEditor
      ? 'Header & menu saved — use "🚀 Publish site…" to update every page that uses them'
      : 'Header & menu saved — drag "🧭 Site header + menu" (Blocks → Site style) onto a page to use it', 'success');
  } catch (e) { showAlert(e.message, 'error'); }
}

// ── Site Builder S2: section library picker (sections live in assets/grapesjs/sb-sections.js) ──

function sbShowSections(group) {
  if (!sbEditor) return;
  const prevBrief = document.getElementById('sb-ai-brief');
  if (prevBrief) window.__sbAiBrief = prevBrief.value;   // keep it when switching groups
  if (!window.SB_SECTIONS) { showAlert('The section library could not be loaded — reload the page and try again.', 'error'); return; }
  const lib = sbAllSections();   // library + installed packs
  const groupNames = ['All', ...lib.GROUPS];
  // Tabs pass the group's index, never its name: pack names are third-party text.
  const g = typeof group === 'number' ? (groupNames[group] || 'All') : (group || 'All');
  const tabs = groupNames.map((x, i) => `<button type="button" class="sb-tpl-cat-btn${x === g ? ' active' : ''}" onclick="sbShowSections(${i})">${escHtml(x)}</button>`).join('');
  const cards = lib.SECTIONS.filter(s => g === 'All' || s.group === g).map(s =>
    `<div class="sb-sec-card" tabindex="0" role="button" onclick="sbInsertSection('${s.id}')" onkeydown="if(event.key==='Enter')sbInsertSection('${s.id}')" title="${escHtml(s.description)}">
      <div class="sb-sec-thumb"><iframe tabindex="-1" sandbox="" data-sec="${s.id}" title=""></iframe></div>
      <div class="sb-sec-label">${escHtml(s.label)}</div><div class="sb-sec-desc">${escHtml(s.description)}</div>
    </div>`).join('');
  const where = sbEditor.getSelected() ? 'below the selected section' : 'at the end of the page';
  showModal('Insert a section', `<p style="margin:0 0 10px;color:#666;font-size:13px">Click a section to add it ${where}. Colours and fonts follow your <b>🎨 Design</b>; every text and image can be edited after inserting.</p>
    <div class="sb-ai-brief" id="sb-ai-brief-box" style="display:none"><label style="font-size:13px;font-weight:600">✨ Let AI write the text (optional) — describe the business or what this section is for</label>
      <textarea id="sb-ai-brief" rows="2" maxlength="600" placeholder="e.g. Family lawn-care company in San Juan: weekly mowing, garden design, free estimates">${escHtml(window.__sbAiBrief || '')}</textarea>
      <small id="sb-ai-brief-note" style="color:#888">Leave empty to insert the section with sample text.</small></div>
    <div class="sb-tpl-cats">${tabs}</div><div class="sb-sec-grid">${cards}</div>`, []);
  sbAiStatus().then(st => { const box = document.getElementById('sb-ai-brief-box'); if (box && st && st.available) box.style.display = ''; }).catch(() => { /* no AI: plain picker */ });
  const modal = document.querySelector('#modalContainer .modal');
  if (modal) modal.style.width = 'min(1100px, 96vw)';
  // Live previews: the real section markup + the site's current token CSS, in sandboxed frames (no scripts).
  document.querySelectorAll('.sb-sec-thumb iframe').forEach(f => {
    const s = lib.SECTIONS.find(x => x.id === f.dataset.sec);
    if (s) f.srcdoc = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>${sbSiteCss}</style><style>body{margin:0}</style></head><body>${s.html}</body></html>`;
  });
}

/** Inserts a library section after the top-level block that contains the selection (else before the site footer, else at the end). */
async function sbInsertSection(id) {
  const s = window.SB_SECTIONS && sbAllSections().SECTIONS.find(x => x.id === id);
  if (!s || !sbEditor) return;
  let html = s.html;
  const briefEl = document.getElementById('sb-ai-brief');
  const brief = briefEl && briefEl.offsetParent !== null ? briefEl.value.trim() : '';
  if (brief) {
    window.__sbAiBrief = brief;
    const card = document.querySelector(`.sb-sec-card[onclick="sbInsertSection('${id}')"]`);
    const note = document.getElementById('sb-ai-brief-note');
    document.querySelectorAll('.sb-sec-card').forEach(c => c.classList.add('sb-busy'));
    if (note) note.textContent = `✨ Writing the text for "${s.label}"…`;
    try {
      html = await sbAiFillSection(s, brief);
    } catch (e) {
      document.querySelectorAll('.sb-sec-card').forEach(c => c.classList.remove('sb-busy'));
      if (note) { note.textContent = e.message; note.style.color = '#b45309'; }
      return;
    }
    if (card) card.classList.remove('sb-busy');
  }
  const wrapper = sbEditor.getWrapper();
  const comps = wrapper.components();
  let sel = sbEditor.getSelected();
  while (sel && sel.parent() && sel.parent() !== wrapper) sel = sel.parent();
  let at;
  if (sel && sel.parent() === wrapper) {
    at = comps.indexOf(sel) + 1;
  } else {
    const footer = comps.find(c => c.getAttributes()['data-sb-global'] === 'footer');
    at = footer ? comps.indexOf(footer) : comps.length;
  }
  const added = comps.add(html, { at });
  const first = Array.isArray(added) ? added[0] : added;
  closeModal();
  sbEditor.select(first);
  try { first.getEl().scrollIntoView({ behavior: 'smooth', block: 'start' }); } catch { /* canvas not ready */ }
  showAlert(brief ? `"${s.label}" added with AI-written text — review it, then edit anything by clicking it` : `"${s.label}" added — click any text to edit it, double-click an image to replace it`, 'success');
}

// ── Site Builder S5: AI Site Assistant. The AI only returns TEXT; it is placed into existing
// elements as text nodes (never parsed as HTML), so nothing it writes can become code. ──

async function sbAiStatus(fresh) {
  if (!fresh && window.__sbAiSt && Date.now() - window.__sbAiSt.at < 60000) return window.__sbAiSt.st;
  const st = await api(`${SB_API}/${sbDomain}/ai/status`);
  window.__sbAiSt = { st, at: Date.now() };
  return st;
}

function sbAiUsageText(st) {
  if (!st) return '';
  return st.limit === null || st.limit === undefined
    ? `${st.used} AI action${st.used === 1 ? '' : 's'} used this month (administrator — no limit)`
    : `${st.used} of ${st.limit} AI actions used this month`;
}

/** Fills a library section's words: its text nodes go to the AI in order and come back as text. */
async function sbAiFillSection(section, brief) {
  const tpl = document.createElement('template');
  tpl.innerHTML = section.html;
  const nodes = [];
  const walker = document.createTreeWalker(tpl.content, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (!n.textContent.trim() || n.parentElement.closest('.sb-icon, .sb-hp, script, style')) continue;
    nodes.push(n);
  }
  const slots = nodes.map(n => ({ tag: n.parentElement.tagName.toLowerCase(), text: n.textContent.trim() }));
  const r = await api(`${SB_API}/${sbDomain}/ai/section`, { method: 'POST', body: JSON.stringify({ sectionId: section.id, brief, slots }) });
  if (!r || !Array.isArray(r.texts) || r.texts.length !== nodes.length) throw new Error('The AI answer did not match the section — try again');
  nodes.forEach((n, i) => {
    const lead = (n.textContent.match(/^\s*/) || [''])[0], trail = (n.textContent.match(/\s*$/) || [''])[0];
    n.textContent = `${lead}${String(r.texts[i])}${trail}`;   // textContent: always text, never markup
  });
  window.__sbAiSt = null;
  return tpl.innerHTML;
}

const SB_AI_INLINE = new Set(['STRONG', 'EM', 'B', 'I', 'U', 'BR', 'SPAN', 'SMALL', 'MARK']);

/** The selected element if it is a single piece of text the AI may rewrite. */
function sbAiTextTarget(comp) {
  if (!comp) return { ok: false, reason: 'Click a heading, paragraph, button or list item on the page first, then open ✨ AI.' };
  for (let c = comp; c; c = c.parent()) {
    if (c.getAttributes && c.getAttributes()['data-sb-global']) return { ok: false, reason: 'That is the shared site header/footer — change it with 🧭 Header & menu.' };
  }
  const el = comp.getEl && comp.getEl();
  if (!el) return { ok: false, reason: 'Select a text on the page first.' };
  const other = [...el.querySelectorAll('*')].find(x => !SB_AI_INLINE.has(x.tagName));
  if (other) return { ok: false, reason: 'This block contains other elements (links, images or sections). Click directly on a single heading, paragraph or button.' };
  const text = (el.innerText || el.textContent || '').trim();
  if (!text) return { ok: false, reason: 'This element has no text to rewrite.' };
  if (text.length > 4000) return { ok: false, reason: 'This text is too long for a rewrite (max 4000 characters) — select a smaller part.' };
  return { ok: true, comp, text };
}

async function sbShowAi() {
  if (!sbEditor || !sbDomain) return;
  let st;
  try { st = await sbAiStatus(true); } catch (e) { showAlert(e.message, 'error'); return; }
  const t = sbAiTextTarget(sbEditor.getSelected());
  window.__sbAiTarget = t.ok ? t : null;
  window.__sbAiResult = null;
  const presets = [['professional', 'More professional'], ['friendly', 'Friendlier'], ['shorter', 'Shorter'], ['longer', 'A bit longer'], ['simpler', 'Simpler'], ['fix', 'Fix spelling'], ['translate-es', '→ Spanish'], ['translate-en', '→ English']];
  const admin = st.settings ? `<div class="sb-ai-box"><b style="font-size:13px">Client settings (administrator)</b>
      <div style="display:flex;gap:14px;align-items:center;flex-wrap:wrap;font-size:13px;margin-top:6px">
        <label style="font-weight:normal"><input type="checkbox" id="sbai-on" ${st.settings.enabledForClients ? 'checked' : ''}> Pro clients can use AI</label>
        <label style="font-weight:normal">Monthly limit per client <input type="number" id="sbai-limit" min="0" max="100000" value="${st.settings.monthlyLimit}" style="width:90px"></label>
        <button class="btn btn-sm" onclick="sbAiSaveSettings()">Save</button></div></div>` : '';
  const body = !st.available
    ? `<p>${escHtml(st.reason || 'AI is not available.')}</p>${admin}`
    : `<p style="margin:0 0 6px;color:#666;font-size:12px" id="sbai-usage">${escHtml(sbAiUsageText(st))} · ${escHtml(st.provider || '')}</p>
      <b style="font-size:13px">Rewrite the selected text</b>
      ${t.ok ? `<div class="sb-ai-quote">${escHtml(t.text.slice(0, 300))}${t.text.length > 300 ? '…' : ''}</div>
        <div class="sb-ai-presets">${presets.map(([k, l]) => `<button class="btn btn-sm" onclick="sbAiRewrite('${k}')">${escHtml(l)}</button>`).join('')}</div>
        <div style="display:flex;gap:6px"><input id="sbai-instr" maxlength="300" placeholder="Or say how: e.g. mention free estimates" style="flex:1"><button class="btn btn-sm btn-primary" onclick="sbAiRewrite(null)">Rewrite</button></div>
        <div id="sbai-result"></div>`
      : `<p style="font-size:13px;color:#888;margin:4px 0">${escHtml(t.reason)}</p>`}
      <div class="sb-ai-box"><b style="font-size:13px">SEO title &amp; description</b>
        <p style="font-size:12px;color:#888;margin:2px 0 6px">Written from this page's text — shown in Google results and when the page is shared.</p>
        <button class="btn btn-sm" onclick="sbAiSeo()">✨ Suggest for ${escHtml(sbFile || 'this page')}</button><div id="sbai-seo"></div></div>
      <div class="sb-ai-box"><b style="font-size:13px">Write a whole section</b>
        <p style="font-size:12px;color:#888;margin:2px 0 0">Open <b>➕ Section</b> and describe the business in the ✨ box — the section you pick is inserted with the text already written.</p></div>
      ${admin}
      <p style="font-size:11px;color:#999;margin:10px 0 0">The text you send is processed by the AI service configured on this server. The AI only writes text — your page layout and code are never changed by it. ↩ Undo works as usual.</p>`;
  showModal('✨ AI Site Assistant', body, []);
}

async function sbAiRefreshUsage() {
  try { const st = await sbAiStatus(true); const el = document.getElementById('sbai-usage'); if (el) el.textContent = `${sbAiUsageText(st)} · ${st.provider || ''}`; } catch { /* cosmetic */ }
}

async function sbAiRewrite(preset) {
  const t = window.__sbAiTarget;
  const out = document.getElementById('sbai-result');
  if (!t || !out) return;
  const instruction = preset ? '' : (document.getElementById('sbai-instr').value || '').trim();
  if (!preset && !instruction) { out.innerHTML = '<div class="sb-pub-warn">Choose a style or type how to rewrite it.</div>'; return; }
  out.innerHTML = '<div class="sb-ai-out">✨ Writing…</div>';
  try {
    const r = await api(`${SB_API}/${sbDomain}/ai/rewrite`, { method: 'POST', body: JSON.stringify({ text: t.text, preset: preset || undefined, instruction: instruction || undefined }) });
    window.__sbAiResult = r.text;
    out.innerHTML = `<div class="sb-ai-out">${escHtml(r.text).replace(/\n/g, '<br>')}</div>
      <button class="btn btn-sm btn-primary" onclick="sbAiApplyRewrite()">Use this</button>
      <button class="btn btn-sm" onclick="sbAiRewrite(${preset ? `'${preset}'` : 'null'})">Try again</button>`;
  } catch (e) {
    out.innerHTML = `<div class="sb-pub-warn">${escHtml(e.message)}</div>`;
  }
  sbAiRefreshUsage();
}

function sbAiApplyRewrite() {
  const t = window.__sbAiTarget, text = window.__sbAiResult;
  if (!t || !text || !sbEditor) return;
  t.comp.components(escHtml(text).replace(/\n/g, '<br>'));   // escaped: the AI's answer is text, never markup
  closeModal();
  sbEditor.select(t.comp);
  showAlert('Text replaced — ↩ Undo brings the old text back', 'success');
}

async function sbAiSeo() {
  const out = document.getElementById('sbai-seo');
  if (!out || !sbFile) return;
  out.innerHTML = '<div class="sb-ai-out">✨ Reading the page and writing…</div>';
  try {
    await sbSave(true);   // the suggestion is based on what is on screen now
    const r = await api(`${SB_API}/${sbDomain}/ai/seo`, { method: 'POST', body: JSON.stringify({ fileName: sbFile }) });
    window.__sbAiSeo = r;
    out.innerHTML = `<div class="sb-ai-out"><b>${escHtml(r.title)}</b><br>${escHtml(r.description)}</div>
      <button class="btn btn-sm btn-primary" onclick="sbAiUseSeo()">Use these</button> <button class="btn btn-sm" onclick="sbAiSeo()">Try again</button>`;
  } catch (e) {
    out.innerHTML = `<div class="sb-pub-warn">${escHtml(e.message)}</div>`;
  }
  sbAiRefreshUsage();
}

function sbAiUseSeo() {
  const r = window.__sbAiSeo;
  if (!r) return;
  closeModal();
  sbShowSeoPanel();
  const set = (id, v, onlyIfEmpty) => { const el = document.getElementById(id); if (el && (!onlyIfEmpty || !el.value.trim())) el.value = v; };
  set('seo-title', r.title);
  set('seo-desc', r.description);
  set('seo-og-title', r.title, true);
  set('seo-og-desc', r.description, true);
  showAlert('Suggestions filled in — review them and click Save', 'info');
}

// ── Site Builder S6: site kits (a whole site from an industry recipe, as drafts) ──

async function sbShowKits() {
  if (!sbDomain) return;
  try {
    const d = await api(`${SB_API}/kits`);
    const kits = d.kits || [];
    window.__sbKits = kits;
    const cards = kits.map(k => `<div class="sb-sec-card" tabindex="0" role="button" onclick="sbKitForm('${k.id}')" onkeydown="if(event.key==='Enter')sbKitForm('${k.id}')">
        <div class="sb-sec-thumb" style="height:200px"><iframe tabindex="-1" sandbox="" data-kit="${k.id}" title=""></iframe></div>
        <div class="sb-sec-label">${escHtml(k.name)} <span style="font-weight:normal;color:#888">· ${escHtml(k.industry)}</span></div>
        <div class="sb-sec-desc">${escHtml(k.description)}<br><span style="display:inline-flex;gap:4px;margin-top:6px;vertical-align:middle">${[k.colors.primary, k.colors.secondary, k.colors.accent].map(c => `<span style="width:14px;height:14px;border-radius:50%;background:${/^#[0-9a-f]{3,6}$/i.test(c) ? c : '#ccc'};display:inline-block"></span>`).join('')}</span> ${k.pages.map(p => escHtml(p.menu)).join(' · ')}</div>
      </div>`).join('');
    showModal('🏗 Site kits', `<p style="margin:0 0 10px;color:#666;font-size:13px">A complete starting site for your kind of business: ${kits[0] ? kits[0].pages.length : 5} pages, menu, colours and fonts, and a working contact form. Everything is created as <b>drafts</b> — nothing goes live until you publish, and every text and image can be changed.</p>
      <div class="sb-sec-grid">${cards || '<p>No site kits are installed.</p>'}</div>`, []);
    const modal = document.querySelector('#modalContainer .modal');
    if (modal) modal.style.width = 'min(1100px, 96vw)';
    document.querySelectorAll('iframe[data-kit]').forEach(f => {
      const k = kits.find(x => x.id === f.dataset.kit);
      if (k) f.srcdoc = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>${k.previewCss}</style><style>body{margin:0}</style></head><body>${k.previewHtml}</body></html>`;
    });
  } catch (e) { showAlert(e.message, 'error'); }
}

async function sbKitForm(id) {
  const k = (window.__sbKits || []).find(x => x.id === id);
  if (!k) return;
  const existing = new Set((sbPagesCache || []).map(p => p.name));
  const conflicts = k.pages.map(p => p.file).filter(f => existing.has(f));
  let siteName = '';
  try { siteName = ((await api(`${SB_API}/${sbDomain}/site`)).manifest.globals || {}).siteName || ''; } catch { /* default */ }
  let st = null;
  try { st = await sbAiStatus(true); } catch { /* no AI */ }
  const left = st && st.available ? (st.limit === null || st.limit === undefined ? Infinity : st.limit - st.used) : 0;
  showModal(`🏗 ${escHtml(k.name)}`, `
    <p style="margin:0 0 10px;color:#666;font-size:13px">Creates these pages as drafts: <b>${k.pages.map(p => escHtml(p.file)).join(', ')}</b>.</p>
    <div class="form-group"><label>Business name</label><input id="sbk-name" maxlength="80" value="${escHtml(siteName)}" placeholder="${escHtml(sbDomain)}"></div>
    <div class="form-group" style="font-size:13px">
      <label style="font-weight:normal;display:block"><input type="checkbox" id="sbk-design" checked> Use the kit's colours and fonts (🎨 Design)</label>
      <label style="font-weight:normal;display:block"><input type="checkbox" id="sbk-menu" checked> Set the site header and menu to the kit's pages (🧭 Header &amp; menu)</label>
      ${conflicts.length ? `<label style="font-weight:normal;display:block;color:#b45309"><input type="checkbox" id="sbk-overwrite"> Replace existing pages: ${conflicts.map(escHtml).join(', ')} — their live versions stay online until you publish</label>` : ''}
    </div>
    ${st && st.available ? `<div class="form-group"><label>✨ Write the text for my business with AI (optional)</label>
      <textarea id="sbk-brief" rows="3" maxlength="600" placeholder="e.g. Italian family restaurant in Old San Juan, homemade pasta, terrace, open since 1998" style="width:100%;box-sizing:border-box"></textarea>
      <small style="color:#888">Uses up to ${k.aiSections} AI actions${left !== Infinity ? ` — you have ${Math.max(0, left)} left this month` : ''}. Leave empty to keep the kit's sample text.</small></div>` : ''}
    <div id="sbk-progress" style="font-size:13px"></div>`,
    [{ label: '🏗 Create the site', cls: 'btn-primary', onclick: `sbKitApply('${k.id}')` }]);
}

async function sbKitApply(id) {
  const k = (window.__sbKits || []).find(x => x.id === id);
  if (!k) return;
  const v = el => document.getElementById(el);
  const brief = v('sbk-brief') ? v('sbk-brief').value.trim() : '';
  const progress = v('sbk-progress');
  const say = t => { if (progress) progress.innerHTML = t; };
  document.querySelectorAll('#modalContainer .modal-actions button').forEach(b => { b.disabled = true; });
  try {
    say('Creating the pages…');
    const r = await sbPost(`/kits/${encodeURIComponent(id)}/apply`, {
      siteName: v('sbk-name').value.trim(), applyDesign: v('sbk-design').checked, applyMenu: v('sbk-menu').checked, overwrite: !!(v('sbk-overwrite') && v('sbk-overwrite').checked),
    });
    if (!r.ok) throw new Error(r.data.error || 'The site kit could not be applied');
    let aiNote = '';
    if (brief) {
      let done = 0, failed = 0;
      for (const [i, file] of r.data.pages.entries()) {
        say(`✨ Writing the text — page ${i + 1} of ${r.data.pages.length} (${escHtml(file)})…`);
        try {
          const p = await api(`${SB_API}/${sbDomain}/ai/personalize-page`, { method: 'POST', body: JSON.stringify({ fileName: file, brief }) });
          done += p.sections; failed += p.failed;
        } catch (e) {
          aiNote = ` AI stopped at ${file}: ${e.message}`;
          break;
        }
      }
      window.__sbAiSt = null;
      aiNote = ` ${done} section(s) written by AI${failed ? `, ${failed} kept the sample text` : ''}.${aiNote}`;
    }
    closeModal();
    showAlert(`Site created as drafts: ${r.data.pages.length} pages.${aiNote} Review them, then use "🚀 Publish site…".`, 'success');
    await sbLoadPages();
    sbOpenEditor(r.data.pages[0]);
  } catch (e) {
    say(`<div class="sb-pub-warn">${escHtml(e.message)}</div>`);
    document.querySelectorAll('#modalContainer .modal-actions button').forEach(b => { b.disabled = false; });
  }
}

// ── Site Builder S6: plugins (administrator) ──

async function sbShowPlugins() {
  try {
    const r = await api(`${SB_API}/plugins`);
    const builtIn = (r.plugins || []).map(p => `<tr><td><b>${escHtml(p.name)}</b><div style="font-size:11px;color:#888">${escHtml(p.description)}</div></td><td style="font-size:12px">built-in · ${escHtml(p.kind)}</td><td></td></tr>`).join('');
    const packs = (r.packs || []).map(p => `<tr><td><b>${escHtml(p.name)}</b> <span style="color:#888;font-size:12px">${escHtml(p.version)}${p.author ? ` · ${escHtml(p.author)}` : ''}</span><div style="font-size:11px;color:#888">${escHtml(p.description || '')} — ${p.sections.length} section(s)</div></td><td style="font-size:12px">section pack</td>
      <td><button class="btn btn-sm" style="color:#e17055" onclick="sbRemovePack('${escHtml(p.id)}')">Remove</button></td></tr>`).join('');
    showModal('🧩 Plugins', `
      <p style="margin:0 0 10px;color:#666;font-size:13px">Built-in plugins ship with the panel. <b>Section packs</b> add ready-made sections for all sites on this server — they are static HTML only (no scripts); a pack with anything unsafe is refused.</p>
      <table class="sb-pub-table"><tbody>${builtIn}${packs}</tbody></table>
      <div class="sb-ai-box"><b style="font-size:13px">Install a section pack</b>
        <div style="margin:6px 0"><input type="file" id="sbpl-file" accept=".json,application/json" onchange="sbPackFile(this)"></div>
        <textarea id="sbpl-json" rows="6" placeholder='{"schema":1,"id":"my-pack","name":"My pack","sections":[{"id":"hero","label":"Hero","html":"<section>…</section>"}]}' style="width:100%;box-sizing:border-box;font-family:monospace;font-size:12px"></textarea>
        <div id="sbpl-msg" class="sb-pub-warn" style="white-space:pre-wrap"></div></div>`,
      [{ label: 'Install pack', cls: 'btn-primary', onclick: 'sbInstallPack()' }]);
  } catch (e) { showAlert(e.message, 'error'); }
}

function sbPackFile(input) {
  const f = input.files && input.files[0];
  if (!f) return;
  if (f.size > 512 * 1024) { document.getElementById('sbpl-msg').textContent = 'A pack can be at most 512 KB.'; return; }
  const rd = new FileReader();
  rd.onload = () => { document.getElementById('sbpl-json').value = String(rd.result || ''); };
  rd.readAsText(f);
}

async function sbInstallPack() {
  const msg = document.getElementById('sbpl-msg');
  let pack;
  try { pack = JSON.parse(document.getElementById('sbpl-json').value); } catch { msg.textContent = 'That is not valid JSON.'; return; }
  try {
    const r = await api(`${SB_API}/plugins`, { method: 'POST', body: JSON.stringify({ pack }) });
    try { window.__sbPacks = (await api(`${SB_API}/plugins`)).packs || []; } catch { /* next load */ }   // used when a page is next opened
    showAlert(`Pack "${r.pack.name}" installed (${r.pack.sections.length} sections) — reopen a page to use it`, 'success');
    sbShowPlugins();
  } catch (e) { msg.textContent = e.message; }
}

async function sbRemovePack(id) {
  if (!confirm('Remove this section pack? Pages that already use its sections keep them.')) return;
  try {
    await api(`${SB_API}/plugins/${encodeURIComponent(id)}`, { method: 'DELETE' });
    try { window.__sbPacks = (await api(`${SB_API}/plugins`)).packs || []; } catch { /* next load */ }
    sbShowPlugins();
  } catch (e) { showAlert(e.message, 'error'); }
}

async function sbAiSaveSettings() {
  try {
    await api(`${SB_API}/ai/settings`, { method: 'PUT', body: JSON.stringify({ enabledForClients: document.getElementById('sbai-on').checked, monthlyLimit: Number(document.getElementById('sbai-limit').value) }) });
    window.__sbAiSt = null;
    showAlert('AI settings saved', 'success');
  } catch (e) { showAlert(e.message, 'error'); }
}

// ── Site Builder S3: pre-publish checks + custom code slots ──

function sbChecksList(checks) {
  if (!checks || !checks.length) return '<p style="margin:0">✅ No problems found.</p>';
  return `<ul class="sb-checks">${checks.map(c => `<li>${c.level === 'warn' ? '⚠️' : 'ℹ️'} ${escHtml(c.message)}</li>`).join('')}</ul>`;
}

/** Compact line for the Publish site card (warnings only expand on click). */
function sbChecksSummary(checks) {
  if (!checks) return '';
  const warns = checks.filter(c => c.level === 'warn').length;
  if (!checks.length) return '<div class="sb-checks-sum" style="color:#16a34a">✅ checks passed</div>';
  return `<details class="sb-checks-sum"><summary>${warns ? `⚠ ${warns} to check` : `ℹ ${checks.length} tip${checks.length > 1 ? 's' : ''}`}</summary>${sbChecksList(checks)}</details>`;
}

async function sbShowChecks() {
  if (!sbFile) return;
  try {
    if (sbEditor) await sbSave(true);
    const r = await api(`${SB_API}/${sbDomain}/pages/${encodeURIComponent(sbFile)}/checks`);
    showModal(`Page check: ${escHtml(sbFile)}`, `<p style="margin:0 0 8px;color:#666;font-size:13px">Quick checks on what would go live${r.source === 'draft' ? ' (your draft)' : ''} — search, accessibility, phones and the browser padlock. They never block publishing.</p>${sbChecksList(r.checks)}`, []);
  } catch (e) { showAlert(e.message, 'error'); }
}

async function sbShowCustomCode(siteOnly) {
  if (!sbDomain) return;
  try {
    const d = await api(`${SB_API}/${sbDomain}/site`);
    const s = (d.manifest && d.manifest.settings) || {};
    const file = siteOnly === true ? null : sbFile;
    const p = (file && d.manifest.pages && d.manifest.pages[file]) || {};
    const area = (id, val, ph) => `<textarea id="${id}" class="sb-code-area" spellcheck="false" placeholder="${escHtml(ph)}">${escHtml(val || '')}</textarea>`;
    showModal('Custom code', `
      <p style="margin:0 0 10px;color:#666;font-size:13px">For analytics, site-verification tags, chat widgets and similar snippets. The code goes into the published pages exactly as written — only paste code from a source you trust. It is added when you <b>publish</b>; "🚀 Publish site…" updates every published page.</p>
      <b style="font-size:13px">Whole site</b>
      <div class="form-group" style="margin:4px 0 8px"><label style="font-size:12px">Inside &lt;head&gt; (e.g. Google Analytics, verification meta tags)</label>${area('sbcc-site-head', s.headCode, '<script async src="https://www.googletagmanager.com/gtag/js?id=G-XXXX"></script>')}</div>
      <div class="form-group" style="margin:4px 0 12px"><label style="font-size:12px">Before &lt;/body&gt; (e.g. chat widget)</label>${area('sbcc-site-body', s.bodyEndCode, '<script src="…"></script>')}</div>
      ${file ? `<b style="font-size:13px">Only this page (${escHtml(file)})</b>
      <div class="form-group" style="margin:4px 0 8px"><label style="font-size:12px">Inside &lt;head&gt;</label>${area('sbcc-page-head', p.headCode, '')}</div>
      <div class="form-group" style="margin:4px 0 0"><label style="font-size:12px">Before &lt;/body&gt;</label>${area('sbcc-page-body', p.bodyEndCode, '')}</div>` : ''}`,
      [{ label: 'Save', cls: 'btn-primary', onclick: `sbSaveCustomCode(${file ? `'${escHtml(file)}'` : 'null'})` }]);
  } catch (e) { showAlert(e.message, 'error'); }
}

async function sbSaveCustomCode(file) {
  const v = id => { const el = document.getElementById(id); return el ? el.value : undefined; };
  const body = { settings: { headCode: v('sbcc-site-head'), bodyEndCode: v('sbcc-site-body') } };
  if (file) body.pages = { [file]: { headCode: v('sbcc-page-head'), bodyEndCode: v('sbcc-page-body') } };
  try {
    await api(`${SB_API}/${sbDomain}/site`, { method: 'PUT', body: JSON.stringify(body) });
    closeModal();
    showAlert('Custom code saved — it goes live with Publish ("🚀 Publish site…" updates every published page)', 'success');
  } catch (e) { showAlert(e.message, 'error'); }
}

// ── Site Builder S4: website forms (submissions are stored with the site and emailed) ──

async function sbShowForms() {
  if (!sbDomain) return;
  try {
    const d = await api(`${SB_API}/${sbDomain}/forms`);
    const forms = d.forms || [];
    window.__sbFormsDefault = d.defaultRecipient || '';
    window.__sbForms = forms;
    const rows = forms.map(f => {
      const s = f.settings || {};
      const to = s.emailEnabled === false ? '<span style="color:#888">email off</span>' : escHtml(s.email || d.defaultRecipient || '');
      return `<tr>
        <td><b>${escHtml(s.name || f.id)}</b><div style="font-size:11px;color:#888">id: ${escHtml(f.id)}${f.pages.length ? ` · on ${f.pages.map(escHtml).join(', ')}` : ' · not on any page'}</div></td>
        <td style="font-size:12px">${to}</td>
        <td style="font-size:12px">${f.count}${f.spam ? ` <span style="color:#888">(+${f.spam} spam)</span>` : ''}${f.last ? `<br><span style="color:#888">last ${new Date(f.last).toLocaleString()}</span>` : ''}</td>
        <td style="white-space:nowrap"><button class="btn btn-sm btn-primary" onclick="sbShowFormMessages('${escHtml(f.id)}')">Messages</button> <button class="btn btn-sm" onclick="sbShowFormSettings('${escHtml(f.id)}')">⚙</button></td>
      </tr>`;
    }).join('');
    showModal('📨 Website forms', forms.length
      ? `<p style="margin:0 0 10px;color:#666;font-size:13px">Messages visitors send through your website's forms. Each one is emailed to the recipient and kept here (export to CSV, delete any time). Likely spam is kept apart and not emailed.</p>
         <div style="max-height:55vh;overflow-y:auto"><table class="sb-pub-table"><thead><tr><th>Form</th><th>Sends to</th><th>Messages</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`
      : `<p>This site has no forms yet. Open a page, click <b>➕ Section</b> and add <b>Contact form</b> (group "Contact"). After you publish, messages from visitors are emailed to you and listed here.</p>`, []);
  } catch (e) { showAlert(e.message, 'error'); }
}

async function sbShowFormMessages(formId, spam) {
  try {
    const r = await api(`${SB_API}/${sbDomain}/forms/${encodeURIComponent(formId)}/submissions${spam ? '?spam=1' : ''}`);
    const f = (window.__sbForms || []).find(x => x.id === formId) || { settings: {}, spam: 0 };
    const subs = r.submissions || [];
    window.__sbSubs = subs;
    const summary = s => {
      const v = s.fields || {};
      const who = [v.name, v.email].filter(Boolean).join(' · ');
      const msg = v.message || Object.entries(v).filter(([k]) => !['name', 'email'].includes(k)).map(([, x]) => x).join(' · ');
      return `${who ? `<b>${escHtml(who)}</b><br>` : ''}${escHtml(String(msg).slice(0, 140))}${String(msg).length > 140 ? '…' : ''}`;
    };
    const rows = subs.map((s, i) => `<tr>
        <td><input type="checkbox" class="sb-sub-sel" value="${escHtml(s.id)}"></td>
        <td style="font-size:12px;white-space:nowrap">${new Date(s.at).toLocaleString()}${s.page ? `<br><span style="color:#888">${escHtml(s.page)}</span>` : ''}</td>
        <td style="font-size:13px">${summary(s)}${s.spam ? `<div class="sb-pub-warn">spam: ${escHtml(s.spamReason || '')}</div>` : ''}
          <details style="font-size:12px;margin-top:4px"><summary style="cursor:pointer;color:#2563eb">All fields</summary>${Object.entries(s.fields || {}).map(([k, v]) => `<div><b>${escHtml(k)}:</b> <span style="white-space:pre-wrap">${escHtml(v)}</span></div>`).join('')}<div style="color:#888">IP ${escHtml(s.ip || '')}</div></details></td>
      </tr>`).join('');
    showModal(`${spam ? 'Spam — ' : ''}${escHtml(f.settings.name || formId)} messages`, `
      <div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:8px">
        <button class="btn btn-sm" onclick="sbShowForms()">← Forms</button>
        ${spam ? `<button class="btn btn-sm" onclick="sbShowFormMessages('${escHtml(formId)}')">Show messages</button>` : `<button class="btn btn-sm" onclick="sbExportForm('${escHtml(formId)}')">⬇ Export CSV</button>${f.spam ? `<button class="btn btn-sm" onclick="sbShowFormMessages('${escHtml(formId)}', true)">Show spam (${f.spam})</button>` : ''}`}
        <button class="btn btn-sm" onclick="sbDeleteSubmissions('${escHtml(formId)}', false, ${spam ? 'true' : 'false'})">🗑 Delete selected</button>
        <button class="btn btn-sm" style="color:#e17055" onclick="sbDeleteSubmissions('${escHtml(formId)}', true)">Delete all</button>
      </div>
      ${subs.length ? `<div style="max-height:55vh;overflow-y:auto"><table class="sb-pub-table"><thead><tr><th></th><th>Received</th><th>Message</th></tr></thead><tbody>${rows}</tbody></table></div>${r.total > subs.length ? `<p style="font-size:12px;color:#888">Showing the newest ${subs.length} of ${r.total} — export to CSV for all.</p>` : ''}`
        : `<p>No ${spam ? 'spam' : 'messages'} yet.</p>`}`, []);
    const modal = document.querySelector('#modalContainer .modal');
    if (modal) modal.style.width = 'min(900px, 96vw)';
  } catch (e) { showAlert(e.message, 'error'); }
}

async function sbExportForm(formId) {
  try {
    const res = await fetch(`${API}${SB_API}/${sbDomain}/forms/${encodeURIComponent(formId)}/export.csv`, { headers: { 'Authorization': `Bearer ${token}` } });
    if (!res.ok) throw new Error(`Export failed (${res.status})`);
    const url = URL.createObjectURL(await res.blob());
    const a = document.createElement('a');
    a.href = url; a.download = `${sbDomain}-${formId}.csv`;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  } catch (e) { showAlert(e.message, 'error'); }
}

async function sbDeleteSubmissions(formId, all, spamView) {
  const ids = all ? 'all' : [...document.querySelectorAll('.sb-sub-sel:checked')].map(c => c.value);
  if (!all && !ids.length) { showAlert('Select the messages to delete first.', 'info'); return; }
  if (!confirm(all ? `Delete ALL messages of this form (spam included)? This cannot be undone — export to CSV first if you need them.` : `Delete ${ids.length} message(s)? This cannot be undone.`)) return;
  try {
    const r = await api(`${SB_API}/${sbDomain}/forms/${encodeURIComponent(formId)}/delete`, { method: 'POST', body: JSON.stringify({ ids }) });
    showAlert(`${r.deleted} message(s) deleted`, 'success');
    const d = await api(`${SB_API}/${sbDomain}/forms`);
    window.__sbForms = d.forms || [];
    sbShowFormMessages(formId, spamView && !all);
  } catch (e) { showAlert(e.message, 'error'); }
}

function sbShowFormSettings(formId) {
  const f = (window.__sbForms || []).find(x => x.id === formId) || { settings: {} };
  const s = f.settings || {};
  const pages = (sbPagesCache || []).map(p => p.name);
  showModal(`Form settings: ${escHtml(s.name || formId)}`, `
    <datalist id="sbf-pages">${pages.map(p => `<option value="${escHtml(p)}">`).join('')}</datalist>
    <div class="form-group"><label>Name (shown here and in the email subject)</label><input id="sbf-name" value="${escHtml(s.name || '')}" placeholder="${escHtml(formId)}" maxlength="80"></div>
    <div class="form-group"><label>Send messages to</label><input id="sbf-email" value="${escHtml(s.email || '')}" placeholder="${escHtml(window.__sbFormsDefault || '')}"><small style="color:#888">Empty = the account email above. Up to 5 addresses, separated by commas.</small></div>
    <div class="form-group"><label style="font-weight:normal"><input type="checkbox" id="sbf-on" ${s.emailEnabled === false ? '' : 'checked'}> Email each message (they are always kept here)</label></div>
    <div class="form-group"><label>Thank-you page (optional)</label><input id="sbf-thanks" value="${escHtml(s.thankYouUrl || '')}" placeholder="thank-you.html" list="sbf-pages"><small style="color:#888">Where visitors go after sending. Empty = a simple built-in "Thank you" page.</small></div>`,
    [{ label: 'Save', cls: 'btn-primary', onclick: `sbSaveFormSettings('${escHtml(formId)}')` }]);
}

async function sbSaveFormSettings(formId) {
  const v = id => document.getElementById(id).value.trim();
  try {
    await api(`${SB_API}/${sbDomain}/forms/${encodeURIComponent(formId)}`, { method: 'PUT', body: JSON.stringify({
      name: v('sbf-name'), email: v('sbf-email'), emailEnabled: document.getElementById('sbf-on').checked, thankYouUrl: v('sbf-thanks'),
    }) });
    showAlert('Form settings saved', 'success');
    sbShowForms();
  } catch (e) { showAlert(e.message, 'error'); }
}
