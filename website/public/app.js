// MacWand website: a working imitation of the app's window (scan, overview chart,
// sections, selection, Trash), plus small page behaviour (clock, feature tabs,
// latest-release links). Nothing here touches the visitor's files: the "scan" replays
// a made-up home folder.
(() => {
  "use strict";

  const REPO = "ypankovych/macwand";
  const GB = 1e9;
  const DAY = 86_400_000;
  const UNUSED_DAYS = 90;
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const SCAN_MS = reducedMotion ? 400 : 6500;

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

  // ---------- Icons (simplified SF Symbols) ----------

  const svg = (body, attrs = 'fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"') =>
    `<svg viewBox="0 0 16 16" aria-hidden="true" ${attrs}>${body}</svg>`;
  const ICONS = {
    overview: svg('<path d="M8 1.5A6.5 6.5 0 1 0 14.5 8H8z" fill="currentColor"/><path d="M9.5 0.5v6h6A6 6 0 0 0 9.5.5z" fill="currentColor" opacity=".55"/>', ""),
    large: svg('<path d="M5 3.5h5.5L13 6v8.5H5z" fill="currentColor"/><path d="M3 1.5h6M3 1.5v10" />'),
    apps: svg('<rect x="2" y="2" width="5" height="5" rx="1.3"/><rect x="9" y="2" width="5" height="5" rx="1.3"/><rect x="2" y="9" width="5" height="5" rx="1.3"/><rect x="9" y="9" width="5" height="5" rx="1.3"/>', 'fill="currentColor"'),
    user_caches: svg('<rect x="1.5" y="5" width="13" height="7" rx="2"/><path d="M4 9.5h.5M6 9.5h.5M8 9.5h.5"/>'),
    logs: svg('<path d="M3.5 1.5h6l3 3v10h-9z"/><path d="M5.5 7h5M5.5 9.5h5M5.5 12h3"/>'),
    xcode: svg('<path d="m2 14 6.5-6.5M9 2.5l4.5 4.5-2 2L7 4.5z"/>'),
    package_caches: svg('<path d="M8 1.5 14 4.5v7L8 14.5 2 11.5v-7z"/><path d="M2 4.5 8 7.5l6-3M8 7.5v7"/>'),
    downloads: svg('<circle cx="8" cy="8" r="6.5"/><path d="M8 4.5v6M5.5 8 8 10.5 10.5 8"/>'),
    trash: svg('<path d="M2.5 4h11M6 4V2.5h4V4M4 4l.8 10h6.4L12 4"/><path d="M6.8 6.5v5M9.2 6.5v5"/>'),
    dev_artifacts: svg('<path d="M5.5 4 2 8l3.5 4M10.5 4 14 8l-3.5 4"/>'),
    scan: svg('<path d="M13.5 8A5.5 5.5 0 1 1 11.6 3.8"/><path d="M13.5 2v3h-3"/>'),
    stop: svg('<rect x="3.5" y="3.5" width="9" height="9" rx="1.5" fill="currentColor"/>', ""),
    lens: '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><circle cx="10.5" cy="10.5" r="6"/><path d="m15 15 5 5"/></svg>',
    check: svg('<path d="m4 8.5 2.5 2.5L12 5.5" stroke-width="2"/>'),
    chevron: svg('<path d="m6 3.5 4.5 4.5L6 12.5"/>'),
    folder: '<svg class="file-icon" viewBox="0 0 16 16" aria-hidden="true"><path d="M1 3.5A1.5 1.5 0 0 1 2.5 2h3.6l1.5 1.5h5.9A1.5 1.5 0 0 1 15 5v7.5a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 1 12.5z" fill="#4aa7f5"/><path d="M1 5.5h14v7A1.5 1.5 0 0 1 13.5 14h-11A1.5 1.5 0 0 1 1 12.5z" fill="#6cbcfa"/></svg>',
    file: '<svg class="file-icon" viewBox="0 0 16 16" aria-hidden="true"><path d="M3 1h7l3 3v11H3z" fill="#fff" stroke="#b6b8c2" stroke-width=".8"/><path d="M10 1v3h3" fill="#e4e6ee" stroke="#b6b8c2" stroke-width=".8"/></svg>',
  };

  // ---------- The made-up Mac ----------

  const disk = { total: 494.38 * GB, free: 38.6 * GB };

  /** Cleanup categories, in the order the app lists them. */
  const CATEGORIES = [
    { id: "user_caches", name: "App Caches", color: "#33b3f2", safety: "safe",
      summary: "Per-app caches in ~/Library/Caches. Apps rebuild them as needed.",
      items: [["Homebrew", "~/Library/Caches", 2.6, 6], ["com.spotify.client", "~/Library/Caches", 1.8, 1], ["Google", "~/Library/Caches", 1.2, 1],
        ["JetBrains", "~/Library/Caches", 0.95, 14], ["com.tinyspeck.slackmacgap", "~/Library/Caches", 0.68, 1], ["com.apple.Safari", "~/Library/Caches", 0.42, 2]] },
    { id: "logs", name: "Logs", color: "#8c99ad", safety: "safe", summary: "Application and diagnostic logs.",
      items: [["JetBrains", "~/Library/Logs", 0.31, 14], ["DiagnosticReports", "~/Library/Logs", 0.12, 3]] },
    { id: "xcode", name: "Xcode Data", color: "#4087ff", safety: "safe", summary: "DerivedData, old device support files and simulator caches.",
      items: [["17.4 (21E219)", "~/Library/Developer/Xcode/iOS DeviceSupport", 5.6, 180], ["Storefront-bxkqzjv", "~/Library/Developer/Xcode/DerivedData", 4.2, 2],
        ["16.6 (20G75)", "~/Library/Developer/Xcode/iOS DeviceSupport", 3.9, 400]] },
    { id: "package_caches", name: "Package Caches", color: "#f5b333", safety: "safe", summary: "npm, pnpm, Cargo, Gradle, Maven, Go and pip/uv download caches.",
      items: [["_cacache", "~/.npm", 2.1, 3], ["modules-2", "~/.gradle/caches", 1.6, 45], ["uv", "~/.cache", 1.4, 9], ["cache", "~/.cargo/registry", 0.9, 12]] },
    { id: "downloads", name: "Downloads", color: "#33c79e", safety: "review", summary: "Everything in your Downloads folder.",
      items: [["Xcode_15.4.xip", "~/Downloads", 7.8, 120], ["ubuntu-24.04-desktop-arm64.iso", "~/Downloads", 3.1, 75], ["conference-talk.mov", "~/Downloads", 2.4, 33],
        ["photos-export.zip", "~/Downloads", 1.9, 160], ["Figma-Installer.dmg", "~/Downloads", 0.41, 210]] },
    { id: "trash", name: "Trash", color: "#9e9ea8", safety: "safe", permanent: true, summary: "Items already in the Trash. Removing them deletes them permanently.",
      items: [["Old Project Backup", "~/.Trash", 3.4, 8]] },
    { id: "dev_artifacts", name: "Build Artifacts", color: "#a866fa", safety: "safe", summary: "node_modules, Rust targets, Python virtualenvs and similar folders that rebuild from source.",
      items: [["api-gateway", "~/Projects", 3.1, 12, "Rust target", "target"], ["ml-experiments", "~/Projects", 2.3, 95, "Python virtualenv", ".venv"],
        ["storefront", "~/Projects", 1.42, 3, "node_modules", "node_modules"], ["analytics", "~/Projects", 1.1, 140, "Python virtualenv", ".venv"],
        ["design-system", "~/Projects", 0.96, 30, "node_modules", "node_modules"], ["mobile-app", "~/Projects", 0.82, 60, "CocoaPods", "Pods"],
        ["marketing-site", "~/Projects", 0.64, 21, "Next.js build", ".next"], ["infra", "~/Projects", 0.45, 200, "Terraform providers", ".terraform"],
        ["old-dashboard", "~/Archive", 0.38, 410, "node_modules", "node_modules"]] },
  ].map((category) => ({
    ...category,
    items: category.items.map(([name, location, gb, days, label, folder]) => ({
      id: `${location}/${name}${folder ? `/${folder}` : ""}`, name, location, size: gb * GB, modified: Date.now() - days * DAY, label, folder: !/\.\w{2,4}$/.test(name),
    })),
  }));

  const LARGE_FILES = [["Windows 11.vmdk", "~/Documents/Virtual Machines", 24, 70], ["Xcode_15.4.xip", "~/Downloads", 7.8, 120],
    ["Family Trip 2025.mov", "~/Movies", 6.2, 50], ["2023-photos.zip", "~/Documents/Archive", 4.1, 300], ["Album Stems.zip", "~/Music/Logic", 3.6, 140]]
    .map(([name, location, gb, days]) => ({ id: `${location}/${name}`, name, location, size: gb * GB, modified: Date.now() - days * DAY, folder: false }));

  const APPS = [["Docker", "#2496ed", 2, 2.1, 23.2], ["Steam", "#1b2838", 240, 0.9, 14.6], ["Android Studio", "#3ddc84", 150, 3.2, 4.8],
    ["Unity Hub", "#3a3a3c", 200, 0.5, 6.1], ["Microsoft Word", "#2b579a", 12, 2.9, 0.12], ["Slack", "#611f69", 1, 0.48, 1.3],
    ["Blender", "#e87d0d", 210, 1.3, 0.2], ["Spotify", "#1db954", 0, 0.4, 1.1], ["Figma", "#a259ff", 3, 0.5, 0.9], ["Zoom", "#2d8cff", 40, 0.3, 0.2],
    ["VLC", "#ff8800", 400, 0.15, 0.01]]
    .map(([name, color, days, app, support]) => ({ id: `/Applications/${name}.app`, name, color, lastUsed: Date.now() - days * DAY, size: app * GB, support: support * GB }))
    .map((app) => ({ ...app, total: app.size + app.support, unused: Date.now() - app.lastUsed > UNUSED_DAYS * DAY }));

  // When each finding turns up during the scan, as a fraction of the scan.
  (() => {
    const order = [];
    const queues = CATEGORIES.map((c) => [...c.items]);
    queues.push([...LARGE_FILES]);
    while (queues.some((q) => q.length)) queues.forEach((q) => q.length && order.push(q.shift()));
    order.forEach((item, i) => { item.at = 0.04 + (i / order.length) * 0.84; });
    APPS.forEach((app, i) => { app.at = 0.9 + (i / APPS.length) * 0.08; });
  })();

  const SCAN_PATHS = ["~/Library/Caches/Homebrew/downloads", "~/Projects/storefront/node_modules/react-dom/cjs", "~/Library/Developer/Xcode/DerivedData/Storefront-bxkqzjv/Build",
    "~/Documents/Virtual Machines", "~/.npm/_cacache/content-v2/sha512", "~/Projects/api-gateway/target/debug/deps", "~/Library/Application Support/Code/User",
    "~/Music/Logic/Album Stems", "~/Downloads", "~/.cache/uv/archive-v0", "~/Library/Containers/com.docker.docker/Data/vms", "~/Pictures/Exports",
    "~/Projects/ml-experiments/.venv/lib/python3.12/site-packages", "~/Library/Logs/DiagnosticReports", "~/Movies", "~/.gradle/caches/modules-2/files-2.1"];

  // ---------- State ----------

  const state = {
    phase: "idle",          // idle | scanning | done | stopped
    progress: 0,            // 0…1 while scanning
    view: "overview",       // overview | large | apps | <category id>
    selection: new Set(),
    sort: { key: "size", dir: -1 },
    onlyUnused: false,
    removed: new Set(),     // ids moved to the Trash or deleted
    trashBytes: 0,          // moved to the Trash by the visitor, not yet emptied
  };
  const seen = new Set();   // nav rows and tiles already animated in

  const found = (item) => state.phase !== "idle" && item.at <= state.progress && !state.removed.has(item.id);
  const itemsOf = (category) => category.items.filter(found);
  const sum = (list, key = "size") => list.reduce((total, item) => total + item[key], 0);
  const visibleCategories = () => CATEGORIES.filter((c) => itemsOf(c).length);
  const largeFiles = () => LARGE_FILES.filter(found);
  const apps = () => APPS.filter(found);
  const unusedApps = () => apps().filter((a) => a.unused);
  /** Large files not already inside a cleanup category, so totals don't double count. */
  const looseLargeFiles = () => {
    const claimed = new Set(CATEGORIES.flatMap(itemsOf).map((i) => i.id));
    return largeFiles().filter((f) => !claimed.has(f.id));
  };

  function findings() {
    const list = visibleCategories().map((c) => ({ id: c.id, title: c.name, color: c.color, icon: ICONS[c.id], size: sum(itemsOf(c)), detail: `${itemsOf(c).length} ${itemsOf(c).length === 1 ? "item" : "items"}`, view: c.id }));
    const loose = looseLargeFiles();
    if (loose.length) list.push({ id: "large", title: "Large Files", color: "#fa7359", icon: ICONS.large, size: sum(loose), detail: `${loose.length} ${loose.length === 1 ? "file" : "files"} over 100 MB`, view: "large" });
    const unused = unusedApps();
    if (unused.length) list.push({ id: "apps", title: "Unused Apps", color: "#ec6aa6", icon: ICONS.apps, size: sum(unused, "total"), detail: `${unused.length} not used in 3 months`, view: "apps" });
    return list.sort((a, b) => b.size - a.size);
  }
  const reclaimable = () => sum(findings());

  // ---------- Formatting ----------

  const numberFormat = (digits) => new Intl.NumberFormat(undefined, { maximumFractionDigits: digits });
  function bytes(n) {
    if (n >= GB) return `${numberFormat(n >= 100 * GB ? 1 : 2).format(n / GB)} GB`;
    if (n >= 1e6) return `${numberFormat(1).format(n / 1e6)} MB`;
    return `${numberFormat(0).format(n / 1e3)} KB`;
  }
  const dateFormat = new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short", year: "numeric" });
  const relative = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });
  function ago(time) {
    const days = Math.round((Date.now() - time) / DAY);
    if (days < 1) return "Today";
    if (days < 30) return relative.format(-days, "day");
    if (days < 365) return relative.format(-Math.round(days / 30), "month");
    return relative.format(-Math.round(days / 365), "year");
  }
  const escapeHTML = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  // ---------- Elements ----------

  const appWindow = $("#app");
  const nav = $("#appNav");
  const detail = $("#appDetail");
  const title = $("#appTitle");
  const scanButton = $("#scanButton");

  // ---------- Sidebar ----------

  function navRow(view, name, icon, color, size) {
    const fresh = !seen.has(`nav:${view}`);
    seen.add(`nav:${view}`);
    return `<button class="nav-item${fresh && view.length && !["overview", "large", "apps"].includes(view) ? " appear" : ""}" type="button" data-view="${view}" style="--c:${color}"${state.view === view ? ' aria-current="page"' : ""}>
      ${icon}<span class="nav-name">${escapeHTML(name)}</span><span class="nav-size">${size ? bytes(size) : ""}</span></button>`;
  }

  function renderNav() {
    const categories = visibleCategories();
    nav.innerHTML = navRow("overview", "Overview", ICONS.overview, "var(--accent)", 0)
      + navRow("large", "Large Files", ICONS.large, "#fa7359", sum(largeFiles()))
      + navRow("apps", "Applications", ICONS.apps, "#ec6aa6", sum(apps(), "total"))
      + (categories.length ? '<p class="nav-heading">Cleanup</p>' : "")
      + categories.map((c) => navRow(c.id, c.name, ICONS[c.id], c.color, sum(itemsOf(c)))).join("");
  }

  // ---------- Overview ----------

  let lastDisk = { used: 0, reclaim: 0 };

  function diskCard() {
    const used = disk.total - disk.free;
    const reclaim = Math.min(reclaimable(), used);
    return `<div class="disk">
      <div class="disk-head"><strong>Macintosh HD</strong><span class="spacer"></span><span class="free" id="diskFree">${bytes(disk.free)}</span><span class="of">free of ${bytes(disk.total)}</span></div>
      <div class="disk-bar"><span class="used" style="width:${lastDisk.used}%"></span><span class="reclaim" style="left:${lastDisk.used - lastDisk.reclaim}%;width:${lastDisk.reclaim}%"></span></div>
      <div class="disk-legend"><span><i style="--c:#f39a1d"></i>Used ${bytes(used)}</span>${reclaim ? `<span><i style="--c:#bf5fcc"></i>Can be freed ${bytes(reclaim)}</span>` : ""}<span><i style="--c:var(--text-3)"></i>Free ${bytes(disk.free)}</span></div>
    </div>`;
  }

  /** Moves the disk bar from its last state to the current one, so changes animate. */
  function animateDisk() {
    const bar = $(".disk-bar", detail);
    if (!bar) return;
    const used = ((disk.total - disk.free) / disk.total) * 100;
    const reclaim = (Math.min(reclaimable(), disk.total - disk.free) / disk.total) * 100;
    requestAnimationFrame(() => requestAnimationFrame(() => {
      $(".used", bar).style.width = `${used}%`;
      Object.assign($(".reclaim", bar).style, { left: `${used - reclaim}%`, width: `${reclaim}%` });
    }));
    lastDisk = { used, reclaim };
  }

  const welcome = () => `<div class="card welcome">
      <div class="welcome-icon"><img src="/assets/icon-256.png" alt=""></div>
      <h3>Find what's taking up space</h3>
      <p>Large files, caches, old downloads, build folders and apps you no longer use. Nothing is removed until you choose, and it goes to the Trash first.</p>
      <button class="push-button default" type="button" data-action="scan">${ICONS.lens.replace("<svg", '<svg width="15" height="15"')} Scan My Mac</button>
    </div>`;

  const scanning = () => `<div class="card scanning">
      <div class="radar" aria-hidden="true"><span class="ring"></span><span class="ring"></span><span class="ring"></span><span class="beam"></span><span class="lens">${ICONS.lens}</span></div>
      <div style="min-width:0;flex:1">
        <h3 class="scan-title">Scanning your Mac…</h3>
        <div class="scan-stats">
          <div><strong id="statFiles">0</strong><span>Files checked</span></div>
          <div><strong id="statBytes">0 KB</strong><span>Data checked</span></div>
          <div><strong class="reclaim-text" id="statFound">0 KB</strong><span>Can be freed</span></div>
        </div>
        <p class="scan-path" id="scanPath">&lrm;~</p>
      </div>
    </div>`;

  function donutSlices(list) {
    const total = sum(list) || 1;
    let start = 0;
    return list.map((f) => {
      const end = start + f.size / total;
      const slice = { ...f, start, end };
      start = end;
      return slice;
    });
  }

  /** SVG path for one ring segment, clockwise from 12 o'clock (same geometry as the app). */
  function arc(start, end) {
    const c = 95, outer = 90, inner = outer * 0.64;
    const span = (end - start) * 360;
    const inset = Math.min(0.8, span / 4);
    const a0 = ((start * 360 - 90 + inset) * Math.PI) / 180;
    const a1 = ((end * 360 - 90 - inset) * Math.PI) / 180;
    const large = end - start > 0.5 ? 1 : 0;
    const p = (r, a) => `${(c + r * Math.cos(a)).toFixed(2)} ${(c + r * Math.sin(a)).toFixed(2)}`;
    return `M${p(outer, a0)} A${outer} ${outer} 0 ${large} 1 ${p(outer, a1)} L${p(inner, a1)} A${inner} ${inner} 0 ${large} 0 ${p(inner, a0)}Z`;
  }

  function result(list) {
    const footnote = state.phase === "stopped"
      ? "Scan stopped. Showing what was found so far."
      : `1,284,512 files · 412 GB checked in 6.8 s`;
    return `<div class="card result">
      <div class="donut" id="donut">
        <svg viewBox="0 0 190 190" role="img" aria-label="Reclaimable space by section">
          <defs>${list.map((f) => `<linearGradient id="g-${f.id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${f.color}" stop-opacity=".8"/><stop offset="1" stop-color="${f.color}"/></linearGradient>`).join("")}</defs>
          ${donutSlices(list).map((s) => `<path class="slice" d="${arc(s.start, s.end)}" fill="url(#g-${s.id})" data-slice="${s.id}"/>`).join("")}
          ${donutSlices(list).map((s) => `<path class="hit" d="${arc(s.start, s.end)}" data-finding="${s.id}" data-view="${s.view}"><title>${escapeHTML(s.title)}: ${bytes(s.size)}</title></path>`).join("")}
        </svg>
        <div class="donut-center" id="donutCenter"></div>
      </div>
      <div class="result-side">
        <p class="label">Ready to clean</p>
        <p class="big-number">${bytes(sum(list))}</p>
        <p class="footnote">${footnote}</p>
        <ul class="legend">${list.slice(0, 7).map((f) => `<li><button type="button" data-finding="${f.id}" data-view="${f.view}" style="--c:${f.color}"><i></i><span>${escapeHTML(f.title)}</span><span class="size">${bytes(f.size)}</span></button></li>`).join("")}</ul>
      </div>
    </div>`;
  }

  function tiles(list) {
    const total = sum(list) || 1;
    return `<div class="tiles">${list.map((f) => {
      const fresh = !seen.has(`tile:${f.id}`);
      seen.add(`tile:${f.id}`);
      return `<button class="tile" type="button" data-view="${f.view}" style="--c:${f.color}${fresh ? "" : ";animation:none"}">
        <span style="display:flex;justify-content:space-between;align-items:center"><span class="badge-icon">${f.icon}</span><span style="width:12px;color:var(--text-3)">${ICONS.chevron}</span></span>
        <span><span class="tile-name">${escapeHTML(f.title)}</span><br><span class="tile-size">${bytes(f.size)}</span><br><span class="tile-detail">${escapeHTML(f.detail)}</span></span>
        <span class="tile-bar"><i style="width:${Math.max(3, (f.size / total) * 100)}%"></i></span>
      </button>`;
    }).join("")}</div>`;
  }

  function renderOverview() {
    const list = findings();
    // Mid-scan, patch the changing parts so the radar animation keeps running.
    if (state.phase === "scanning" && $(".scanning", detail)) {
      $(".disk", detail).outerHTML = diskCard();
      animateDisk();
      const html = tiles(list);
      const current = $(".tiles", detail);
      if (current) current.outerHTML = html; else $(".overview", detail).insertAdjacentHTML("beforeend", html);
      updateScanStats();
      return;
    }
    let hero = welcome();
    if (state.phase === "scanning") hero = scanning();
    else if (state.phase !== "idle") hero = list.length ? result(list) : '<div class="card welcome"><h3>All clean</h3><p>Nothing left to remove. Scan again any time.</p></div>';
    detail.className = "app-detail";
    detail.innerHTML = `<div class="overview">${diskCard()}${hero}${state.phase === "idle" ? "" : tiles(list)}</div>`;
    animateDisk();
    setDonutHighlight(null);
    if (state.phase === "scanning") updateScanStats();
  }

  function setDonutHighlight(id) {
    const donut = $("#donut");
    if (!donut) return;
    const list = findings();
    const hot = list.find((f) => f.id === id);
    donut.classList.toggle("dim", Boolean(hot));
    $$(".slice", donut).forEach((p) => p.classList.toggle("hot", p.dataset.slice === id));
    $$(".legend button").forEach((b) => b.classList.toggle("hot", b.dataset.finding === id));
    $("#donutCenter").innerHTML = hot
      ? `<span class="badge-icon" style="--c:${hot.color};margin:0 auto 4px;width:26px;height:26px">${hot.icon}</span><strong>${bytes(hot.size)}</strong><span>${escapeHTML(hot.title)}</span>`
      : `<strong>${list.length}</strong><span>findings</span>`;
  }

  // ---------- Lists ----------

  function sorted(list, columns) {
    const column = columns.find((c) => c.key === state.sort.key) || columns[columns.length - 1];
    return [...list].sort((a, b) => {
      const x = column.sortValue(a), y = column.sortValue(b);
      return (x < y ? -1 : x > y ? 1 : 0) * (state.sort.key === column.key ? state.sort.dir : -1);
    });
  }

  function table(rows, columns) {
    if (!rows.length) return '<div class="empty-list">Nothing here. This spot is already clean.</div>';
    return `<table class="table" aria-multiselectable="true">
      <colgroup>${columns.map((c) => `<col class="col-${c.key}" style="width:${c.width}">`).join("")}</colgroup>
      <thead><tr>${columns.map((c) => `<th class="col-${c.key}${c.num ? " num" : ""}" data-sort="${c.key}"${state.sort.key === c.key ? ` aria-sort="${state.sort.dir < 0 ? "descending" : "ascending"}"` : ""}>${c.label}</th>`).join("")}</tr></thead>
      <tbody>${sorted(rows, columns).map((row) => `<tr data-id="${escapeHTML(row.id)}" aria-selected="${state.selection.has(row.id)}" title="${escapeHTML(row.id)}">${columns.map((c) => `<td class="col-${c.key}${c.num ? " num" : ""}">${c.cell(row)}</td>`).join("")}</tr>`).join("")}</tbody>
    </table>`;
  }

  const FILE_COLUMNS = [
    { key: "name", label: "Name", width: "42%", sortValue: (i) => i.name.toLowerCase(),
      cell: (i) => `<span class="name-cell">${i.folder ? ICONS.folder : ICONS.file}<span class="name">${escapeHTML(i.name)}</span>${i.label ? `<span class="tag">${escapeHTML(i.label)}</span>` : ""}</span>` },
    { key: "location", label: "Location", width: "23%", sortValue: (i) => i.location, cell: (i) => `<span class="muted">${escapeHTML(i.location)}</span>` },
    { key: "modified", label: "Modified", width: "21%", sortValue: (i) => i.modified, cell: (i) => `<span class="muted">${dateFormat.format(i.modified)}</span>` },
    { key: "size", label: "Size", width: "14%", num: true, sortValue: (i) => i.size, cell: (i) => bytes(i.size) },
  ];

  const APP_COLUMNS = [
    { key: "name", label: "Name", width: "34%", sortValue: (a) => a.name.toLowerCase(),
      cell: (a) => `<span class="name-cell"><span class="app-icon" style="--c:${a.color}">${escapeHTML(a.name.split(" ").map((w) => w[0]).join("").slice(0, 2))}</span><span class="name">${escapeHTML(a.name)}</span></span>` },
    { key: "lastUsed", label: "Last Used", width: "20%", sortValue: (a) => a.lastUsed, cell: (a) => `<span class="${a.unused ? "warn" : "muted"}">${ago(a.lastUsed)}</span>` },
    { key: "app", label: "App", width: "14%", num: true, sortValue: (a) => a.size, cell: (a) => bytes(a.size) },
    { key: "support", label: "Support Files", width: "17%", num: true, sortValue: (a) => a.support, cell: (a) => bytes(a.support) },
    { key: "total", label: "Total", width: "15%", num: true, sortValue: (a) => a.total, cell: (a) => `<strong style="font-weight:600">${bytes(a.total)}</strong>` },
  ];

  function bars(list, segments) {
    const top = [...list].sort((a, b) => segments.reduce((s, g) => s + b[g.key], 0) - segments.reduce((s, g) => s + a[g.key], 0)).slice(0, 6);
    const max = Math.max(1, ...top.map((r) => segments.reduce((s, g) => s + r[g.key], 0)));
    return `<div class="bars">${top.map((row) => {
      const total = segments.reduce((s, g) => s + row[g.key], 0);
      return `<div class="bar-row"><span class="bar-name">${escapeHTML(row.name)}</span>
        <span class="bar-track"><span class="bar-fill" style="width:0" data-width="${Math.max(1, (total / max) * 100)}%">${segments.map((g) => `<i style="width:${(row[g.key] / total) * 100}%;background:linear-gradient(color-mix(in srgb, ${g.color} 78%, #fff), ${g.color})"></i>`).join("")}</span></span>
        <span class="bar-size">${bytes(total)}</span></div>`;
    }).join("")}</div>`;
  }

  function growBars() {
    requestAnimationFrame(() => requestAnimationFrame(() => $$(".bar-fill", detail).forEach((b) => { b.style.width = b.dataset.width; })));
  }

  function listView({ color, icon, total, count, summary, safety, headExtra = "", barsHTML, rows, columns, actionTitle }) {
    const selected = rows.filter((r) => state.selection.has(r.id));
    detail.className = "app-detail list-mode";
    detail.innerHTML = `
      <div class="list-head" style="--c:${color}">
        <div>
          <div class="list-total"><span class="badge-icon" style="--c:${color}">${icon}</span><div><strong>${bytes(total)}</strong><span>${count}</span></div></div>
          <p class="list-summary">${escapeHTML(summary)}</p>
          ${safety ? `<span class="safety ${safety}">${safety === "safe" ? "✓ Safe to remove, rebuilt automatically" : "◉ Review before removing"}</span>` : ""}
          ${headExtra}
        </div>
        <div>${rows.length > 1 ? barsHTML : ""}</div>
      </div>
      <div class="table-wrap">${table(rows, columns)}</div>
      <div class="action-bar">
        <span class="hint">${selected.length ? `${selected.length} selected · ${bytes(sum(selected, columns === APP_COLUMNS ? "total" : "size"))}` : "Click rows to select them."}</span>
        <button class="push-button${selected.length ? " destructive" : ""}" type="button" data-action="remove"${selected.length ? "" : " disabled"}>${actionTitle}</button>
      </div>`;
    growBars();
  }

  function renderCategory(category) {
    const rows = itemsOf(category);
    listView({
      color: category.color, icon: ICONS[category.id], total: sum(rows), count: `${rows.length} items`, summary: category.summary, safety: category.safety,
      barsHTML: bars(rows, [{ key: "size", color: category.color }]), rows, columns: FILE_COLUMNS,
      actionTitle: category.permanent ? "Delete Permanently" : "Move to Trash",
    });
  }

  function renderLarge() {
    const rows = largeFiles();
    listView({
      color: "#fa7359", icon: ICONS.large, total: sum(rows), count: `${rows.length} files`, summary: "Files of 100 MB or more in your home folder.", safety: "review",
      barsHTML: bars(rows, [{ key: "size", color: "#fa7359" }]), rows, columns: FILE_COLUMNS, actionTitle: "Move to Trash",
    });
  }

  function renderApps() {
    const all = apps();
    const rows = state.onlyUnused ? all.filter((a) => a.unused) : all;
    listView({
      color: "#ec6aa6", icon: ICONS.apps, total: sum(all, "total"), count: `${all.length} apps · ${all.filter((a) => a.unused).length} unused`,
      summary: "Uninstalling moves the app and the files it keeps in ~/Library to the Trash.",
      headExtra: `<label class="toggle"><input type="checkbox" data-action="unused"${state.onlyUnused ? " checked" : ""}> Only apps not used in 3 months</label>`,
      barsHTML: `<div class="bar-legend"><span><i style="--c:#5c85fa"></i>App</span><span><i style="--c:#a866fa"></i>Support files</span></div>`
        + bars(rows, [{ key: "size", color: "#ec6aa6" }, { key: "support", color: "#a866fa" }]),
      rows, columns: APP_COLUMNS, actionTitle: "Uninstall",
    });
  }

  // ---------- Rendering ----------

  const TITLES = { overview: "Overview", large: "Large Files", apps: "Applications" };

  function render() {
    if (!["overview", "large", "apps"].includes(state.view) && !CATEGORIES.some((c) => c.id === state.view && itemsOf(c).length)) state.view = "overview";
    title.textContent = TITLES[state.view] || CATEGORIES.find((c) => c.id === state.view).name;
    scanButton.innerHTML = state.phase === "scanning" ? ICONS.stop : ICONS.scan;
    scanButton.setAttribute("aria-label", state.phase === "scanning" ? "Stop scanning" : "Scan this Mac");
    scanButton.title = state.phase === "scanning" ? "Stop scanning (⌘.)" : "Scan this Mac (⌘R)";
    renderNav();
    if (state.view === "overview") renderOverview();
    else if (state.view === "large") renderLarge();
    else if (state.view === "apps") renderApps();
    else renderCategory(CATEGORIES.find((c) => c.id === state.view));
  }

  function show(view) {
    if (view === state.view) return;
    state.view = view;
    state.selection.clear();
    state.sort = { key: view === "apps" ? "total" : "size", dir: -1 };
    closeSheet();
    render();
  }

  // ---------- Scanning ----------

  let scanStart = 0;
  let frame = 0;
  let lastCount = -1;

  const easeOut = (t) => 1 - Math.pow(1 - t, 2.2);

  function updateScanStats() {
    const p = easeOut(state.progress);
    const set = (id, text) => { const el = $(id); if (el) el.textContent = text; };
    set("#statFiles", numberFormat(0).format(Math.round(1_284_512 * p)));
    set("#statBytes", bytes(412 * GB * p));
    set("#statFound", bytes(reclaimable()));
    set("#scanPath", `‎${SCAN_PATHS[Math.floor(performance.now() / 90) % SCAN_PATHS.length]}`);
  }

  function tick(now) {
    state.progress = Math.min(1, (now - scanStart) / SCAN_MS);
    const count = [...CATEGORIES.flatMap((c) => c.items), ...LARGE_FILES, ...APPS].filter(found).length;
    if (count !== lastCount) { lastCount = count; render(); }
    else if (state.view === "overview") { updateScanStats(); }
    if (state.progress < 1) frame = requestAnimationFrame(tick);
    else { state.phase = "done"; render(); }
  }

  function startScan() {
    cancelAnimationFrame(frame);
    state.phase = "scanning";
    state.progress = 0;
    state.view = "overview";
    state.selection.clear();
    lastCount = -1;
    scanStart = performance.now();
    render();
    frame = requestAnimationFrame(tick);
  }

  function stopScan() {
    cancelAnimationFrame(frame);
    state.phase = "stopped";
    render();
  }

  // ---------- Removing ----------

  const sheet = $("#sheet");
  let pending = null;

  function selectedRows() {
    if (state.view === "apps") return APPS.filter((a) => state.selection.has(a.id) && found(a));
    const source = state.view === "large" ? LARGE_FILES : (CATEGORIES.find((c) => c.id === state.view) || { items: [] }).items;
    return source.filter((i) => state.selection.has(i.id) && found(i));
  }

  function askToRemove() {
    const rows = selectedRows();
    if (!rows.length) return;
    const isApps = state.view === "apps";
    const permanent = state.view === "trash";
    const size = bytes(sum(rows, isApps ? "total" : "size"));
    const noun = rows.length === 1 ? `“${rows[0].name}”` : `${rows.length} ${isApps ? "apps" : "items"}`;
    $("#sheetTitle").textContent = isApps ? `Uninstall ${noun} (${size})?` : permanent ? `Permanently delete ${noun} (${size})?` : `Move ${noun} (${size}) to the Trash?`;
    $("#sheetMessage").textContent = permanent ? "This can't be undone."
      : isApps ? "The apps and the support files they keep in ~/Library go to the Trash. You can put them back from there."
      : "You can put them back from the Trash. Space is freed when you empty the Trash.";
    $("#sheetConfirm").textContent = permanent ? "Delete" : "Move to Trash";
    pending = { rows, isApps, permanent };
    sheet.hidden = false;
    $("#sheetConfirm").focus({ preventScroll: true });
  }

  function closeSheet() {
    sheet.hidden = true;
    pending = null;
  }

  function confirmRemove() {
    if (!pending) return;
    const { rows, isApps, permanent } = pending;
    closeSheet();
    const freed = sum(rows, isApps ? "total" : "size");
    rows.forEach((row) => $(`tr[data-id="${CSS.escape(row.id)}"]`, detail)?.classList.add("leaving"));
    setTimeout(() => {
      rows.forEach((row) => state.removed.add(row.id));
      state.selection.clear();
      if (permanent) {
        changeFreeSpace(freed);
        toast(`Freed ${bytes(freed)}`, `${rows.length} ${rows.length === 1 ? "item" : "items"} deleted.`);
      } else {
        state.trashBytes += freed;
        toast(`${bytes(freed)} moved to the Trash`, "Empty the Trash in the Dock to get the space back.");
        bounce($("#dockTrash"));
      }
      updateTrash();
      render();
    }, reducedMotion ? 0 : 420);
  }

  const toastEl = $("#toast");
  let toastTimer = null;
  function toast(heading, body) {
    toastEl.innerHTML = `<span class="check">${ICONS.check}</span><span><strong>${escapeHTML(heading)}</strong><span>${escapeHTML(body)}</span></span>`;
    toastEl.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toastEl.hidden = true; }, 4200);
  }

  // ---------- Dock and Trash ----------

  const trashItems = () => CATEGORIES.find((c) => c.id === "trash").items.filter((i) => !state.removed.has(i.id));
  const trashTotal = () => state.trashBytes + sum(trashItems());

  function updateTrash() {
    const full = trashTotal() > 0;
    $("#trashCan").classList.toggle("full", full);
    $("#trashLabel").textContent = full ? `Trash, ${bytes(trashTotal())}` : "Trash, empty";
  }

  function bounce(element) {
    element.classList.remove("bounce");
    void element.offsetWidth;
    element.classList.add("bounce");
  }

  /** Adds freed bytes to the disk and counts the free-space label up to the new value. */
  function changeFreeSpace(delta) {
    const from = disk.free;
    disk.free = Math.min(disk.total, disk.free + delta);
    const to = disk.free;
    const started = performance.now();
    const step = (now) => {
      const t = Math.min(1, (now - started) / 900);
      const label = $("#diskFree");
      if (label) label.textContent = bytes(from + (to - from) * easeOut(t));
      if (t < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }

  const trashAlert = $("#trashAlert");
  $("#dockTrash").addEventListener("click", () => {
    if (!trashTotal()) { notify("The Trash is empty", "Remove something in MacWand first, then empty the Trash here."); return; }
    $("#trashAlertBody").textContent = `${bytes(trashTotal())} will be freed. You can't undo this action.`;
    trashAlert.hidden = false;
    $("#trashEmpty").focus({ preventScroll: true });
  });
  $("#trashCancel").addEventListener("click", () => { trashAlert.hidden = true; });
  $("#trashEmpty").addEventListener("click", () => {
    trashAlert.hidden = true;
    const freed = trashTotal();
    trashItems().forEach((i) => state.removed.add(i.id));
    state.trashBytes = 0;
    if (state.view === "overview") render();
    changeFreeSpace(freed);
    updateTrash();
    if (state.view !== "overview") render();
    notify("Trash emptied", `${bytes(freed)} is free again. Macintosh HD now has ${bytes(disk.free)} available.`);
  });
  trashAlert.addEventListener("keydown", (e) => { if (e.key === "Escape") trashAlert.hidden = true; });

  $("#dockApp").addEventListener("click", (e) => {
    e.preventDefault();
    bounce(e.currentTarget);
    appWindow.scrollIntoView({ behavior: reducedMotion ? "auto" : "smooth", block: "center" });
    appWindow.focus({ preventScroll: true });
  });

  // ---------- Notification banner ----------

  const note = $("#notification");
  let noteTimer = null;
  function notify(heading, body) {
    $("#notificationTitle").textContent = heading;
    $("#notificationBody").textContent = body;
    note.hidden = false;
    clearTimeout(noteTimer);
    noteTimer = setTimeout(() => { note.hidden = true; }, 5000);
  }

  // ---------- Events inside the window ----------

  scanButton.addEventListener("click", () => (state.phase === "scanning" ? stopScan() : startScan()));
  nav.addEventListener("click", (e) => { const item = e.target.closest("[data-view]"); if (item) show(item.dataset.view); });
  $("#sheetCancel").addEventListener("click", closeSheet);
  $("#sheetConfirm").addEventListener("click", confirmRemove);

  let anchor = null;
  detail.addEventListener("click", (e) => {
    const action = e.target.closest("[data-action]");
    if (action?.dataset.action === "scan") return startScan();
    if (action?.dataset.action === "remove") return askToRemove();
    const target = e.target.closest("[data-view]");
    if (target) return show(target.dataset.view);
    const header = e.target.closest("th[data-sort]");
    if (header) {
      const key = header.dataset.sort;
      state.sort = { key, dir: state.sort.key === key ? -state.sort.dir : (key === "name" || key === "location" ? 1 : -1) };
      return render();
    }
    const row = e.target.closest("tbody tr");
    if (row) {
      const rows = $$("tbody tr", detail).map((r) => r.dataset.id);
      if (e.shiftKey && anchor && rows.includes(anchor)) {
        const [a, b] = [rows.indexOf(anchor), rows.indexOf(row.dataset.id)].sort((x, y) => x - y);
        rows.slice(a, b + 1).forEach((id) => state.selection.add(id));
      } else if (state.selection.has(row.dataset.id)) {
        state.selection.delete(row.dataset.id);
      } else {
        state.selection.add(row.dataset.id);
      }
      anchor = row.dataset.id;
      render();
    }
  });
  detail.addEventListener("change", (e) => {
    if (e.target.dataset.action === "unused") { state.onlyUnused = e.target.checked; state.selection.clear(); render(); }
  });

  // Donut and legend hover highlight the same finding.
  detail.addEventListener("pointerover", (e) => {
    const target = e.target.closest("[data-finding]");
    if (target) setDonutHighlight(target.dataset.finding);
  });
  detail.addEventListener("pointerout", (e) => {
    const target = e.target.closest("[data-finding]");
    if (target && !target.contains(e.relatedTarget)) setDonutHighlight(null);
  });

  appWindow.addEventListener("keydown", (e) => {
    const cmd = e.metaKey || e.ctrlKey;
    if (e.key === "Escape" && !sheet.hidden) closeSheet();
    else if (cmd && e.key.toLowerCase() === "r") (state.phase === "scanning" ? null : startScan());
    else if (cmd && e.key === ".") (state.phase === "scanning" ? stopScan() : null);
    else if (cmd && e.key.toLowerCase() === "a" && state.view !== "overview") {
      $$("tbody tr", detail).forEach((r) => state.selection.add(r.dataset.id));
      render();
    } else if (cmd && (e.key === "Backspace" || e.key === "Delete")) askToRemove();
    else return;
    e.preventDefault();
  });

  // ---------- Menu bar clock ----------

  const clock = $("#clock");
  const clockFormat = new Intl.DateTimeFormat(undefined, { weekday: "short", day: "numeric", month: "short", hour: "numeric", minute: "2-digit" });
  const updateClock = () => { clock.textContent = clockFormat.format(new Date()).replace(/,/g, ""); };
  updateClock();
  setInterval(updateClock, 15_000);

  // ---------- Feature tabs ----------

  const tabs = $$('.sidebar [role="tab"]');
  function selectTab(tab, focus) {
    tabs.forEach((t) => {
      const on = t === tab;
      t.setAttribute("aria-selected", String(on));
      t.tabIndex = on ? 0 : -1;
      $(`#${t.getAttribute("aria-controls")}`).hidden = !on;
    });
    if (focus) tab.focus();
  }
  tabs.forEach((tab, i) => {
    tab.addEventListener("click", () => selectTab(tab, false));
    tab.addEventListener("keydown", (e) => {
      const step = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }[e.key];
      if (!step) return;
      e.preventDefault();
      selectTab(tabs[(i + step + tabs.length) % tabs.length], true);
    });
  });

  // ---------- Latest release links ----------

  fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers: { Accept: "application/vnd.github+json" } })
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then((release) => {
      const dmg = (release.assets || []).find((a) => a.name.endsWith(".dmg"));
      if (!dmg) return;
      ["#downloadHero", "#downloadFile", "#downloadStep", "#downloadBottom"].forEach((id) => { $(id).href = dmg.browser_download_url; });
      $("#dmgName").textContent = dmg.name;
      $("#versionLabel").textContent = `Version ${release.tag_name.replace(/^v/, "")}`;
    })
    .catch(() => { /* links already point at the releases page */ });

  updateTrash();
  render();
})();
