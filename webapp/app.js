'use strict';

(() => {
  const tg = window.Telegram && window.Telegram.WebApp ? window.Telegram.WebApp : null;
  const API_BASE = window.location.origin;

  const state = {
    token: sessionStorage.getItem('hisobchi_wa_token') || '',
    user: null,
    tab: 'dashboard',
    loading: true,
    error: null,
    summary: null,
    viewedSummary: null,
    historySessions: [],
    debts: [],
    nasiya: null,
    allSuppliers: [],
    periodKey: '7d',
    periodLabel: 'Oxirgi 7 kunlik dinamika',
    seriesGranularity: 'daily',
    dailySeries: [],
    selectedTrendIdx: null,
    customDateFrom: null,
    customDateTo: null,
    timelineFilter: 'all',
    filterMode: 'all',
    sortMode: 'newest',
    searchQuery: '',
    debtSubTab: 'nakladnoy',
    debtSupplierFilter: 'all',
  };

  const $root = document.getElementById('app-root');
  const $nav = document.getElementById('bottom-nav');
  const $fab = document.getElementById('fab-add');
  const $topbarSub = document.getElementById('topbar-sub');
  const $debtBadge = document.getElementById('nav-debt-badge');
  const $sheetOverlay = document.getElementById('sheet-overlay');
  const $sheetTitle = document.getElementById('sheet-title');
  const $sheetBody = document.getElementById('sheet-body');
  const $lightbox = document.getElementById('lightbox');
  const $lightboxImg = document.getElementById('lightbox-img');
  const $toast = document.getElementById('toast');

  let toastTimer = null;

  function esc(val) {
    return String(val == null ? '' : val)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function fmtUzs(num, withCur = false) {
    if (num == null || Number.isNaN(Number(num))) return withCur ? "0 so'm" : '0';
    const rounded = Math.round(Number(num));
    const neg = rounded < 0 ? '-' : '';
    const digits = Math.abs(rounded).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
    return `${neg}${digits}${withCur ? " so'm" : ''}`;
  }

  function formatDigitsInput(raw) {
    const clean = String(raw || '').replace(/\D+/g, '');
    if (!clean) return '';
    return clean.replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  }

  function parseUzsInput(raw) {
    const clean = String(raw || '').replace(/\D+/g, '');
    if (!clean) return null;
    const n = Number(clean);
    return Number.isFinite(n) && n > 0 ? n : null;
  }

  function bindUzsFormatter(inputEl) {
    if (!inputEl) return;
    inputEl.addEventListener('input', () => {
      const formatted = formatDigitsInput(inputEl.value);
      inputEl.value = formatted;
    });
  }

  function haptic(kind = 'selection') {
    try {
      if (!tg || !tg.HapticFeedback) return;
      if (kind === 'success') tg.HapticFeedback.notificationOccurred('success');
      else if (kind === 'error') tg.HapticFeedback.notificationOccurred('error');
      else tg.HapticFeedback.selectionChanged();
    } catch (_) {}
  }

  function showToast(msg, isErr = false) {
    $toast.textContent = msg;
    $toast.className = `toast${isErr ? ' err' : ''}`;
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      $toast.className = 'toast hidden';
    }, 3200);
  }

  function applyTheme(dark) {
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
    localStorage.setItem('hisobchi_theme', dark ? 'dark' : 'light');
    document.getElementById('btn-theme').textContent = dark ? '☀️' : '🌙';
  }

  function initTelegramChrome() {
    const saved = localStorage.getItem('hisobchi_theme');
    const tgDark = tg && tg.colorScheme === 'dark';
    applyTheme(saved ? saved === 'dark' : tgDark);
    if (tg) {
      try {
        tg.ready();
        tg.expand();
        if (tg.onEvent) {
          tg.onEvent('themeChanged', () => {
            if (!localStorage.getItem('hisobchi_theme')) {
              applyTheme(tg.colorScheme === 'dark');
            }
          });
        }
      } catch (_) {}
    }
  }

  async function apiFetch(path, opts = {}, retryAuth = true) {
    const headers = Object.assign({}, opts.headers || {});
    if (state.token) {
      headers['Authorization'] = `Bearer ${state.token}`;
    }
    if (opts.json !== undefined) {
      headers['Content-Type'] = 'application/json';
      opts.body = JSON.stringify(opts.json);
    }
    const res = await fetch(`${API_BASE}${path}`, {
      method: opts.method || 'GET',
      headers,
      body: opts.body,
    });
    if (res.status === 401 && retryAuth && tg && tg.initData) {
      await authenticateWebApp();
      return apiFetch(path, opts, false);
    }
    let data = {};
    const ctype = res.headers.get('content-type') || '';
    if (ctype.includes('application/json')) {
      data = await res.json();
    } else {
      data = { detail: await res.text() };
    }
    if (!res.ok) {
      const err = new Error(data.detail || data.message || `Xatolik (${res.status})`);
      err.status = res.status;
      throw err;
    }
    return data;
  }

  async function authenticateWebApp() {
    const initData = tg && tg.initData ? tg.initData.trim() : '';
    if (!initData) {
      const err = new Error("Iltimos, ilovani Telegram bot ichidan (/app yoki menyu tugmasidan) oching.");
      err.status = 401;
      throw err;
    }
    const res = await fetch(`${API_BASE}/auth/telegram-webapp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ init_data: initData }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || !data.access_token) {
      const err = new Error(data.detail || `Kirish taqiqlangan (${res.status})`);
      err.status = res.status;
      throw err;
    }
    state.token = data.access_token;
    state.user = data;
    sessionStorage.setItem('hisobchi_wa_token', data.access_token);
    return data;
  }

  function photoUrl(paymentId, cacheBust = '') {
    const q = `token=${encodeURIComponent(state.token)}${cacheBust ? `&v=${cacheBust}` : ''}`;
    return `${API_BASE}/nakladnoy/${paymentId}/photo?${q}`;
  }

  function downloadExcel(path, filename) {
    const sep = path.includes('?') ? '&' : '?';
    const url = `${API_BASE}${path}${sep}token=${encodeURIComponent(state.token)}`;
    if (tg && typeof tg.downloadFile === 'function') {
      try {
        tg.downloadFile({ url, file_name: filename });
        return;
      } catch (_) {}
    }
    if (tg && typeof tg.openLink === 'function') {
      try {
        tg.openLink(url);
        return;
      } catch (_) {}
    }
    window.open(url, '_blank');
  }

  // Sheet Modal Controls
  function openSheet(title, htmlContent, onMount) {
    $sheetTitle.textContent = title;
    $sheetBody.innerHTML = htmlContent;
    $sheetOverlay.classList.remove('hidden');
    $sheetOverlay.setAttribute('aria-hidden', 'false');
    if (typeof onMount === 'function') onMount($sheetBody);
  }

  function closeSheet() {
    $sheetOverlay.classList.add('hidden');
    $sheetOverlay.setAttribute('aria-hidden', 'true');
    $sheetBody.innerHTML = '';
  }

  function openLightbox(src) {
    $lightboxImg.src = src;
    $lightbox.classList.remove('hidden');
  }

  // Reusable Custom Dropdown (No native <select>)
  function renderCustomDropdownTrigger({ id, labelText, value, options, compact = false }) {
    let sel = options.find((o) => String(o.value) === String(value)) || options[0];
    const lblHtml = labelText && !compact ? `<span class="custom-dd-lbl">${esc(labelText)}</span>` : '';
    const icoHtml = sel && sel.icon ? `<span class="custom-dd-ico">${esc(sel.icon)}</span>` : '';
    const badgeHtml = sel && sel.badge ? `<span class="custom-dd-badge tnum">${esc(sel.badge)}</span>` : '';
    return `
      <div class="custom-dd-wrap">
        ${lblHtml}
        <button class="custom-dd-btn${compact ? ' compact' : ''}" id="${esc(id)}" type="button">
          ${icoHtml}
          <span class="custom-dd-text">${esc(sel ? sel.label : 'Tanlang')}</span>
          ${badgeHtml}
          <span class="custom-dd-chev">▾</span>
        </button>
      </div>
    `;
  }

  function openCustomDropdown({ title, value, options, searchable = false, onSelect }) {
    haptic();
    const showSearch = searchable || options.length >= 8;
    const renderList = (q) => {
      const needle = (q || '').trim().toLowerCase();
      const filtered = needle
        ? options.filter(
            (o) =>
              o.label.toLowerCase().includes(needle) ||
              (o.subtitle && o.subtitle.toLowerCase().includes(needle))
          )
        : options;
      if (!filtered.length) {
        return `<div class="card" style="text-align:center;color:var(--text-2);">Mos variant topilmadi</div>`;
      }
      return filtered
        .map((o) => {
          const isSel = String(o.value) === String(value);
          return `
            <button class="dd-option${isSel ? ' selected' : ''}" data-dd-val="${esc(o.value)}" type="button">
              ${o.icon ? `<span class="custom-dd-ico">${esc(o.icon)}</span>` : ''}
              <div style="flex:1;min-width:0;">
                <div class="dd-option-lbl">${esc(o.label)}</div>
                ${o.subtitle ? `<div class="dd-option-sub">${esc(o.subtitle)}</div>` : ''}
              </div>
              ${o.badge ? `<span class="custom-dd-badge tnum">${esc(o.badge)}</span>` : ''}
              ${isSel ? '<span style="color:var(--brand);font-weight:900;">✓</span>' : ''}
            </button>
          `;
        })
        .join('');
    };

    const html = `
      ${showSearch ? '<input id="dd-search-input" class="input" placeholder="Qidirish..." autocomplete="off" />' : ''}
      <div id="dd-options-list" style="display:flex;flex-direction:column;gap:7px;">
        ${renderList('')}
      </div>
    `;
    openSheet(title || 'Tanlang', html, (body) => {
      const listEl = body.querySelector('#dd-options-list');
      const searchEl = body.querySelector('#dd-search-input');
      const bindClicks = () => {
        listEl.querySelectorAll('[data-dd-val]').forEach((btn) => {
          btn.addEventListener('click', () => {
            haptic();
            const chosen = btn.getAttribute('data-dd-val');
            closeSheet();
            onSelect(chosen);
          });
        });
      };
      bindClicks();
      if (searchEl) {
        searchEl.addEventListener('input', () => {
          listEl.innerHTML = renderList(searchEl.value);
          bindClicks();
        });
      }
    });
  }

  async function fetchTrendStats() {
    let q = 'days=7';
    if (state.periodKey === 'today') q = 'days=1&preset=today';
    else if (state.periodKey === 'yesterday') q = 'days=1&preset=yesterday';
    else if (state.periodKey === '14d') q = 'days=14';
    else if (state.periodKey === '30d') q = 'days=30';
    else if (state.periodKey === 'custom' && state.customDateFrom && state.customDateTo) {
      q = `days=30&date_from=${encodeURIComponent(state.customDateFrom)}&date_to=${encodeURIComponent(state.customDateTo)}`;
    }
    const p = await apiFetch(`/stats/period?${q}`);
    state.dailySeries = Array.isArray(p.daily_series) ? p.daily_series : [];
    state.seriesGranularity = p.granularity || (state.dailySeries[0] && String(state.dailySeries[0].date).includes(':') ? 'hourly' : 'daily');
  }

  async function refreshAll(silent = false) {
    if (!silent) {
      state.loading = true;
      render();
    }
    try {
      const [statusData, debtsData] = await Promise.all([
        apiFetch('/status'),
        apiFetch('/debts'),
      ]);
      state.summary = statusData;
      state.debts = Array.isArray(debtsData.items) ? debtsData.items : [];

      await Promise.allSettled([
        apiFetch('/history/sessions?limit=30').then((h) => {
          state.historySessions = Array.isArray(h.sessions) ? h.sessions : [];
        }),
        apiFetch('/suppliers').then((s) => {
          state.allSuppliers = Array.isArray(s.suppliers) ? s.suppliers : [];
        }),
        fetchTrendStats(),
        state.viewedSummary
          ? apiFetch(`/history/sessions/${state.viewedSummary.session_id}`).then((d) => {
              state.viewedSummary = d;
            })
          : Promise.resolve(),
      ]);

      state.error = null;
    } catch (err) {
      state.error = err;
    } finally {
      state.loading = false;
      render();
    }
  }

  // Rendering helpers
  function pmBadge(n) {
    if (n.is_debt) return '<span class="tag tag-debt">📌 Qarzga</span>';
    if (n.payment_method === 'card') return '<span class="tag tag-card">💳 Karta</span>';
    if (n.payment_method === 'transfer') return '<span class="tag tag-transfer">🏦 O\'tkazma</span>';
    return '<span class="tag tag-cash">💵 Naqd</span>';
  }

  function renderNakCard(n) {
    const grpTag = n.in_group
      ? '<span class="tag tag-grp">📤 Guruhda</span>'
      : '<span class="tag tag-local">💾 Bazada</span>';
    const photoTag = n.has_photo ? '<span class="tag tag-local">📸 Rasm</span>' : '';
    const datePart = n.report_date ? `${esc(n.report_date)} • ` : '';
    const origPart =
      n.original_amount != null && Math.round(n.original_amount) !== Math.round(n.amount)
        ? ` <span style="opacity:.7">(asli ${fmtUzs(n.original_amount)})</span>`
        : '';
    return `
      <div class="nak-card" data-nak-id="${n.id}">
        <div class="row-between">
          <div class="nak-sup">${esc(n.supplier_name)}</div>
          <div class="nak-amt tnum">${fmtUzs(n.amount, true)}</div>
        </div>
        <div class="nak-meta">
          <div class="row" style="gap:5px;flex-wrap:wrap;">
            ${pmBadge(n)}
            ${grpTag}
            ${photoTag}
          </div>
          <div>${datePart}${esc(n.time_hm)} • ${esc(n.display_num)}${origPart}</div>
        </div>
        ${n.note ? `<div style="margin-top:6px;font-size:12px;color:var(--text-2);">💬 ${esc(n.note)}</div>` : ''}
      </div>
    `;
  }

  function renderSessionSwitcherBar(activeSummary, isViewingPast) {
    const sessions = state.historySessions || [];
    const curId = activeSummary.session_id;
    const curIdx = sessions.findIndex((s) => s.id === curId);
    const hasPrev = curIdx >= 0 && curIdx + 1 < sessions.length;
    const hasNext = curIdx > 0;

    const options = sessions.map((s) => {
      const isCurOpen = state.summary && s.id === state.summary.session_id;
      return {
        value: s.id,
        label: `${s.report_date} • Smena #${s.id}`,
        subtitle: isCurOpen
          ? 'Bugungi faol ochiq smena'
          : `Kutilgan naqd: ${fmtUzs(s.expected_cash, true)}`,
        icon: isCurOpen ? '🟢' : '📅',
        badge: isCurOpen ? 'Faol' : `#${s.id}`,
      };
    });

    const centerHtml = options.length
      ? renderCustomDropdownTrigger({
          id: 'dd-session-switcher',
          value: options.some((o) => o.value === curId) ? curId : options[0].value,
          options,
          compact: true,
        })
      : `<div style="text-align:center;font-weight:900;">📅 ${esc(activeSummary.report_date)} (Smena #${curId})</div>`;

    return `
      <div class="card switcher-card">
        <div class="switcher-row">
          <button class="icon-btn" id="btn-prev-sess" type="button" ${hasPrev ? '' : 'disabled'} title="Oldingi smena">‹</button>
          <div style="flex:1;min-width:0;">${centerHtml}</div>
          <button class="icon-btn" id="btn-next-sess" type="button" ${hasNext ? '' : 'disabled'} title="Keyingi smena">›</button>
        </div>
        ${
          isViewingPast && state.summary
            ? `<button class="btn btn-soft btn-sm btn-block" id="btn-back-today" type="button" style="margin-top:8px;">
                 🟢 Bugungi faol smenaga qaytish (${esc(state.summary.report_date)})
               </button>`
            : ''
        }
      </div>
    `;
  }

  function renderDonutCard(s) {
    const naks = s.nakladnoys || [];
    const cntCash = naks.filter((n) => !n.is_debt && n.payment_method === 'cash').length;
    const cntCard = naks.filter((n) => !n.is_debt && n.payment_method === 'card').length;
    const cntTr = naks.filter((n) => !n.is_debt && n.payment_method === 'transfer').length;
    const cntDebt = naks.filter((n) => n.is_debt).length;

    const segments = [
      { key: 'cash', label: 'Naqd', val: Number(s.total_nakladnoy_spent || 0), cnt: cntCash, color: '#059669' },
      { key: 'card', label: 'Karta', val: Number(s.total_card_spent || 0), cnt: cntCard, color: '#2563EB' },
      { key: 'transfer', label: "O'tkazma", val: Number(s.total_transfer_spent || 0), cnt: cntTr, color: '#9333EA' },
      { key: 'debt', label: 'Qarzga', val: Number(s.total_debt_nakladnoy || 0), cnt: cntDebt, color: '#D97706' },
    ];
    const grand = segments.reduce((a, b) => a + b.val, 0);
    const R = 44;
    const C = 2 * Math.PI * R;
    let offset = 0;
    const arcs = grand > 0
      ? segments
          .filter((seg) => seg.val > 0)
          .map((seg) => {
            const len = (seg.val / grand) * C;
            const dash = `${Math.max(0, len - 2)} ${C}`;
            const dashOffset = -offset;
            offset += len;
            return `<circle cx="66" cy="66" r="${R}" fill="none" stroke="${seg.color}" stroke-width="18" stroke-dasharray="${dash}" stroke-dashoffset="${dashOffset}" transform="rotate(-90 66 66)" />`;
          })
          .join('')
      : `<circle cx="66" cy="66" r="${R}" fill="none" stroke="var(--border)" stroke-width="18" />`;

    return `
      <div class="card">
        <div class="chart-header">
          <div>
            <div class="chart-title">Dumaloq Statistika</div>
            <div class="chart-sub">To'lov turlari bo'yicha ulush (${esc(s.report_date)})</div>
          </div>
          <span class="tag tag-local tnum">${naks.length} ta</span>
        </div>
        <div class="donut-wrap">
          <div class="donut-svg-box">
            <svg viewBox="0 0 132 132" width="132" height="132">${arcs}</svg>
            <div class="donut-center">
              <div class="donut-center-lbl">Jami</div>
              <div class="donut-center-val tnum">${fmtUzs(grand)}</div>
            </div>
          </div>
          <div class="donut-legend">
            ${segments
              .map(
                (seg) => `
              <button class="legend-item" data-donut-filter="${seg.key}" type="button">
                <div style="font-size:11.5px;color:var(--text-2);font-weight:800;">
                  <span class="legend-dot" style="background:${seg.color};"></span>${seg.label} (${seg.cnt})
                </div>
                <div class="tnum" style="font-weight:900;font-size:13px;margin-top:3px;">${fmtUzs(seg.val)}</div>
              </button>
            `
              )
              .join('')}
          </div>
        </div>
      </div>
    `;
  }

  function defaultTrendIdx(pts, isHourly) {
    if (!pts.length) return null;
    if (isHourly) {
      for (let i = pts.length - 1; i >= 0; i--) {
        if ((pts[i].spent || 0) > 0 || (pts[i].cash_in || 0) > 0) return i;
      }
    }
    return pts.length - 1;
  }

  function buildTrendSvg(pts, activeIdx) {
    const W = 340;
    const H = 160;
    const topPad = 14;
    const bottomPad = 24;
    const hPad = 14;
    const cH = H - topPad - bottomPad;
    const cW = W - hPad * 2;

    let maxVal = 1;
    for (const p of pts) {
      maxVal = Math.max(maxVal, Number(p.spent || 0), Number(p.cash_in || 0));
    }

    const ptAt = (i, val) => {
      const x = pts.length <= 1 ? W / 2 : hPad + (cW * i) / (pts.length - 1);
      const ratio = Math.max(0, Math.min(1, val / maxVal));
      const y = topPad + cH * (1 - ratio);
      return { x, y };
    };

    const spentPts = pts.map((p, i) => ptAt(i, Number(p.spent || 0)));
    const inPts = pts.map((p, i) => ptAt(i, Number(p.cash_in || 0)));

    const smoothPath = (arr) => {
      if (!arr.length) return '';
      let d = `M ${arr[0].x.toFixed(1)} ${arr[0].y.toFixed(1)}`;
      if (arr.length === 1) return `${d} L ${(arr[0].x + 1).toFixed(1)} ${arr[0].y.toFixed(1)}`;
      for (let i = 0; i < arr.length - 1; i++) {
        const p0 = arr[i];
        const p1 = arr[i + 1];
        const midX = ((p0.x + p1.x) / 2).toFixed(1);
        d += ` C ${midX} ${p0.y.toFixed(1)}, ${midX} ${p1.y.toFixed(1)}, ${p1.x.toFixed(1)} ${p1.y.toFixed(1)}`;
      }
      return d;
    };

    const gridLines = [0, 1, 2, 3]
      .map((i) => {
        const y = (topPad + (cH / 3) * i).toFixed(1);
        return `<line x1="${hPad}" y1="${y}" x2="${W - hPad}" y2="${y}" stroke="var(--border)" stroke-width="1" />`;
      })
      .join('');

    const inPath = smoothPath(inPts);
    const spPath = smoothPath(spentPts);
    const areaPath =
      spentPts.length >= 2
        ? `${spPath} L ${spentPts[spentPts.length - 1].x.toFixed(1)} ${(topPad + cH).toFixed(1)} L ${spentPts[0].x.toFixed(1)} ${(topPad + cH).toFixed(1)} Z`
        : '';

    const step = Math.max(1, Math.ceil(pts.length / 5));
    const dots = spentPts
      .map((o, i) => {
        const isSel = i === activeIdx;
        let lbl = '';
        if (i % step === 0 || i === pts.length - 1) {
          const raw = String(pts[i].date || '');
          const shortLbl = raw.length >= 10 ? raw.slice(5, 10) : raw;
          const lx = Math.max(18, Math.min(W - 18, o.x));
          lbl = `<text x="${lx.toFixed(1)}" y="${H - 5}" text-anchor="middle" font-size="10" font-weight="${isSel ? '900' : '600'}" fill="var(--text-2)">${esc(shortLbl)}</text>`;
        }
        return `
          ${lbl}
          <circle data-dot-idx="${i}" cx="${o.x.toFixed(1)}" cy="${o.y.toFixed(1)}" r="${isSel ? 5.8 : 3.4}" fill="${isSel ? 'var(--brand)' : 'var(--card)'}" stroke="var(--brand)" stroke-width="${isSel ? 2.5 : 1.8}" />
        `;
      })
      .join('');

    return `
      <svg id="trend-svg" viewBox="0 0 ${W} ${H}" width="100%" height="160" preserveAspectRatio="none">
        <defs>
          <linearGradient id="trendGrad" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="#4f46e5" stop-opacity="0.30" />
            <stop offset="100%" stop-color="#4f46e5" stop-opacity="0.02" />
          </linearGradient>
        </defs>
        ${gridLines}
        ${inPts.length >= 2 ? `<path d="${inPath}" fill="none" stroke="rgba(5,150,105,0.65)" stroke-width="2" />` : ''}
        ${areaPath ? `<path d="${areaPath}" fill="url(#trendGrad)" />` : ''}
        <path d="${spPath}" fill="none" stroke="var(--brand)" stroke-width="3" stroke-linecap="round" />
        ${dots}
      </svg>
    `;
  }

  function renderTrendCard() {
    const pts = state.dailySeries || [];
    const isHourly = state.seriesGranularity === 'hourly' || (pts.length > 0 && String(pts[0].date || '').includes(':'));
    const activeIdx =
      state.selectedTrendIdx != null && state.selectedTrendIdx >= 0 && state.selectedTrendIdx < pts.length
        ? state.selectedTrendIdx
        : defaultTrendIdx(pts, isHourly);
    const selPt = activeIdx != null ? pts[activeIdx] : null;

    const presets = [
      { key: 'today', label: '📅 Bugun' },
      { key: 'yesterday', label: '🕒 Kecha' },
      { key: '7d', label: '7 kun' },
      { key: '14d', label: '14 kun' },
      { key: '30d', label: '30 kun' },
    ];

    const tooltipHtml = selPt
      ? `
        <div class="trend-tooltip" id="trend-tooltip">
          <div class="row" style="gap:6px;font-weight:900;font-size:12.5px;">
            <span>${isHourly ? '🕒' : '📅'}</span>
            <span>${esc(selPt.label || selPt.date)}</span>
          </div>
          <div style="text-align:right;">
            <div class="tnum" style="font-weight:900;font-size:12.5px;color:var(--brand);">Rasxod: ${fmtUzs(selPt.spent)} (${selPt.count || 0} ta)</div>
            ${Number(selPt.cash_in || 0) > 0 ? `<div class="tnum" style="font-weight:800;font-size:11.5px;color:var(--green);">Kirim: +${fmtUzs(selPt.cash_in, true)}</div>` : ''}
          </div>
        </div>
      `
      : '';

    return `
      <div class="card">
        <div class="chart-header">
          <div>
            <div class="chart-title">${isHourly ? 'Chiziqli Statistika (Soatlik)' : 'Chiziqli Statistika (Kunlik)'}</div>
            <div class="chart-sub">${esc(state.periodLabel)}</div>
          </div>
          <button class="btn btn-sm ${state.periodKey === 'custom' ? 'btn-primary' : 'btn-outline'}" id="btn-trend-custom-date" type="button">📆 Sana</button>
        </div>
        <div class="pill-scroll">
          ${presets
            .map(
              (pr) => `<button class="pill-btn${state.periodKey === pr.key ? ' active' : ''}" data-period-key="${pr.key}" type="button">${pr.label}</button>`
            )
            .join('')}
        </div>
        ${tooltipHtml}
        ${
          pts.length
            ? `<div class="trend-svg-wrap" id="trend-svg-wrap">${buildTrendSvg(pts, activeIdx)}</div>`
            : `<div style="padding:26px 8px;text-align:center;color:var(--text-2);">Ma'lumot topilmadi</div>`
        }
        <div class="chart-legend-row">
          <span><span class="legend-dot" style="background:var(--brand);"></span>${isHourly ? 'Soatlik nakladnoy rasxod' : 'Kunlik nakladnoy rasxod'}</span>
          <span><span class="legend-dot" style="background:var(--green);"></span>Olingan pul (Kirim)</span>
        </div>
      </div>
    `;
  }

  function renderTimelineCard(s, canEdit) {
    const events = [];
    for (const tx of s.cash_transactions || []) {
      const lbl =
        tx.source_type === 'main'
          ? 'Asosiy pul olindi (Kirim)'
          : tx.source_type === 'kassa_debt'
          ? 'Kassadan pul olindi'
          : 'Kassaga pul qaytarildi';
      events.push({
        kind: tx.source_type === 'kassa_repay' ? 'repay' : 'in',
        time: tx.time_hm,
        title: lbl,
        sub: tx.note || '',
        amount: tx.amount,
        tx,
      });
    }
    for (const n of s.nakladnoys || []) {
      events.push({
        kind: n.is_debt ? 'debt' : 'out',
        time: n.time_hm,
        title: n.supplier_name,
        sub: `${n.display_num}${n.is_debt ? ' • Qarzga' : n.payment_method === 'card' ? ' • Karta' : n.payment_method === 'transfer' ? " • O'tkazma" : ' • Naqd'}`,
        amount: n.amount,
        nak: n,
      });
    }
    events.sort((a, b) => String(b.time).localeCompare(String(a.time)));

    const filtered = events.filter((ev) => {
      if (state.timelineFilter === 'in') return ev.kind === 'in' || ev.kind === 'repay';
      if (state.timelineFilter === 'out') return ev.kind === 'out';
      if (state.timelineFilter === 'debt') return ev.kind === 'debt';
      return true;
    });

    const filters = [
      { key: 'all', lbl: 'Barchasi' },
      { key: 'in', lbl: 'Kirimlar' },
      { key: 'out', lbl: "To'lovlar" },
      { key: 'debt', lbl: 'Qarzga' },
    ];

    return `
      <div class="card">
        <div class="chart-header">
          <div>
            <div class="chart-title">Qachon nima olindi & Kimga berildi</div>
            <div class="chart-sub">${filtered.length} ta operatsiya (${esc(s.report_date)})</div>
          </div>
        </div>
        <div class="pill-scroll" style="margin-bottom:10px;">
          ${filters
            .map(
              (f) => `<button class="pill-btn${state.timelineFilter === f.key ? ' active' : ''}" data-tl-filter="${f.key}" type="button">${f.lbl}</button>`
            )
            .join('')}
        </div>
        <div style="display:flex;flex-direction:column;gap:8px;">
          ${
            filtered.length
              ? filtered
                  .slice(0, 25)
                  .map((ev) => {
                    const color =
                      ev.kind === 'in'
                        ? 'var(--green)'
                        : ev.kind === 'repay'
                        ? 'var(--blue)'
                        : ev.kind === 'debt'
                        ? 'var(--amber)'
                        : 'var(--brand)';
                    const sign = ev.kind === 'in' ? '+' : ev.kind === 'repay' ? '-' : '';
                    const ico = ev.kind === 'in' ? '➕' : ev.kind === 'repay' ? '↩️' : ev.kind === 'debt' ? '📌' : '🧾';
                    return `
                      <div class="row" style="padding:9px 10px;border-radius:12px;background:var(--surface-alt);border:1px solid var(--border);${ev.nak ? 'cursor:pointer;' : ''}" ${ev.nak ? `data-nak-id="${ev.nak.id}"` : ''}>
                        <span style="font-size:16px;">${ico}</span>
                        <div style="flex:1;min-width:0;">
                          <div style="font-weight:800;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${esc(ev.title)}</div>
                          <div style="font-size:11px;color:var(--text-2);">${esc(ev.time)}${ev.sub ? ` • ${esc(ev.sub)}` : ''}</div>
                        </div>
                        <div class="tnum" style="font-weight:900;font-size:13.5px;color:${color};">${sign}${fmtUzs(ev.amount)}</div>
                        ${
                          ev.tx && canEdit
                            ? `<button class="icon-btn" style="width:28px;height:28px;font-size:12px;" data-del-tx="${ev.tx.id}" type="button" title="O'chirish">🗑</button>`
                            : ''
                        }
                      </div>
                    `;
                  })
                  .join('')
              : `<div style="text-align:center;color:var(--text-2);padding:16px 0;">Harakatlar yo'q</div>`
          }
        </div>
      </div>
    `;
  }

  function renderDashboardTab() {
    const s = state.viewedSummary || state.summary;
    const isPast = Boolean(state.viewedSummary && state.summary && state.viewedSummary.session_id !== state.summary.session_id);
    const canEdit = !isPast && s.session_status === 'open';

    const hero = `
      <div class="hero-card">
        <div class="hero-top">
          <div class="hero-lbl">Qo'lda qolishi kerak</div>
          <div class="hero-pill">${esc(s.report_date)} • #${s.session_id}</div>
        </div>
        <div class="hero-val tnum">${fmtUzs(s.expected_cash, true)}</div>
        <div class="hero-metrics">
          <div>
            <div class="hm-lbl">Boshlanishi</div>
            <div class="hm-val tnum">${fmtUzs(s.opening_balance)}</div>
          </div>
          <div>
            <div class="hm-lbl">Jami kirim</div>
            <div class="hm-val tnum">${fmtUzs(s.total_available_inflow)}</div>
          </div>
          <div>
            <div class="hm-lbl">Naqd rasxod</div>
            <div class="hm-val tnum">${fmtUzs(s.total_nakladnoy_spent)}</div>
          </div>
        </div>
        ${
          canEdit
            ? `<div class="hero-actions">
                 <button class="hero-btn" id="btn-cash-main" type="button">+ Pul oldim</button>
                 <button class="hero-btn" id="btn-cash-kdebt" type="button">🏦 Kassadan</button>
                 <button class="hero-btn" id="btn-cash-krepay" type="button">↩️ Qaytarish</button>
               </div>`
            : ''
        }
      </div>
    `;

    const quickBtns = `
      <div class="grid-2">
        <button class="btn btn-outline" id="btn-open-sverka" type="button">📊 Jonli Sverka</button>
        <button class="btn btn-outline" id="btn-open-history" type="button">📜 O'tgan smenalar</button>
      </div>
    `;

    return [
      renderSessionSwitcherBar(s, isPast),
      hero,
      quickBtns,
      renderDonutCard(s),
      renderTrendCard(),
      renderTimelineCard(s, canEdit),
    ].join('');
  }

  function renderNakladnoylarTab() {
    const s = state.viewedSummary || state.summary;
    const isPast = Boolean(state.viewedSummary && state.summary && state.viewedSummary.session_id !== state.summary.session_id);
    const naks = s.nakladnoys || [];

    const cashCnt = naks.filter((n) => !n.is_debt && n.payment_method === 'cash').length;
    const cardCnt = naks.filter((n) => !n.is_debt && n.payment_method === 'card').length;
    const trCnt = naks.filter((n) => !n.is_debt && n.payment_method === 'transfer').length;
    const debtCnt = naks.filter((n) => n.is_debt).length;

    const filtered = naks.filter((n) => {
      if (state.filterMode === 'cash' && (n.is_debt || n.payment_method !== 'cash')) return false;
      if (state.filterMode === 'card' && (n.is_debt || n.payment_method !== 'card')) return false;
      if (state.filterMode === 'transfer' && (n.is_debt || n.payment_method !== 'transfer')) return false;
      if (state.filterMode === 'debt' && !n.is_debt) return false;
      if (state.searchQuery) {
        const q = state.searchQuery.toLowerCase();
        return (
          n.supplier_name.toLowerCase().includes(q) ||
          n.display_num.toLowerCase().includes(q) ||
          String(Math.round(n.amount)).includes(q)
        );
      }
      return true;
    });

    if (state.sortMode === 'amount_desc') filtered.sort((a, b) => b.amount - a.amount);
    else if (state.sortMode === 'supplier_az') filtered.sort((a, b) => a.supplier_name.localeCompare(b.supplier_name));
    else filtered.sort((a, b) => b.id - a.id);

    const filteredSum = filtered.reduce((acc, x) => acc + Number(x.amount || 0), 0);

    const miniCards = [
      { key: 'cash', lbl: '💵 Naqd', val: s.total_nakladnoy_spent, cnt: cashCnt, border: '#059669' },
      { key: 'card', lbl: '💳 Karta', val: s.total_card_spent, cnt: cardCnt, border: '#2563EB' },
      { key: 'transfer', lbl: "🏦 O'tkazma", val: s.total_transfer_spent, cnt: trCnt, border: '#9333EA' },
      { key: 'debt', lbl: '📌 Qarzga', val: s.total_debt_nakladnoy, cnt: debtCnt, border: '#D97706' },
    ];

    const filterOptions = [
      { value: 'all', label: 'Barchasi', subtitle: "Hamma to'lov turlari", icon: '🧾', badge: `${naks.length}` },
      { value: 'cash', label: 'Naqd', subtitle: "Qo'ldagi naqd puldan", icon: '💵', badge: `${cashCnt}` },
      { value: 'card', label: 'Karta', subtitle: 'Plastik karta orqali', icon: '💳', badge: `${cardCnt}` },
      { value: 'transfer', label: "O'tkazma", subtitle: 'Perechesleniya orqali', icon: '🏦', badge: `${trCnt}` },
      { value: 'debt', label: 'Qarzga', subtitle: "To'lanmagan qarzlar", icon: '📌', badge: `${debtCnt}` },
    ];
    const sortOptions = [
      { value: 'newest', label: 'Yangilari tepada', subtitle: 'Oxirgi kiritilganlar', icon: '🕒' },
      { value: 'amount_desc', label: 'Summasi katta', subtitle: 'Eng yirikdan kichigiga', icon: '⬇️' },
      { value: 'supplier_az', label: 'Postavshik (A-Z)', subtitle: 'Alifbo tartibida', icon: '🔤' },
    ];

    window.__nakFilterOptions = filterOptions;
    window.__nakSortOptions = sortOptions;

    return `
      ${renderSessionSwitcherBar(s, isPast)}
      <div class="mini-dash-grid">
        ${miniCards
          .map((c) => {
            const act = state.filterMode === c.key;
            return `
              <button class="mini-card${act ? ' active' : ''}" data-mini-filter="${c.key}" style="${act ? `border-color:${c.border};` : ''}" type="button">
                <div class="mini-card-head">
                  <span>${c.lbl}</span>
                  ${act ? '<span style="font-size:10px;font-weight:900;">✓</span>' : ''}
                </div>
                <div class="mini-card-val tnum">${fmtUzs(c.val, true)}</div>
                <div class="mini-card-cnt">${c.cnt} ta nakladnoy</div>
              </button>
            `;
          })
          .join('')}
      </div>
      <div class="row-between" style="padding:2px 2px;">
        <div style="font-size:17px;font-weight:900;">Nakladnoylar (${filtered.length} ta)</div>
        <div class="tnum" style="font-size:15px;font-weight:900;color:var(--brand);">${fmtUzs(filteredSum, true)}</div>
      </div>
      <div class="grid-2">
        ${renderCustomDropdownTrigger({ id: 'dd-nak-filter', labelText: "To'lov turi", value: state.filterMode, options: filterOptions })}
        ${renderCustomDropdownTrigger({ id: 'dd-nak-sort', labelText: 'Saralash', value: state.sortMode, options: sortOptions })}
      </div>
      <div class="row">
        <input class="input" id="input-nak-search" value="${esc(state.searchQuery)}" placeholder="Bugungi nakladnoylardan qidirish..." style="flex:1;" />
        <button class="btn btn-outline" id="btn-global-search" type="button" title="Arxiv qidiruv">🌐</button>
      </div>
      <div style="display:flex;flex-direction:column;gap:9px;">
        ${
          filtered.length
            ? filtered.map(renderNakCard).join('')
            : `<div class="card" style="text-align:center;color:var(--text-2);padding:26px;">Nakladnoy topilmadi</div>`
        }
      </div>
    `;
  }

  function renderDebtsTab() {
    const subTabs = `
      <div class="grid-2">
        <button class="btn ${state.debtSubTab === 'nakladnoy' ? 'btn-primary' : 'btn-outline'}" data-debt-sub="nakladnoy" type="button">
          📌 Nakladnoy qarz (${state.debts.length})
        </button>
        <button class="btn ${state.debtSubTab === 'nasiya' ? 'btn-primary' : 'btn-outline'}" data-debt-sub="nasiya" type="button">
          📒 Nasiya daftari
        </button>
      </div>
    `;

    if (state.debtSubTab === 'nasiya') {
      const nas = state.nasiya;
      if (!nas) {
        apiFetch('/nasiya').then((d) => {
          state.nasiya = d;
          render();
        });
        return `${subTabs}<div class="card" style="text-align:center;">Yuklanmoqda...</div>`;
      }
      const balances = nas.balances || [];
      const entries = nas.entries || [];
      return `
        ${subTabs}
        <div class="card" style="display:flex;align-items:center;justify-content:space-between;gap:10px;">
          <div>
            <div style="font-size:12px;color:var(--text-2);font-weight:800;">Umumiy Nasiya Qoldiq</div>
            <div class="tnum" style="font-size:21px;font-weight:900;color:var(--brand);">${fmtUzs(nas.total_balance, true)}</div>
          </div>
          <button class="btn btn-primary btn-sm" id="btn-add-nasiya" type="button">+ Yozuv qo'shish</button>
        </div>
        ${
          balances.length
            ? `<div class="card">
                 <div style="font-weight:900;margin-bottom:8px;">Postavshiklar kesimida</div>
                 <div style="display:flex;flex-direction:column;gap:6px;">
                   ${balances
                     .map(
                       (b) => `
                     <div class="row-between" style="padding:7px 9px;border-radius:10px;background:var(--surface-alt);">
                       <div>
                         <div style="font-weight:800;">${esc(b.supplier)}</div>
                         <div style="font-size:11px;color:var(--text-2);">Qarz: ${fmtUzs(b.debt)} • To'landi: ${fmtUzs(b.paid)}</div>
                       </div>
                       <div class="tnum" style="font-weight:900;color:${b.balance > 0 ? 'var(--amber)' : 'var(--green)'};">${fmtUzs(b.balance)}</div>
                     </div>`
                     )
                     .join('')}
                 </div>
               </div>`
            : ''
        }
        <div class="card">
          <div style="font-weight:900;margin-bottom:8px;">Oxirgi harakatlar (${entries.length} ta)</div>
          <div style="display:flex;flex-direction:column;gap:6px;">
            ${
              entries.length
                ? entries
                    .map(
                      (e) => `
                  <div class="row" style="padding:7px 9px;border-radius:10px;background:var(--surface-alt);">
                    <span>${e.entry_type === 'debt' ? '📌' : '✅'}</span>
                    <div style="flex:1;min-width:0;">
                      <div style="font-weight:800;">${esc(e.supplier_name)}</div>
                      <div style="font-size:11px;color:var(--text-2);">${esc(e.created_at)}${e.note ? ` • ${esc(e.note)}` : ''}</div>
                    </div>
                    <div class="tnum" style="font-weight:900;">${fmtUzs(e.amount)}</div>
                    <button class="icon-btn" style="width:28px;height:28px;font-size:12px;" data-del-nasiya="${e.id}" type="button">🗑</button>
                  </div>`
                    )
                    .join('')
                : `<div style="color:var(--text-2);text-align:center;">Yozuvlar yo'q</div>`
            }
          </div>
        </div>
      `;
    }

    const bySup = {};
    for (const d of state.debts) {
      if (!bySup[d.supplier_name]) bySup[d.supplier_name] = { cnt: 0, sum: 0 };
      bySup[d.supplier_name].cnt += 1;
      bySup[d.supplier_name].sum += Number(d.amount || 0);
    }
    const supNames = Object.keys(bySup).sort();
    const activeSup = state.debtSupplierFilter === 'all' || supNames.includes(state.debtSupplierFilter) ? state.debtSupplierFilter : 'all';
    const visible = activeSup === 'all' ? state.debts : state.debts.filter((d) => d.supplier_name === activeSup);
    const totalDebt = visible.reduce((a, b) => a + Number(b.amount || 0), 0);
    const allSum = state.debts.reduce((a, b) => a + Number(b.amount || 0), 0);

    const supOpts = [
      { value: 'all', label: 'Barcha postavshiklar', subtitle: fmtUzs(allSum, true), icon: '👥', badge: `${state.debts.length} ta` },
      ...supNames.map((n) => ({
        value: n,
        label: n,
        subtitle: fmtUzs(bySup[n].sum, true),
        icon: '🏪',
        badge: `${bySup[n].cnt} ta`,
      })),
    ];
    window.__debtSupOptions = supOpts;

    return `
      ${subTabs}
      <div class="alert-box alert-amber" style="margin-top:0;">
        <div style="font-weight:800;">To'lanmagan nakladnoy qarzlari (${visible.length} ta)</div>
        <div class="tnum" style="font-size:22px;font-weight:900;margin-top:3px;">${fmtUzs(totalDebt, true)}</div>
      </div>
      ${
        supNames.length > 1
          ? renderCustomDropdownTrigger({ id: 'dd-debt-sup', labelText: "Postavshik bo'yicha saralash", value: activeSup, options: supOpts })
          : ''
      }
      <div style="display:flex;flex-direction:column;gap:9px;">
        ${
          visible.length
            ? visible
                .map(
                  (d) => `
              ${renderNakCard(d)}
              <button class="btn btn-soft btn-sm btn-block" style="margin-top:-4px;margin-bottom:4px;" data-quick-pay="${d.id}" type="button">
                ✅ Qarzni to'lash (Naqd / Karta / O'tkazma)
              </button>
            `
                )
                .join('')
            : `<div class="card" style="text-align:center;color:var(--text-2);padding:28px;">✅ To'lanmagan qarzlar yo'q</div>`
        }
      </div>
    `;
  }

  function renderReportsTab() {
    const s = state.summary;
    const reportType = state.selectedReportType || 'today';
    const reportOptions = [
      { value: 'today', label: 'Bugungi kunlik hisobot', subtitle: `Sana: ${s.report_date}`, icon: '📊' },
      { value: 'week', label: 'Oxirgi 7 kunlik hisobot', subtitle: 'Haftalik kirim-chiqim jadvali', icon: '📅' },
      { value: 'month', label: 'Joriy oy hisoboti', subtitle: 'Oy boshidan bugungacha', icon: '🗓' },
      { value: 'custom', label: "Ixtiyoriy sana oralig'i...", subtitle: 'Sanadan sanagacha tanlash', icon: '📆' },
      { value: 'sverka', label: 'Postavshiklar Sverkasi', subtitle: "Oylik to'lovlar taqqoslamasi", icon: '🏢' },
    ];
    window.__reportOptions = reportOptions;

    return `
      <div class="card">
        <div style="font-size:16px;font-weight:900;margin-bottom:10px;">🏁 Kunni yakunlash (Smena yopish)</div>
        <div class="row-between" style="padding:11px;border-radius:12px;background:rgba(79,70,229,0.1);margin-bottom:10px;">
          <span style="font-weight:700;">Qo'lda bo'lishi kerak:</span>
          <span class="tnum" style="font-weight:900;font-size:15px;">${fmtUzs(s.expected_cash, true)}</span>
        </div>
        <div class="field">
          <label>Qo'lda sanalgan haqiqiy pul (so'm)</label>
          <div class="row">
            <input class="input tnum" id="input-counted-cash" inputmode="numeric" placeholder="${fmtUzs(s.expected_cash)}" style="font-size:17px;" />
            <button class="btn btn-soft btn-sm" id="btn-fill-expected" type="button">Teng</button>
          </div>
        </div>
        <div id="close-day-diff"></div>
        <button class="btn btn-primary btn-block" id="btn-close-day" type="button" style="margin-top:12px;">
          Kunni yakunlash va yangi kun ochish
        </button>
      </div>

      <div class="card">
        <div style="font-size:16px;font-weight:900;margin-bottom:8px;">📥 Excel Hisobot va Sverka yuklash</div>
        ${renderCustomDropdownTrigger({ id: 'dd-excel-type', labelText: 'Hisobot turini tanlang', value: reportType, options: reportOptions })}
        <button class="btn btn-green btn-block" id="btn-download-excel" type="button" style="margin-top:10px;">
          Excel yuklab olish
        </button>
        <button class="btn btn-outline btn-block" id="btn-sverka-sheet" type="button" style="margin-top:8px;">
          📊 Jonli Sverka (oylik jadval)
        </button>
      </div>

      <div class="card" style="display:flex;flex-direction:column;gap:8px;">
        <div style="font-size:16px;font-weight:900;">👑 Arxiv, Prixod va Sozlamalar</div>
        <button class="btn btn-soft btn-block" id="btn-history-sheet" type="button">📜 O'tgan smenalar tarixi</button>
        <button class="btn btn-outline btn-block" id="btn-prixod-sheet" type="button">👑 Prixod (ITOG) hisobotlari</button>
        <button class="btn btn-outline btn-block" id="btn-settings-sheet" type="button">🏢 Postavshiklar va Yaxlitlash</button>
      </div>
    `;
  }

  function render() {
    if (state.error && !state.summary) {
      $nav.classList.add('hidden');
      $fab.classList.add('hidden');
      $topbarSub.textContent = 'Kirish cheklangan';
      $root.innerHTML = `
        <div class="card" style="text-align:center;padding:28px 18px;">
          <div style="font-size:38px;margin-bottom:8px;">🔒</div>
          <div style="font-size:17px;font-weight:900;">Kirish rad etildi</div>
          <div style="margin-top:8px;color:var(--text-2);font-size:13.5px;">${esc(state.error.message || state.error)}</div>
        </div>
      `;
      return;
    }

    if (state.loading && !state.summary) {
      $root.innerHTML = `
        <div class="card skeleton-card">
          <div class="skeleton-line w-60"></div>
          <div class="skeleton-line w-40"></div>
          <div class="skeleton-line w-85"></div>
        </div>
      `;
      return;
    }

    const s = state.summary;
    const viewed = state.viewedSummary || s;
    const isPast = Boolean(state.viewedSummary && state.viewedSummary.session_id !== s.session_id);
    $topbarSub.textContent = `${viewed.report_date} • Smena #${viewed.session_id}`;

    $nav.classList.remove('hidden');
    if (state.debts.length > 0) {
      $debtBadge.textContent = String(state.debts.length);
      $debtBadge.classList.remove('hidden');
    } else {
      $debtBadge.classList.add('hidden');
    }

    const showFab = (state.tab === 'dashboard' || state.tab === 'nakladnoys') && !isPast && s.session_status === 'open';
    $fab.classList.toggle('hidden', !showFab);

    document.querySelectorAll('#bottom-nav .nav-btn').forEach((btn) => {
      btn.classList.toggle('active', btn.getAttribute('data-tab') === state.tab);
    });

    if (state.tab === 'dashboard') $root.innerHTML = renderDashboardTab();
    else if (state.tab === 'nakladnoys') $root.innerHTML = renderNakladnoylarTab();
    else if (state.tab === 'debts') $root.innerHTML = renderDebtsTab();
    else $root.innerHTML = renderReportsTab();

    bindDynamicEvents();
  }

  function updateTrendTooltipDom(idx) {
    const pts = state.dailySeries || [];
    if (idx == null || idx < 0 || idx >= pts.length) return;
    state.selectedTrendIdx = idx;
    const svgWrap = document.getElementById('trend-svg-wrap');
    if (svgWrap) svgWrap.innerHTML = buildTrendSvg(pts, idx);
    const tip = document.getElementById('trend-tooltip');
    const pt = pts[idx];
    const isHourly = state.seriesGranularity === 'hourly' || String(pt.date || '').includes(':');
    if (tip) {
      tip.innerHTML = `
        <div class="row" style="gap:6px;font-weight:900;font-size:12.5px;">
          <span>${isHourly ? '🕒' : '📅'}</span>
          <span>${esc(pt.label || pt.date)}</span>
        </div>
        <div style="text-align:right;">
          <div class="tnum" style="font-weight:900;font-size:12.5px;color:var(--brand);">Rasxod: ${fmtUzs(pt.spent)} (${pt.count || 0} ta)</div>
          ${Number(pt.cash_in || 0) > 0 ? `<div class="tnum" style="font-weight:800;font-size:11.5px;color:var(--green);">Kirim: +${fmtUzs(pt.cash_in, true)}</div>` : ''}
        </div>
      `;
    }
  }

  function bindDynamicEvents() {
    // Nakladnoy cards open detail
    $root.querySelectorAll('[data-nak-id]').forEach((el) => {
      el.addEventListener('click', () => {
        const id = Number(el.getAttribute('data-nak-id'));
        const active = state.viewedSummary || state.summary;
        const item = (active.nakladnoys || []).find((n) => n.id === id) || state.debts.find((n) => n.id === id);
        if (item) openNakladnoyDetailSheet(item);
      });
    });

    // Session Switcher
    const ddSess = document.getElementById('dd-session-switcher');
    if (ddSess) {
      const sessions = state.historySessions || [];
      const curId = (state.viewedSummary || state.summary).session_id;
      ddSess.addEventListener('click', () => {
        const opts = sessions.map((s) => {
          const isOpen = state.summary && s.id === state.summary.session_id;
          return {
            value: String(s.id),
            label: `${s.report_date} • Smena #${s.id}`,
            subtitle: isOpen ? 'Bugungi faol ochiq smena' : `Kutilgan naqd: ${fmtUzs(s.expected_cash, true)}`,
            icon: isOpen ? '🟢' : '📅',
            badge: isOpen ? 'Faol' : `#${s.id}`,
          };
        });
        openCustomDropdown({
          title: 'Smena / sanani tanlang',
          value: String(curId),
          options: opts,
          searchable: opts.length >= 8,
          onSelect: async (val) => {
            const sid = Number(val);
            if (!state.summary || sid === state.summary.session_id) {
              state.viewedSummary = null;
              render();
              return;
            }
            try {
              state.viewedSummary = await apiFetch(`/history/sessions/${sid}`);
              render();
            } catch (e) {
              showToast(e.message, true);
            }
          },
        });
      });
    }

    const prevBtn = document.getElementById('btn-prev-sess');
    const nextBtn = document.getElementById('btn-next-sess');
    const backTodayBtn = document.getElementById('btn-back-today');
    if (prevBtn) {
      prevBtn.addEventListener('click', async () => {
        const curId = (state.viewedSummary || state.summary).session_id;
        const idx = state.historySessions.findIndex((s) => s.id === curId);
        if (idx >= 0 && idx + 1 < state.historySessions.length) {
          state.viewedSummary = await apiFetch(`/history/sessions/${state.historySessions[idx + 1].id}`);
          render();
        }
      });
    }
    if (nextBtn) {
      nextBtn.addEventListener('click', async () => {
        const curId = (state.viewedSummary || state.summary).session_id;
        const idx = state.historySessions.findIndex((s) => s.id === curId);
        if (idx > 0) {
          const targetId = state.historySessions[idx - 1].id;
          state.viewedSummary = targetId === state.summary.session_id ? null : await apiFetch(`/history/sessions/${targetId}`);
          render();
        }
      });
    }
    if (backTodayBtn) {
      backTodayBtn.addEventListener('click', () => {
        state.viewedSummary = null;
        render();
      });
    }

    // Donut filter
    $root.querySelectorAll('[data-donut-filter]').forEach((b) => {
      b.addEventListener('click', () => {
        state.filterMode = b.getAttribute('data-donut-filter');
        state.tab = 'nakladnoys';
        render();
      });
    });

    // Trend presets & custom date
    $root.querySelectorAll('[data-period-key]').forEach((b) => {
      b.addEventListener('click', async () => {
        const k = b.getAttribute('data-period-key');
        state.periodKey = k;
        state.selectedTrendIdx = null;
        state.periodLabel =
          k === 'today'
            ? 'Bugun • Soatlik dinamika'
            : k === 'yesterday'
            ? 'Kecha • Soatlik dinamika'
            : k === '14d'
            ? 'Oxirgi 14 kunlik dinamika'
            : k === '30d'
            ? 'Oxirgi 30 kunlik dinamika'
            : 'Oxirgi 7 kunlik dinamika';
        await fetchTrendStats();
        render();
      });
    });

    const customDateBtn = document.getElementById('btn-trend-custom-date');
    if (customDateBtn) customDateBtn.addEventListener('click', openTrendDateSheet);

    const svgWrap = document.getElementById('trend-svg-wrap');
    if (svgWrap && state.dailySeries.length) {
      const handlePointer = (clientX) => {
        const rect = svgWrap.getBoundingClientRect();
        const pts = state.dailySeries;
        if (pts.length <= 1) return updateTrendTooltipDom(0);
        const hPad = (14 / 340) * rect.width;
        const chartW = Math.max(1, rect.width - hPad * 2);
        const rel = Math.max(0, Math.min(1, (clientX - rect.left - hPad) / chartW));
        const idx = Math.round(rel * (pts.length - 1));
        updateTrendTooltipDom(idx);
      };
      svgWrap.addEventListener('pointerdown', (e) => handlePointer(e.clientX));
      svgWrap.addEventListener('touchmove', (e) => {
        if (e.touches && e.touches[0]) handlePointer(e.touches[0].clientX);
      }, { passive: true });
    }

    // Timeline filter & delete cash
    $root.querySelectorAll('[data-tl-filter]').forEach((b) => {
      b.addEventListener('click', () => {
        state.timelineFilter = b.getAttribute('data-tl-filter');
        render();
      });
    });
    $root.querySelectorAll('[data-del-tx]').forEach((b) => {
      b.addEventListener('click', async (e) => {
        e.stopPropagation();
        const txId = Number(b.getAttribute('data-del-tx'));
        if (!confirm("Kassa amalini o'chirasizmi?")) return;
        await apiFetch(`/cash/${txId}`, { method: 'DELETE' });
        showToast("Kassa amali o'chirildi");
        await refreshAll(true);
      });
    });

    // Hero cash actions & dashboard quick buttons
    const bindId = (id, fn) => {
      const el = document.getElementById(id);
      if (el) el.addEventListener('click', fn);
    };
    bindId('btn-cash-main', () => openCashSheet('main', '➕ Asosiy balansga pul oldim'));
    bindId('btn-cash-kdebt', () => openCashSheet('kassa_debt', '🏦 Kassadan pul oldim'));
    bindId('btn-cash-krepay', () => openCashSheet('kassa_repay', '↩️ Kassaga qarz qaytardim'));
    bindId('btn-open-sverka', openSverkaSheet);
    bindId('btn-open-history', openHistorySheet);

    // Nakladnoylar tab bindings
    $root.querySelectorAll('[data-mini-filter]').forEach((b) => {
      b.addEventListener('click', () => {
        const k = b.getAttribute('data-mini-filter');
        state.filterMode = state.filterMode === k ? 'all' : k;
        render();
      });
    });
    bindId('dd-nak-filter', () =>
      openCustomDropdown({
        title: "To'lov turi bo'yicha filtrlash",
        value: state.filterMode,
        options: window.__nakFilterOptions || [],
        onSelect: (v) => {
          state.filterMode = v;
          render();
        },
      })
    );
    bindId('dd-nak-sort', () =>
      openCustomDropdown({
        title: 'Nakladnoylarni saralash',
        value: state.sortMode,
        options: window.__nakSortOptions || [],
        onSelect: (v) => {
          state.sortMode = v;
          render();
        },
      })
    );
    const searchEl = document.getElementById('input-nak-search');
    if (searchEl) {
      searchEl.addEventListener('input', () => {
        const pos = searchEl.selectionStart;
        state.searchQuery = searchEl.value.trim();
        render();
        const fresh = document.getElementById('input-nak-search');
        if (fresh) {
          fresh.focus();
          if (pos != null) fresh.setSelectionRange(pos, pos);
        }
      });
    }
    bindId('btn-global-search', openGlobalSearchSheet);

    // Debts tab bindings
    $root.querySelectorAll('[data-debt-sub]').forEach((b) => {
      b.addEventListener('click', () => {
        state.debtSubTab = b.getAttribute('data-debt-sub');
        render();
      });
    });
    bindId('dd-debt-sup', () =>
      openCustomDropdown({
        title: 'Qarz postavshikni tanlang',
        value: state.debtSupplierFilter,
        options: window.__debtSupOptions || [],
        searchable: true,
        onSelect: (v) => {
          state.debtSupplierFilter = v;
          render();
        },
      })
    );
    $root.querySelectorAll('[data-quick-pay]').forEach((b) => {
      b.addEventListener('click', () => {
        const id = Number(b.getAttribute('data-quick-pay'));
        const item = state.debts.find((d) => d.id === id);
        if (item) openPayDebtSheet(item);
      });
    });
    bindId('btn-add-nasiya', openAddNasiyaSheet);
    $root.querySelectorAll('[data-del-nasiya]').forEach((b) => {
      b.addEventListener('click', async () => {
        const id = Number(b.getAttribute('data-del-nasiya'));
        await apiFetch(`/nasiya/${id}`, { method: 'DELETE' });
        state.nasiya = await apiFetch('/nasiya');
        showToast("Nasiya yozuvi o'chirildi");
        render();
      });
    });

    // Reports / Smena tab bindings
    const countedEl = document.getElementById('input-counted-cash');
    if (countedEl) {
      bindUzsFormatter(countedEl);
      const updateDiff = () => {
        const val = parseUzsInput(countedEl.value);
        const box = document.getElementById('close-day-diff');
        if (!box) return;
        if (val == null) {
          box.innerHTML = '';
          return;
        }
        const diff = val - Number(state.summary.expected_cash || 0);
        const cls = diff === 0 ? 'alert-green' : diff > 0 ? 'alert-violet' : 'alert-red';
        const txt =
          diff === 0
            ? "✅ Farq: 0 so'm (Kassa 100% to'g'ri!)"
            : diff > 0
            ? `➕ Ortiqcha: +${fmtUzs(diff, true)}`
            : `⚠️ Kamomad: ${fmtUzs(diff, true)}`;
        box.innerHTML = `<div class="alert-box ${cls}"><b>${txt}</b></div>`;
      };
      countedEl.addEventListener('input', updateDiff);
      bindId('btn-fill-expected', () => {
        countedEl.value = formatDigitsInput(String(Math.round(state.summary.expected_cash || 0)));
        updateDiff();
      });
      bindId('btn-close-day', async () => {
        const val = parseUzsInput(countedEl.value);
        if (val == null) return showToast("Sanalgan haqiqiy pulni kiriting", true);
        const res = await apiFetch('/day/close', { method: 'POST', json: { actual_counted_cash: val } });
        haptic('success');
        showToast(`🏁 Kun yakunlandi! Qoldiq: ${fmtUzs(res.next_opening_balance, true)}`);
        state.viewedSummary = null;
        await refreshAll(true);
      });
    }
    bindId('dd-excel-type', () =>
      openCustomDropdown({
        title: 'Excel hisobot turini tanlang',
        value: state.selectedReportType || 'today',
        options: window.__reportOptions || [],
        onSelect: (v) => {
          state.selectedReportType = v;
          render();
        },
      })
    );
    bindId('btn-download-excel', async () => {
      const t = state.selectedReportType || 'today';
      const today = new Date().toISOString().slice(0, 10);
      if (t === 'today') downloadExcel('/export/session', `Hisobot_${state.summary.report_date}.xlsx`);
      else if (t === 'week') {
        const d1 = new Date(Date.now() - 6 * 86400000).toISOString().slice(0, 10);
        downloadExcel(`/export/range?date_from=${d1}&date_to=${today}`, `Hisobot_7kun.xlsx`);
      } else if (t === 'month') {
        const m1 = `${today.slice(0, 7)}-01`;
        downloadExcel(`/export/range?date_from=${m1}&date_to=${today}`, `Hisobot_Oy.xlsx`);
      } else if (t === 'sverka') {
        downloadExcel('/export/sverka', `Sverka_${today.slice(0, 7)}.xlsx`);
      } else {
        openExcelCustomDateSheet();
      }
    });
    bindId('btn-sverka-sheet', openSverkaSheet);
    bindId('btn-history-sheet', openHistorySheet);
    bindId('btn-prixod-sheet', openPrixodSheet);
    bindId('btn-settings-sheet', openSettingsSheet);
  }

  // Interactive Modal Sheets
  function openTrendDateSheet() {
    const today = new Date().toISOString().slice(0, 10);
    const html = `
      <div class="field">
        <label>Boshlanish sanasi</label>
        <input type="date" class="input" id="tr-from" value="${esc(state.customDateFrom || today)}" />
      </div>
      <div class="field">
        <label>Tugash sanasi (1 kunlik soatlik uchun bir xil sana tanlang)</label>
        <input type="date" class="input" id="tr-to" value="${esc(state.customDateTo || today)}" />
      </div>
      <button class="btn btn-primary btn-block" id="tr-apply" type="button">Ko'rsatish</button>
    `;
    openSheet('Chiziqli statistika sanasi', html, (body) => {
      body.querySelector('#tr-apply').addEventListener('click', async () => {
        const d1 = body.querySelector('#tr-from').value;
        const d2 = body.querySelector('#tr-to').value || d1;
        if (!d1) return;
        const [from, to] = d1 <= d2 ? [d1, d2] : [d2, d1];
        state.customDateFrom = from;
        state.customDateTo = to;
        state.periodKey = 'custom';
        state.selectedTrendIdx = null;
        state.periodLabel = from === to ? `${from} • Soatlik dinamika` : `${from} — ${to} dinamikasi`;
        closeSheet();
        await fetchTrendStats();
        render();
      });
    });
  }

  function openExcelCustomDateSheet() {
    const today = new Date().toISOString().slice(0, 10);
    const html = `
      <div class="field"><label>Dan:</label><input type="date" class="input" id="ex-from" value="${today}" /></div>
      <div class="field"><label>Gacha:</label><input type="date" class="input" id="ex-to" value="${today}" /></div>
      <button class="btn btn-green btn-block" id="ex-go" type="button">📥 Excel yuklab olish</button>
    `;
    openSheet("Hisobot sanasi oralig'i", html, (body) => {
      body.querySelector('#ex-go').addEventListener('click', () => {
        const d1 = body.querySelector('#ex-from').value;
        const d2 = body.querySelector('#ex-to').value || d1;
        if (!d1) return;
        const [from, to] = d1 <= d2 ? [d1, d2] : [d2, d1];
        closeSheet();
        downloadExcel(`/export/range?date_from=${from}&date_to=${to}`, `Hisobot_${from}_${to}.xlsx`);
      });
    });
  }

  function openCashSheet(sourceType, title) {
    const html = `
      <div class="field"><label>Summa (so'm)</label><input class="input tnum" id="cash-amt" inputmode="numeric" placeholder="21 000 000" /></div>
      <div class="field"><label>Izoh (ixtiyoriy)</label><input class="input" id="cash-note" placeholder="Kirim manbai yoki izoh" /></div>
      <button class="btn btn-primary btn-block" id="cash-save" type="button">Saqlash</button>
    `;
    openSheet(title, html, (body) => {
      const amtEl = body.querySelector('#cash-amt');
      bindUzsFormatter(amtEl);
      amtEl.focus();
      body.querySelector('#cash-save').addEventListener('click', async () => {
        const amt = parseUzsInput(amtEl.value);
        if (!amt) return showToast('Summani kiriting', true);
        await apiFetch('/cash', {
          method: 'POST',
          json: { amount: amt, source_type: sourceType, note: body.querySelector('#cash-note').value.trim() },
        });
        haptic('success');
        closeSheet();
        showToast(`✅ ${fmtUzs(amt, true)} qo'shildi`);
        await refreshAll(true);
      });
    });
  }

  function openAddNakladnoySheet() {
    let selectedFile = null;
    let originalAmt = null;
    let writtenAmtBeforeFix = null;
    let writtenOrigBeforeFix = null;
    let mathCheck = null;
    let appliedCalcFix = false;
    let pmMode = 'cash';
    let sendGroup = true;

    const html = `
      <div class="card" style="background:rgba(124,58,237,0.08);border-color:rgba(124,58,237,0.28);">
        <div class="grid-2">
          <label class="btn btn-primary btn-sm" style="margin:0;">
            📷 Kamera (AI)
            <input type="file" id="ai-cam-inp" accept="image/*" capture="environment" class="hidden" />
          </label>
          <label class="btn btn-outline btn-sm" style="margin:0;">
            🖼 Galereya (AI)
            <input type="file" id="ai-gal-inp" accept="image/*" class="hidden" />
          </label>
        </div>
        <div id="ai-preview-box" class="hidden" style="margin-top:8px;">
          <div style="position:relative;">
            <img id="ai-thumb" style="width:100%;max-height:130px;object-fit:cover;border-radius:12px;" />
            <button id="ai-clear-photo" class="icon-btn" type="button" style="position:absolute;top:6px;right:6px;">✕</button>
          </div>
        </div>
        <div id="ai-status-txt" style="margin-top:7px;font-size:12.5px;font-weight:800;"></div>
        <div id="ai-math-box"></div>
      </div>

      <div id="ai-sim-chips" class="pill-scroll"></div>

      <div class="field">
        <label>Postavshik nomi</label>
        <div class="row">
          <input class="input" id="add-sup" placeholder="Tanlang yoki yozing..." style="flex:1;" />
          <button class="btn btn-outline btn-sm" id="add-sup-pick" type="button">Ro'yxat ▾</button>
        </div>
        <div id="add-sup-picker-box" class="hidden" style="margin-top:6px;padding:10px;border-radius:14px;border:1px solid var(--border);background:var(--surface-alt);">
          <input class="input" id="add-sup-search" placeholder="Postavshik qidirish..." style="margin-bottom:8px;" />
          <div id="add-sup-list" style="max-height:190px;overflow-y:auto;display:flex;flex-direction:column;gap:6px;"></div>
        </div>
      </div>

      ${
        state.allSuppliers.length
          ? `<div class="pill-scroll">${state.allSuppliers
              .slice(0, 12)
              .map((s) => `<button class="pill-btn" data-qsup="${esc(s)}" type="button">${esc(s)}</button>`)
              .join('')}</div>`
          : ''
      }

      <div class="field">
        <label>Summa (so'm)</label>
        <input class="input tnum" id="add-amt" inputmode="numeric" placeholder="354 000" style="font-size:18px;" />
      </div>
      <div id="recent-amt-chips" class="pill-scroll"></div>

      <div class="field">
        <label>To'lov turi</label>
        <div class="pill-scroll">
          <button class="pill-btn active" data-pm="cash" type="button">💵 Naqd</button>
          <button class="pill-btn" data-pm="card" type="button">💳 Karta</button>
          <button class="pill-btn" data-pm="transfer" type="button">🏦 O'tkazma</button>
          <button class="pill-btn" data-pm="debt" type="button">📌 Qarzga</button>
        </div>
      </div>

      <div class="field">
        <label>Izoh (ixtiyoriy)</label>
        <input class="input" id="add-note" placeholder="Mahsulot nomi yoki izoh" />
      </div>

      <label class="switch-row">
        <span>📤 Telegram guruhga yuborish</span>
        <input type="checkbox" id="add-send-grp" checked />
      </label>

      <button class="btn btn-primary btn-block" id="add-submit" type="button">✅ Tasdiqlash va saqlash</button>
    `;

    openSheet('Yangi Nakladnoy', html, (body) => {
      const supEl = body.querySelector('#add-sup');
      const amtEl = body.querySelector('#add-amt');
      const noteEl = body.querySelector('#add-note');
      const grpEl = body.querySelector('#add-send-grp');
      const statusTxt = body.querySelector('#ai-status-txt');
      const mathBox = body.querySelector('#ai-math-box');
      const simBox = body.querySelector('#ai-sim-chips');
      const recentBox = body.querySelector('#recent-amt-chips');
      const previewBox = body.querySelector('#ai-preview-box');
      const thumbEl = body.querySelector('#ai-thumb');
      const submitBtn = body.querySelector('#add-submit');

      bindUzsFormatter(amtEl);

      const renderMathBox = () => {
        if (!mathCheck || mathCheck.status === 'skipped' || !mathCheck.items_count) {
          mathBox.innerHTML = '';
          return;
        }
        if (mathCheck.status === 'mismatch') {
          const targetCalc = mathCheck.rounded_calculated_total || mathCheck.calculated_total;
          if (appliedCalcFix && targetCalc > 0) {
            mathBox.innerHTML = `
              <div class="alert-box alert-green row-between">
                <span>✅ To'g'ri summa qo'yildi (${fmtUzs(targetCalc, true)})</span>
                ${
                  writtenAmtBeforeFix > 0
                    ? `<button class="btn btn-sm btn-outline" id="btn-revert-amt" type="button">Aslini qaytarish</button>`
                    : ''
                }
              </div>
            `;
            const revBtn = mathBox.querySelector('#btn-revert-amt');
            if (revBtn) {
              revBtn.addEventListener('click', () => {
                amtEl.value = formatDigitsInput(String(Math.round(writtenAmtBeforeFix)));
                originalAmt = writtenOrigBeforeFix;
                appliedCalcFix = false;
                renderMathBox();
              });
            }
            return;
          }
          const diff = Number(mathCheck.difference || 0);
          const diffTxt =
            diff > 0 ? `+${fmtUzs(Math.abs(diff))} so'm ortiqcha` : `-${fmtUzs(Math.abs(diff))} so'm kam`;
          const errsHtml = (mathCheck.line_errors || [])
            .slice(0, 4)
            .map(
              (le) =>
                `<div style="font-size:11.5px;margin-top:2px;">• ${esc(le.name)}: ${le.qty ?? '?'} × ${fmtUzs(le.unit_price)} = ${fmtUzs(le.expected)} (yozilgan: ${fmtUzs(le.written)})</div>`
            )
            .join('');
          mathBox.innerHTML = `
            <div class="alert-box alert-red">
              <div style="font-weight:900;">⚠️ HISOB-KITOBDA XATOLIK!</div>
              ${mathCheck.written_total != null ? `<div class="row-between" style="margin-top:4px;"><span>Rasmda yozilgan:</span><b>${fmtUzs(mathCheck.written_total, true)}</b></div>` : ''}
              ${mathCheck.calculated_total != null ? `<div class="row-between"><span>Hisoblangan (${mathCheck.items_count} ta qator):</span><b>${fmtUzs(mathCheck.calculated_total, true)}</b></div>` : ''}
              ${diff !== 0 ? `<div class="row-between"><span>Farq:</span><b>${diffTxt}</b></div>` : ''}
              ${errsHtml}
              ${
                targetCalc > 0
                  ? `<button class="btn btn-red btn-sm btn-block" id="btn-apply-calc" type="button" style="margin-top:8px;">
                       🧮 To'g'ri summani (${fmtUzs(targetCalc)} so'm) qo'yish
                     </button>`
                  : ''
              }
            </div>
          `;
          const applyBtn = mathBox.querySelector('#btn-apply-calc');
          if (applyBtn) {
            applyBtn.addEventListener('click', () => {
              amtEl.value = formatDigitsInput(String(Math.round(targetCalc)));
              originalAmt = mathCheck.calculated_total;
              appliedCalcFix = true;
              haptic('success');
              renderMathBox();
            });
          }
          return;
        }

        if (mathCheck.status === 'ok' || mathCheck.status === 'vat_ok') {
          const msg =
            mathCheck.status === 'vat_ok'
              ? `✅ Tekshirildi: ${mathCheck.items_count} ta qator + 12% QQS (НДС) mos`
              : `✅ Tekshirildi: ${mathCheck.items_count} ta qator yig'indisi mos (${fmtUzs(mathCheck.calculated_total, true)})`;
          mathBox.innerHTML = `<div class="alert-box alert-green"><b>${msg}</b></div>`;
        } else if (mathCheck.status === 'computed') {
          mathBox.innerHTML = `<div class="alert-box alert-violet"><b>🧮 Rasmda jami yozilmagan — ${mathCheck.items_count} ta qator hisoblandi: ${fmtUzs(mathCheck.calculated_total, true)}</b></div>`;
        } else if (mathCheck.status === 'adjusted') {
          mathBox.innerHTML = `<div class="alert-box alert-amber">ℹ️ Qatorlar yig'indisi: ${fmtUzs(mathCheck.calculated_total, true)} (chegirma/qaytarish/qoldiq bo'lishi mumkin)</div>`;
        }
      };

      const runAi = async (file) => {
        selectedFile = file;
        thumbEl.src = URL.createObjectURL(file);
        previewBox.classList.remove('hidden');
        statusTxt.style.color = 'var(--violet)';
        statusTxt.textContent = "✨ AI nakladnoyni o'qimoqda...";
        mathCheck = null;
        appliedCalcFix = false;
        mathBox.innerHTML = '';

        const fd = new FormData();
        fd.append('photo', file, file.name || 'nakladnoy.jpg');
        try {
          const res = await apiFetch('/ai/extract', { method: 'POST', body: fd });
          if (res.supplier_name) supEl.value = res.supplier_name;
          if (res.amount > 0) amtEl.value = formatDigitsInput(String(Math.round(res.amount)));
          originalAmt = res.original_amount;
          writtenAmtBeforeFix = res.amount;
          writtenOrigBeforeFix = res.original_amount;
          mathCheck = res.math_check || null;

          if (mathCheck && mathCheck.status === 'mismatch') {
            statusTxt.style.color = 'var(--red)';
            statusTxt.textContent = "⚠️ AI o'qidi, lekin nakladnoy summasida xatolik topildi!";
          } else if (mathCheck && mathCheck.status === 'computed') {
            statusTxt.style.color = 'var(--violet)';
            statusTxt.textContent = "🧮 AI qatorlar yig'indisini hisoblab chiqdi!";
          } else if (res.ok) {
            statusTxt.style.color = 'var(--green)';
            const rNote =
              res.original_amount && res.amount && Math.round(res.original_amount) !== Math.round(res.amount)
                ? ` (${fmtUzs(res.original_amount)} → ${fmtUzs(res.amount)})`
                : '';
            statusTxt.textContent = `✨ AI avtomatik to'ldirdi!${rNote}`;
          } else {
            statusTxt.style.color = 'var(--amber)';
            statusTxt.textContent = res.message || "ℹ️ Rasmda yozuv to'liq o'qilmadi — qo'lda kiriting";
          }

          if (Array.isArray(res.similar_suppliers) && res.similar_suppliers.length) {
            simBox.innerHTML = res.similar_suppliers
              .map((s) => `<button class="pill-btn" data-sim-sup="${esc(s)}" type="button">✨ ${esc(s)}</button>`)
              .join('');
            simBox.querySelectorAll('[data-sim-sup]').forEach((b) =>
              b.addEventListener('click', () => {
                supEl.value = b.getAttribute('data-sim-sup');
                simBox.innerHTML = '';
              })
            );
          }

          if (Array.isArray(res.recent_amounts) && res.recent_amounts.length) {
            recentBox.innerHTML = res.recent_amounts
              .map((a) => `<button class="pill-btn tnum" data-rec-amt="${a}" type="button">${fmtUzs(a)}</button>`)
              .join('');
            recentBox.querySelectorAll('[data-rec-amt]').forEach((b) =>
              b.addEventListener('click', () => {
                amtEl.value = formatDigitsInput(String(Math.round(Number(b.getAttribute('data-rec-amt')))));
              })
            );
          }
          renderMathBox();
        } catch (err) {
          statusTxt.style.color = 'var(--amber)';
          statusTxt.textContent = `⚠️ AI tahlil xatosi: ${err.message}`;
        }
      };

      body.querySelector('#ai-cam-inp').addEventListener('change', (e) => {
        if (e.target.files && e.target.files[0]) runAi(e.target.files[0]);
      });
      body.querySelector('#ai-gal-inp').addEventListener('change', (e) => {
        if (e.target.files && e.target.files[0]) runAi(e.target.files[0]);
      });
      body.querySelector('#ai-clear-photo').addEventListener('click', () => {
        selectedFile = null;
        mathCheck = null;
        appliedCalcFix = false;
        previewBox.classList.add('hidden');
        statusTxt.textContent = '';
        mathBox.innerHTML = '';
      });

      const pickerBox = body.querySelector('#add-sup-picker-box');
      const pickerSearch = body.querySelector('#add-sup-search');
      const pickerList = body.querySelector('#add-sup-list');

      const loadRecentForSup = async (supName) => {
        try {
          const amts = await apiFetch(`/suppliers/amounts?supplier=${encodeURIComponent(supName)}`);
          recentBox.innerHTML = (amts.amounts || [])
            .map((a) => `<button class="pill-btn tnum" data-rec-amt="${a}" type="button">${fmtUzs(a)}</button>`)
            .join('');
          recentBox.querySelectorAll('[data-rec-amt]').forEach((ab) =>
            ab.addEventListener('click', () => {
              amtEl.value = formatDigitsInput(String(Math.round(Number(ab.getAttribute('data-rec-amt')))));
            })
          );
        } catch (_) {}
      };

      const renderInlineSupplierList = (q) => {
        const needle = (q || '').trim().toLowerCase();
        const items = needle
          ? state.allSuppliers.filter((s) => s.toLowerCase().includes(needle))
          : state.allSuppliers;
        pickerList.innerHTML = items.length
          ? items
              .slice(0, 40)
              .map(
                (s) =>
                  `<button class="dd-option${supEl.value.trim() === s ? ' selected' : ''}" data-inl-sup="${esc(s)}" type="button" style="padding:8px 10px;">
                     <span style="font-size:15px;">🏪</span>
                     <span class="dd-option-lbl" style="flex:1;">${esc(s)}</span>
                   </button>`
              )
              .join('')
          : `<div style="text-align:center;color:var(--text-2);padding:8px;">Topilmadi</div>`;
        pickerList.querySelectorAll('[data-inl-sup]').forEach((btn) => {
          btn.addEventListener('click', () => {
            const chosen = btn.getAttribute('data-inl-sup');
            supEl.value = chosen;
            pickerBox.classList.add('hidden');
            haptic();
            loadRecentForSup(chosen);
          });
        });
      };

      body.querySelectorAll('[data-qsup]').forEach((b) => {
        b.addEventListener('click', () => {
          supEl.value = b.getAttribute('data-qsup');
          pickerBox.classList.add('hidden');
          loadRecentForSup(supEl.value);
        });
      });

      body.querySelector('#add-sup-pick').addEventListener('click', () => {
        const willOpen = pickerBox.classList.contains('hidden');
        pickerBox.classList.toggle('hidden', !willOpen);
        if (willOpen) {
          renderInlineSupplierList(pickerSearch.value);
          pickerSearch.focus();
        }
      });
      pickerSearch.addEventListener('input', () => renderInlineSupplierList(pickerSearch.value));

      body.querySelectorAll('[data-pm]').forEach((b) => {
        b.addEventListener('click', () => {
          pmMode = b.getAttribute('data-pm');
          body.querySelectorAll('[data-pm]').forEach((x) => x.classList.toggle('active', x === b));
        });
      });

      submitBtn.addEventListener('click', async () => {
        const sup = supEl.value.trim();
        const amt = parseUzsInput(amtEl.value);
        if (!sup) return showToast('Postavshik nomini kiriting', true);
        if (!amt) return showToast('Summani kiriting', true);
        submitBtn.disabled = true;
        try {
          const fd = new FormData();
          fd.append('supplier_name', sup);
          fd.append('amount', String(amt));
          fd.append('payment_mode', pmMode);
          fd.append('note', noteEl.value.trim());
          fd.append('send_to_group', grpEl.checked ? 'true' : 'false');
          if (originalAmt != null) fd.append('original_amount', String(originalAmt));
          if (selectedFile) fd.append('photo', selectedFile, selectedFile.name || 'nakladnoy.jpg');
          await apiFetch('/nakladnoy', { method: 'POST', body: fd });
          haptic('success');
          closeSheet();
          showToast('✅ Nakladnoy saqlandi!');
          await refreshAll(true);
        } catch (err) {
          showToast(err.message, true);
          submitBtn.disabled = false;
        }
      });
    });
  }

  function openNakladnoyDetailSheet(item) {
    const isPast = Boolean(state.viewedSummary && state.summary && state.viewedSummary.session_id !== state.summary.session_id);
    const readOnly = isPast || item.session_status === 'closed';
    const photoSrc = item.has_photo ? photoUrl(item.id, Date.now()) : '';

    if (readOnly) {
      // Clean read-only view WITHOUT any "yopilgan kun" banner text
      const html = `
        ${
          photoSrc
            ? `<img src="${esc(photoSrc)}" id="det-photo-img" style="width:100%;max-height:240px;object-fit:cover;border-radius:14px;cursor:pointer;" />`
            : ''
        }
        <div class="card">
          <div class="row-between" style="padding:5px 0;">
            <span style="color:var(--text-2);">Postavshik:</span>
            <b>${esc(item.supplier_name)}</b>
          </div>
          <div class="row-between" style="padding:5px 0;">
            <span style="color:var(--text-2);">Summa:</span>
            <b class="tnum" style="color:var(--brand);font-size:16px;">${fmtUzs(item.amount, true)}</b>
          </div>
          <div class="row-between" style="padding:5px 0;">
            <span style="color:var(--text-2);">To'lov turi:</span>
            ${pmBadge(item)}
          </div>
          <div class="row-between" style="padding:5px 0;">
            <span style="color:var(--text-2);">Vaqt:</span>
            <span>${esc(item.created_at)}</span>
          </div>
          ${item.note ? `<div class="row-between" style="padding:5px 0;"><span style="color:var(--text-2);">Izoh:</span><span>${esc(item.note)}</span></div>` : ''}
        </div>
      `;
      openSheet(`Nakladnoy ${item.display_num}${item.report_date ? ` (${item.report_date})` : ''}`, html, (body) => {
        const img = body.querySelector('#det-photo-img');
        if (img) img.addEventListener('click', () => openLightbox(photoSrc));
      });
      return;
    }

    const html = `
      ${
        photoSrc
          ? `<img src="${esc(photoSrc)}" id="det-photo-img" style="width:100%;max-height:200px;object-fit:cover;border-radius:14px;cursor:pointer;" />`
          : `<div style="padding:14px;border-radius:13px;background:var(--surface-alt);text-align:center;color:var(--text-2);">Rasm biriktirilmagan</div>`
      }
      <label class="btn btn-outline btn-sm btn-block" style="margin:0;">
        📸 ${item.has_photo ? 'Rasmni almashtirish' : 'Rasm biriktirish'}
        <input type="file" id="det-up-photo" accept="image/*" class="hidden" />
      </label>

      <div class="field"><label>Postavshik nomi</label><input class="input" id="det-sup" value="${esc(item.supplier_name)}" /></div>
      <div class="field"><label>Summa (so'm)</label><input class="input tnum" id="det-amt" inputmode="numeric" value="${formatDigitsInput(String(Math.round(item.amount)))}" /></div>
      <div class="field"><label>Izoh</label><input class="input" id="det-note" value="${esc(item.note)}" placeholder="Izoh..." /></div>

      <button class="btn btn-primary btn-block" id="det-save-all" type="button">💾 O'zgarishlarni saqlash</button>

      <div class="field" style="margin-top:4px;">
        <label>To'lov holati</label>
        <div class="grid-2">
          <button class="btn btn-sm ${!item.is_debt && item.payment_method === 'cash' ? 'btn-green' : 'btn-outline'}" data-det-pm="cash" type="button">💵 Naqd</button>
          <button class="btn btn-sm ${!item.is_debt && item.payment_method === 'card' ? 'btn-primary' : 'btn-outline'}" data-det-pm="card" type="button">💳 Karta</button>
          <button class="btn btn-sm ${!item.is_debt && item.payment_method === 'transfer' ? 'btn-primary' : 'btn-outline'}" data-det-pm="transfer" type="button">🏦 O'tkazma</button>
          <button class="btn btn-sm ${item.is_debt ? 'btn-red' : 'btn-outline'}" id="det-to-debt" type="button">📌 Qarzga</button>
        </div>
      </div>

      <div class="grid-2" style="margin-top:4px;">
        <button class="btn btn-outline btn-sm" id="det-post-grp" type="button">📤 Guruhga yuborish</button>
        <button class="btn btn-red btn-sm" id="det-delete" type="button">🗑 O'chirish</button>
      </div>
    `;

    openSheet(`Nakladnoy ${item.display_num}`, html, (body) => {
      const img = body.querySelector('#det-photo-img');
      if (img) img.addEventListener('click', () => openLightbox(photoSrc));
      const amtEl = body.querySelector('#det-amt');
      bindUzsFormatter(amtEl);

      body.querySelector('#det-up-photo').addEventListener('change', async (e) => {
        const file = e.target.files && e.target.files[0];
        if (!file) return;
        const fd = new FormData();
        fd.append('photo', file, file.name || 'photo.jpg');
        fd.append('send_to_group', 'true');
        await apiFetch(`/nakladnoy/${item.id}/photo`, { method: 'POST', body: fd });
        haptic('success');
        closeSheet();
        showToast('📸 Rasm biriktirildi!');
        await refreshAll(true);
      });

      // Unified single Save button
      body.querySelector('#det-save-all').addEventListener('click', async () => {
        const sup = body.querySelector('#det-sup').value.trim();
        const amt = parseUzsInput(amtEl.value);
        const note = body.querySelector('#det-note').value;
        if (!sup || !amt) return showToast("Postavshik va summani to'liq kiriting", true);
        await apiFetch(`/nakladnoy/${item.id}`, {
          method: 'PATCH',
          json: { supplier_name: sup, amount: amt, note },
        });
        haptic('success');
        closeSheet();
        showToast("✅ O'zgarishlar saqlandi!");
        await refreshAll(true);
      });

      body.querySelectorAll('[data-det-pm]').forEach((b) => {
        b.addEventListener('click', async () => {
          const pm = b.getAttribute('data-det-pm');
          if (item.is_debt) {
            await apiFetch(`/nakladnoy/${item.id}/paid`, { method: 'POST', json: { payment_method: pm } });
          } else {
            await apiFetch(`/nakladnoy/${item.id}/payment-method`, { method: 'POST', json: { payment_method: pm } });
          }
          haptic('success');
          closeSheet();
          showToast("✅ To'lov turi yangilandi");
          await refreshAll(true);
        });
      });

      body.querySelector('#det-to-debt').addEventListener('click', async () => {
        await apiFetch(`/nakladnoy/${item.id}/debt`, { method: 'POST' });
        haptic('success');
        closeSheet();
        showToast("📌 Qarzga o'tkazildi");
        await refreshAll(true);
      });

      body.querySelector('#det-post-grp').addEventListener('click', async () => {
        try {
          const r = await apiFetch(`/nakladnoy/${item.id}/group`, { method: 'POST' });
          showToast(r.message || '📤 Guruhga yuborildi');
          await refreshAll(true);
        } catch (err) {
          showToast(err.message, true);
        }
      });

      body.querySelector('#det-delete').addEventListener('click', async () => {
        if (!confirm("Nakladnoyni o'chirishni tasdiqlaysizmi?")) return;
        await apiFetch(`/nakladnoy/${item.id}`, { method: 'DELETE' });
        haptic('success');
        closeSheet();
        showToast("🗑 O'chirildi");
        await refreshAll(true);
      });
    });
  }

  function openPayDebtSheet(item) {
    const html = `
      <div class="card">
        <div style="font-weight:900;font-size:15px;">${esc(item.supplier_name)}</div>
        <div class="tnum" style="font-size:20px;font-weight:900;color:var(--amber);margin-top:4px;">${fmtUzs(item.amount, true)}</div>
      </div>
      <button class="btn btn-green btn-block" data-pay-pm="cash" type="button">💵 Naqd bilan to'lash</button>
      <button class="btn btn-primary btn-block" data-pay-pm="card" type="button">💳 Karta bilan to'lash</button>
      <button class="btn btn-outline btn-block" data-pay-pm="transfer" type="button">🏦 O'tkazma bilan to'lash</button>
    `;
    openSheet("Qarzni to'lash", html, (body) => {
      body.querySelectorAll('[data-pay-pm]').forEach((b) => {
        b.addEventListener('click', async () => {
          const pm = b.getAttribute('data-pay-pm');
          await apiFetch(`/nakladnoy/${item.id}/paid`, { method: 'POST', json: { payment_method: pm } });
          haptic('success');
          closeSheet();
          showToast("✅ Qarz to'landi deb belgilandi!");
          await refreshAll(true);
        });
      });
    });
  }

  function openAddNasiyaSheet() {
    let entryType = 'debt';
    const html = `
      <div class="grid-2">
        <button class="btn btn-primary btn-sm" data-nt="debt" type="button">📌 Qarzga oldik</button>
        <button class="btn btn-outline btn-sm" data-nt="payment" type="button">✅ Qarz berdik</button>
      </div>
      <div class="field"><label>Postavshik</label><input class="input" id="nas-sup" placeholder="Postavshik nomi" /></div>
      <div class="field"><label>Summa (so'm)</label><input class="input tnum" id="nas-amt" inputmode="numeric" placeholder="500 000" /></div>
      <div class="field"><label>Izoh</label><input class="input" id="nas-note" placeholder="Izoh..." /></div>
      <button class="btn btn-primary btn-block" id="nas-save" type="button">Saqlash</button>
    `;
    openSheet('Nasiya daftari yozuvi', html, (body) => {
      const amtEl = body.querySelector('#nas-amt');
      bindUzsFormatter(amtEl);
      body.querySelectorAll('[data-nt]').forEach((b) => {
        b.addEventListener('click', () => {
          entryType = b.getAttribute('data-nt');
          body.querySelectorAll('[data-nt]').forEach((x) => {
            x.className = `btn btn-sm ${x === b ? 'btn-primary' : 'btn-outline'}`;
          });
        });
      });
      body.querySelector('#nas-save').addEventListener('click', async () => {
        const sup = body.querySelector('#nas-sup').value.trim();
        const amt = parseUzsInput(amtEl.value);
        if (!sup || !amt) return showToast('Postavshik va summani kiriting', true);
        await apiFetch('/nasiya', {
          method: 'POST',
          json: { supplier_name: sup, entry_type: entryType, amount: amt, note: body.querySelector('#nas-note').value.trim() },
        });
        state.nasiya = await apiFetch('/nasiya');
        closeSheet();
        showToast('✅ Nasiya yozuvi saqlandi');
        render();
      });
    });
  }

  function openGlobalSearchSheet() {
    const html = `
      <div class="row">
        <input class="input" id="gs-inp" placeholder="Postavshik nomi yoki summa..." style="flex:1;" />
        <button class="btn btn-primary btn-sm" id="gs-btn" type="button">Qidirish</button>
      </div>
      <div id="gs-results" style="display:flex;flex-direction:column;gap:8px;"></div>
    `;
    openSheet('Barcha kunlardan qidirish', html, (body) => {
      const inp = body.querySelector('#gs-inp');
      const box = body.querySelector('#gs-results');
      const run = async () => {
        const q = inp.value.trim();
        if (!q) return;
        const r = await apiFetch(`/history/search?q=${encodeURIComponent(q)}`);
        const items = r.items || [];
        box.innerHTML = items.length
          ? items.map(renderNakCard).join('')
          : `<div style="text-align:center;color:var(--text-2);padding:18px;">Topilmadi</div>`;
        box.querySelectorAll('[data-nak-id]').forEach((el) => {
          el.addEventListener('click', () => {
            const id = Number(el.getAttribute('data-nak-id'));
            const found = items.find((x) => x.id === id);
            if (found) openNakladnoyDetailSheet(found);
          });
        });
      };
      body.querySelector('#gs-btn').addEventListener('click', run);
      inp.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') run();
      });
      inp.focus();
    });
  }

  function openHistorySheet() {
    const sessions = state.historySessions || [];
    const html = sessions.length
      ? sessions
          .map(
            (s) => `
          <div class="nak-card" data-open-sess="${s.id}">
            <div class="row-between">
              <div style="font-weight:900;">${s.status === 'open' ? '🟢' : '📅'} ${esc(s.report_date)} • Smena #${s.id}</div>
              <div class="tnum" style="font-weight:900;color:var(--brand);">${fmtUzs(s.expected_cash, true)}</div>
            </div>
            ${
              s.actual_counted_cash != null
                ? `<div style="font-size:12px;color:var(--text-2);margin-top:4px;">Sanalgan: ${fmtUzs(s.actual_counted_cash, true)} (Farq: ${fmtUzs(s.difference)})</div>`
                : ''
            }
          </div>`
          )
          .join('')
      : `<div style="text-align:center;color:var(--text-2);padding:20px;">Tarix topilmadi</div>`;

    openSheet("O'tgan smenalar tarixi", html, (body) => {
      body.querySelectorAll('[data-open-sess]').forEach((el) => {
        el.addEventListener('click', async () => {
          const sid = Number(el.getAttribute('data-open-sess'));
          closeSheet();
          state.viewedSummary = sid === state.summary.session_id ? null : await apiFetch(`/history/sessions/${sid}`);
          render();
        });
      });
    });
  }

  function openSverkaSheet() {
    let curMonth = new Date().toISOString().slice(0, 7);
    let q = '';
    const loadMonth = async (body) => {
      const box = body.querySelector('#sv-content');
      box.innerHTML = `<div style="text-align:center;padding:20px;">Yuklanmoqda...</div>`;
      const data = await apiFetch(`/sverka?month=${encodeURIComponent(curMonth)}`);
      body.querySelector('#sv-month-lbl').textContent = curMonth;
      const list = (data.suppliers || []).filter((s) => !q || s.supplier.toLowerCase().includes(q.toLowerCase()));
      box.innerHTML = `
        <div class="alert-box alert-violet row-between" style="margin-top:0;">
          <span>Jami (${list.length} ta):</span>
          <b class="tnum">${fmtUzs(data.grand_total, true)}</b>
        </div>
        ${list
          .map(
            (r) => `
          <div class="nak-card">
            <div class="row-between">
              <b>${esc(r.supplier)} (${r.count} ta)</b>
              <b class="tnum" style="color:var(--brand);">${fmtUzs(r.total, true)}</b>
            </div>
            <div style="font-size:11.5px;color:var(--text-2);margin-top:4px;">
              Naqd: ${fmtUzs(r.cash_total)} • Karta: ${fmtUzs(r.card_total)} • O'tkazma: ${fmtUzs(r.transfer_total)}
            </div>
          </div>`
          )
          .join('')}
      `;
    };
    const shiftMonth = (delta) => {
      const [y, m] = curMonth.split('-').map(Number);
      const dt = new Date(y, m - 1 + delta, 1);
      curMonth = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`;
    };
    const html = `
      <div class="row-between">
        <button class="icon-btn" id="sv-prev" type="button">‹</button>
        <div id="sv-month-lbl" style="font-weight:900;font-size:15px;">${curMonth}</div>
        <button class="icon-btn" id="sv-next" type="button">›</button>
        <button class="btn btn-green btn-sm" id="sv-xlsx" type="button">📥 Excel</button>
      </div>
      <input class="input" id="sv-search" placeholder="Postavshik qidirish..." />
      <div id="sv-content" style="display:flex;flex-direction:column;gap:8px;"></div>
    `;
    openSheet('Jonli Sverka', html, (body) => {
      loadMonth(body);
      body.querySelector('#sv-prev').addEventListener('click', () => { shiftMonth(-1); loadMonth(body); });
      body.querySelector('#sv-next').addEventListener('click', () => { shiftMonth(1); loadMonth(body); });
      body.querySelector('#sv-search').addEventListener('input', (e) => { q = e.target.value; loadMonth(body); });
      body.querySelector('#sv-xlsx').addEventListener('click', () => downloadExcel(`/export/sverka?month=${curMonth}`, `Sverka_${curMonth}.xlsx`));
    });
  }

  function openPrixodSheet() {
    const html = `
      <div class="field">
        <label>YesPOS / qo'lda matn kiritish (ITOG 👑)</label>
        <textarea class="textarea" id="prx-txt" placeholder="Nafis 150 000&#10;Coca Cola 200 000"></textarea>
      </div>
      <div class="grid-2">
        <button class="btn btn-primary btn-sm" id="prx-save-txt" type="button">👑 Matndan ITOG</button>
        <label class="btn btn-outline btn-sm" style="margin:0;">
          📄 Fayl (.xlsx/.csv)
          <input type="file" id="prx-file" accept=".xlsx,.xls,.csv" class="hidden" />
        </label>
      </div>
      <div id="prx-list" style="display:flex;flex-direction:column;gap:8px;margin-top:6px;"></div>
    `;
    const loadPrixod = async (body) => {
      const r = await apiFetch('/prixod');
      const items = r.items || [];
      const box = body.querySelector('#prx-list');
      box.innerHTML = items.length
        ? items
            .map(
              (p) => `
          <div class="card">
            <div class="row-between">
              <b>👑 ${esc(p.report_date)}</b>
              <b class="tnum" style="color:var(--brand);">${fmtUzs(p.total_cost, true)}</b>
            </div>
            <pre class="pre-box" style="margin-top:7px;">${esc(p.formatted_text)}</pre>
            ${
              !p.in_group
                ? `<button class="btn btn-soft btn-sm btn-block" data-prx-pub="${p.id}" type="button" style="margin-top:7px;">📤 Guruhga yuborish</button>`
                : `<div style="margin-top:6px;font-size:11.5px;color:var(--green);font-weight:800;">✅ Guruhga yuborilgan</div>`
            }
          </div>`
            )
            .join('')
        : `<div style="text-align:center;color:var(--text-2);padding:16px;">Prixod hisobotlari yo'q</div>`;
      box.querySelectorAll('[data-prx-pub]').forEach((b) => {
        b.addEventListener('click', async () => {
          await apiFetch(`/prixod/${b.getAttribute('data-prx-pub')}/publish`, { method: 'POST' });
          showToast('📤 Prixod guruhiga yuborildi');
          loadPrixod(body);
        });
      });
    };
    openSheet('Prixod (ITOG 👑)', html, (body) => {
      loadPrixod(body);
      body.querySelector('#prx-save-txt').addEventListener('click', async () => {
        const text = body.querySelector('#prx-txt').value.trim();
        if (!text) return showToast('Matn kiriting', true);
        await apiFetch('/prixod/text', { method: 'POST', json: { text, publish_to_group: false } });
        body.querySelector('#prx-txt').value = '';
        showToast('👑 Prixod saqlandi');
        loadPrixod(body);
      });
      body.querySelector('#prx-file').addEventListener('change', async (e) => {
        const file = e.target.files && e.target.files[0];
        if (!file) return;
        const fd = new FormData();
        fd.append('file', file, file.name);
        fd.append('publish_to_group', 'false');
        await apiFetch('/prixod/file', { method: 'POST', body: fd });
        showToast('👑 Fayldan Prixod yaratildi');
        loadPrixod(body);
      });
    });
  }

  function openSettingsSheet() {
    const html = `<div id="set-inner">Yuklanmoqda...</div>`;
    const loadSettings = async (body) => {
      const [rmRes, supRes] = await Promise.all([apiFetch('/settings/round-mode'), apiFetch('/settings/suppliers')]);
      const curMode = rmRes.round_mode || 'floor_1000';
      const roundOpts = [
        { value: 'floor_1000', label: "1 000 so'mga pastga", subtitle: '192 640 → 192 000', icon: '⬇️' },
        { value: 'nearest_1000', label: "1 000 so'mga yaqiniga", subtitle: '192 640 → 193 000', icon: '↕️' },
        { value: 'none', label: 'Yaxlitlanmasin', subtitle: 'Aniq summa saqlanadi', icon: '🎯' },
      ];
      const cfgs = supRes.configs || [];
      body.querySelector('#set-inner').innerHTML = `
        <div class="card">
          ${renderCustomDropdownTrigger({ id: 'dd-round-mode', labelText: 'AI Summa Yaxlitlash Qoidasi', value: curMode, options: roundOpts })}
        </div>
        <div class="card">
          <div style="font-weight:900;margin-bottom:8px;">Yangi postavshik / taxallus qo'shish</div>
          <input class="input" id="set-sup-name" placeholder="Asosiy nomi (masalan: Coca Cola)" style="margin-bottom:7px;" />
          <input class="input" id="set-sup-aliases" placeholder="Taxalluslar: КОКА КОЛА,COCA..." style="margin-bottom:8px;" />
          <button class="btn btn-primary btn-sm btn-block" id="set-sup-add" type="button">+ Qo'shish</button>
        </div>
        <div style="display:flex;flex-direction:column;gap:6px;">
          ${cfgs
            .map(
              (c) => `
            <div class="row-between" style="padding:9px 11px;border-radius:12px;background:var(--surface-alt);border:1px solid var(--border);">
              <div>
                <div style="font-weight:800;">${esc(c.display_name)}</div>
                ${c.aliases ? `<div style="font-size:11px;color:var(--text-2);">${esc(c.aliases)}</div>` : ''}
              </div>
              <button class="icon-btn" style="width:28px;height:28px;font-size:12px;" data-del-sup="${c.id}" type="button">🗑</button>
            </div>`
            )
            .join('')}
        </div>
      `;
      body.querySelector('#dd-round-mode').addEventListener('click', () => {
        openCustomDropdown({
          title: 'AI summa yaxlitlash qoidasi',
          value: curMode,
          options: roundOpts,
          onSelect: async (v) => {
            await apiFetch('/settings/round-mode', { method: 'POST', json: { round_mode: v } });
            showToast('✅ Yaxlitlash qoidasi saqlandi');
            openSettingsSheet();
          },
        });
      });
      body.querySelector('#set-sup-add').addEventListener('click', async () => {
        const display_name = body.querySelector('#set-sup-name').value.trim();
        const aliases = body.querySelector('#set-sup-aliases').value.trim();
        if (!display_name) return showToast('Postavshik nomini kiriting', true);
        await apiFetch('/settings/suppliers', { method: 'POST', json: { display_name, aliases, default_category: 'qarz' } });
        showToast('✅ Postavshik saqlandi');
        loadSettings(body);
      });
      body.querySelectorAll('[data-del-sup]').forEach((b) => {
        b.addEventListener('click', async () => {
          await apiFetch(`/settings/suppliers/${b.getAttribute('data-del-sup')}`, { method: 'DELETE' });
          showToast("🗑 O'chirildi");
          loadSettings(body);
        });
      });
    };
    openSheet('Postavshiklar va Yaxlitlash', html, loadSettings);
  }

  // Static Global Controls
  document.getElementById('btn-refresh').addEventListener('click', () => refreshAll());
  document.getElementById('btn-theme').addEventListener('click', () => {
    const curDark = document.documentElement.getAttribute('data-theme') === 'dark';
    applyTheme(!curDark);
  });
  document.getElementById('sheet-close').addEventListener('click', closeSheet);
  $sheetOverlay.addEventListener('click', (e) => {
    if (e.target === $sheetOverlay) closeSheet();
  });
  document.getElementById('lightbox-close').addEventListener('click', () => {
    $lightbox.classList.add('hidden');
  });
  $lightbox.addEventListener('click', (e) => {
    if (e.target === $lightbox) $lightbox.classList.add('hidden');
  });
  $fab.addEventListener('click', openAddNakladnoySheet);

  document.querySelectorAll('#bottom-nav .nav-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      haptic();
      state.tab = btn.getAttribute('data-tab');
      render();
    });
  });

  window.addEventListener('unhandledrejection', (e) => {
    if (e.reason && e.reason.message) {
      showToast(e.reason.message, true);
    }
  });

  // Boot
  (async function boot() {
    initTelegramChrome();
    try {
      await authenticateWebApp();
      await refreshAll();
    } catch (err) {
      state.error = err;
      state.loading = false;
      render();
    }
  })();
})();
