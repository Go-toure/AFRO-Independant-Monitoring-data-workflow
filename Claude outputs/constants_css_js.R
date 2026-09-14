# ============================================================
# CUSTOM CSS & JS
# ============================================================
# Moved out of shiny_app/app.R during the app.R modularization pass.
# This file lives in shiny_app/R/ , which Shiny's runApp() sources
# automatically before app.R itself runs (shiny::loadSupport()), so
# no explicit source() call is needed anywhere -- everything defined
# here is available to app.R exactly as if it were still inline.
# Content is verbatim from the original app.R (byte-identical).
# ============================================================

# ── CUSTOM CSS ────────────────────────────────────────────────────────────────
CSS <- "
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap');

/* ─ Root ─────────────────────────────────────────────── */
:root {
  --blue:#005C97; --blue2:#003F6B; --blue3:#1A7BBF;
  --teal:#00C9C8; --green:#27AE60; --orange:#E8730A;
  --red:#C0392B;  --purple:#8E44AD; --dark:#1A2637;
  --muted:#6C7A8D; --bg:#F0F4F8; --card:#FFFFFF;
  --sh: 0 4px 24px rgba(0,92,151,.10);
  --sh2:0 10px 40px rgba(0,92,151,.18);
  --r:16px; --tr:.28s cubic-bezier(.4,0,.2,1);
}
*  { box-sizing:border-box; }
body { background:var(--bg)!important; font-family:'Inter',sans-serif!important; color:var(--dark)!important; }

/* ─ Scrollbar ────────────────────────────────────────── */
::-webkit-scrollbar{width:5px;height:5px}
::-webkit-scrollbar-track{background:#e8eef5;border-radius:3px}
::-webkit-scrollbar-thumb{background:var(--blue);border-radius:3px}

/* ─ Navbar ───────────────────────────────────────────── */
.navbar{
  background:linear-gradient(135deg,var(--blue2) 0%,var(--blue) 55%,var(--blue3) 100%)!important;
  box-shadow:0 2px 28px rgba(0,0,0,.28)!important;
  padding:10px 28px!important; border-bottom:none!important;
}
.navbar-brand,.navbar-nav .nav-link{color:rgba(255,255,255,.92)!important;font-weight:600!important;}
.navbar-nav .nav-link{padding:8px 18px!important;margin:0 3px!important;border-radius:10px!important;transition:var(--tr)!important;}
.navbar-nav .nav-link:hover,.navbar-nav .nav-link.active{
  color:#fff!important;background:rgba(255,255,255,.18)!important;}

/* ─ Cards ────────────────────────────────────────────── */
.card{
  border:none!important; border-radius:var(--r)!important;
  box-shadow:var(--sh)!important; background:var(--card)!important;
  transition:box-shadow var(--tr),transform var(--tr)!important; overflow:hidden!important;
}
.card:hover{box-shadow:var(--sh2)!important;}
.card-header{
  background:transparent!important;
  border-bottom:1px solid rgba(0,92,151,.07)!important;
  font-weight:600!important; color:var(--dark)!important;
  padding:15px 20px 12px!important; font-size:.9rem!important;
  letter-spacing:.01em!important;
}

/* ─ KPI Cards ────────────────────────────────────────── */
.kpi{
  border-radius:var(--r)!important; padding:22px!important; color:#fff!important;
  position:relative!important; overflow:hidden!important; height:100%!important;
  transition:transform var(--tr),box-shadow var(--tr)!important;
  box-shadow:0 6px 28px rgba(0,0,0,.16)!important;
  display:flex!important; flex-direction:column!important; justify-content:space-between!important;
  cursor:default!important;
}
.kpi:hover{transform:translateY(-6px) scale(1.015)!important;box-shadow:0 14px 40px rgba(0,0,0,.24)!important;}
.kpi::before{content:'';position:absolute;top:-50px;right:-35px;width:150px;height:150px;border-radius:50%;background:rgba(255,255,255,.11);}
.kpi::after {content:'';position:absolute;bottom:-60px;right:10px; width:110px;height:110px;border-radius:50%;background:rgba(255,255,255,.07);}
.kpi-icon {font-size:2rem;opacity:.85;position:relative;z-index:1;line-height:1;}
.kpi-label{font-size:.7rem;font-weight:600;letter-spacing:.09em;text-transform:uppercase;opacity:.82;position:relative;z-index:1;margin-top:14px;}
.kpi-val  {font-size:2.1rem;font-weight:800;line-height:1.05;position:relative;z-index:1;margin:2px 0 4px;}
.kpi-sub  {font-size:.7rem;opacity:.72;position:relative;z-index:1;}

.kpi-blue  {background:linear-gradient(140deg,var(--blue2) 0%,var(--blue) 55%,var(--blue3) 100%);}
.kpi-teal  {background:linear-gradient(140deg,var(--teal2) 0%,var(--teal) 100%);}
.kpi-green {background:linear-gradient(140deg,#1A7A44 0%,var(--green) 55%,#2ECC71 100%);}
.kpi-orange{background:linear-gradient(140deg,#B8520A 0%,var(--orange) 55%,#F39C12 100%);}
.kpi-purple{background:linear-gradient(140deg,var(--purple2) 0%,var(--purple) 55%,#9B59B6 100%);}
.kpi-red   {background:linear-gradient(140deg,var(--red2) 0%,var(--red) 55%,#E74C3C 100%);}

/* ─ Sidebar ──────────────────────────────────────────── */
.bslib-sidebar-layout>.sidebar{
  background:var(--dark)!important; border-radius:var(--r)!important;
  box-shadow:var(--sh2)!important; padding:22px 18px!important;
  border:none!important;
}
.bslib-sidebar-layout>.sidebar label,
.bslib-sidebar-layout>.sidebar .shiny-input-container>label,
.bslib-sidebar-layout>.sidebar h6{
  color:rgba(255,255,255,.7)!important; font-size:.7rem!important;
  font-weight:700!important; letter-spacing:.07em!important; text-transform:uppercase!important;
}
.bslib-sidebar-layout>.sidebar .form-select,
.bslib-sidebar-layout>.sidebar .form-control{
  background:rgba(255,255,255,.08)!important; border:1.5px solid rgba(255,255,255,.14)!important;
  color:#fff!important; border-radius:10px!important; font-size:.84rem!important;
}
.bslib-sidebar-layout>.sidebar .form-select:focus,
.bslib-sidebar-layout>.sidebar .form-control:focus{
  border-color:var(--teal)!important;
  box-shadow:0 0 0 3px rgba(0,201,200,.22)!important;
}
.bslib-sidebar-layout>.sidebar .form-select option{background:#1A2637;color:#fff;}
.bslib-sidebar-layout>.sidebar hr{border-color:rgba(255,255,255,.13)!important;margin:14px 0!important;}
.bslib-sidebar-layout>.sidebar .btn{border:none!important;}
.bslib-sidebar-layout>.collapse-toggle{
  background:var(--dark)!important; border:none!important; color:#fff!important;
  border-radius:0 10px 10px 0!important;
}

/* ─ Buttons ──────────────────────────────────────────── */
.btn{
  border-radius:10px!important; font-weight:600!important;
  font-size:.83rem!important; letter-spacing:.02em!important;
  transition:var(--tr)!important; border:none!important;
  padding:9px 18px!important;
}
.btn:hover{filter:brightness(1.1);transform:translateY(-2px);box-shadow:0 6px 20px rgba(0,0,0,.2)!important;}
.btn:active{transform:translateY(0)!important;}
.btn-success {background:linear-gradient(135deg,#1A7A44,#27AE60)!important;color:#fff!important;}
.btn-primary {background:linear-gradient(135deg,var(--blue2),var(--blue))!important;color:#fff!important;}
.btn-info    {background:linear-gradient(135deg,var(--teal2),var(--teal))!important;color:#fff!important;}
.btn-warning {background:linear-gradient(135deg,#B8520A,var(--orange))!important;color:#fff!important;}
.btn-danger  {background:linear-gradient(135deg,var(--red2),var(--red))!important;color:#fff!important;}
.btn-outline-primary  {background:transparent!important;border:2px solid var(--blue)!important;color:var(--blue)!important;}
.btn-outline-primary:hover{background:var(--blue)!important;color:#fff!important;}
.btn-outline-secondary{background:transparent!important;border:2px solid var(--muted)!important;color:var(--muted)!important;}
.btn-outline-secondary:hover{background:var(--muted)!important;color:#fff!important;}
.btn-outline-success{background:transparent!important;border:2px solid var(--green)!important;color:var(--green)!important;}
.btn-outline-success:hover{background:var(--green)!important;color:#fff!important;}
.btn-lg{font-size:.92rem!important;padding:12px 22px!important;}

/* ─ DT Tables ────────────────────────────────────────── */
table.dataTable thead th{
  background:linear-gradient(135deg,var(--blue2),var(--blue))!important;
  color:#fff!important; font-weight:600!important; border:none!important;
  font-size:.74rem!important; letter-spacing:.05em!important;
  text-transform:uppercase!important; padding:13px 10px!important;
}
table.dataTable thead th:hover{background:linear-gradient(135deg,#002E4F,var(--blue2))!important;}
table.dataTable tbody tr:hover{background:rgba(0,92,151,.05)!important;}
table.dataTable tbody td{border-color:rgba(0,92,151,.05)!important;vertical-align:middle!important;}
.dataTables_wrapper .dataTables_filter input{border-radius:10px!important;border:1.5px solid rgba(0,92,151,.2)!important;padding:6px 12px!important;font-size:.83rem!important;}
.dataTables_wrapper .dataTables_length select{border-radius:8px!important;border:1.5px solid rgba(0,92,151,.2)!important;}

/* ─ Form inputs ──────────────────────────────────────── */
.form-select,.form-control{
  border-radius:10px!important; border:1.5px solid rgba(0,92,151,.18)!important;
  font-size:.85rem!important; transition:var(--tr)!important;
  color:var(--dark)!important;
}
.form-select:focus,.form-control:focus{border-color:var(--blue)!important;box-shadow:0 0 0 3px rgba(0,92,151,.13)!important;}

/* ─ Badges ───────────────────────────────────────────── */
.badge{border-radius:8px!important;font-weight:700!important;letter-spacing:.03em!important;}

/* ─ Pipeline step badges ─────────────────────────────── */
.step-pill{
  display:inline-flex;align-items:center;gap:8px;padding:8px 16px;
  border-radius:50px;font-size:.79rem;font-weight:700;margin:3px;
  transition:var(--tr); letter-spacing:.02em;
}
.step-done   {background:linear-gradient(135deg,#1A7A44,#27AE60);color:#fff;box-shadow:0 4px 14px rgba(39,174,96,.3);}
.step-pending{background:rgba(108,122,141,.12);color:var(--muted);border:1.5px dashed rgba(108,122,141,.3);}
.step-error  {background:linear-gradient(135deg,var(--red2),var(--red));color:#fff;}
@keyframes pulse-glow{
  0%  {box-shadow:0 0 0 0 rgba(0,201,200,.5);}
  70% {box-shadow:0 0 0 10px rgba(0,201,200,0);}
  100%{box-shadow:0 0 0 0 rgba(0,201,200,0);}
}
.step-running{
  background:linear-gradient(135deg,var(--teal2),var(--teal));color:#fff;
  animation:pulse-glow 1.6s ease infinite;
}

/* ─ Log viewer ───────────────────────────────────────── */
#log_pre,#rpt_console{
  background:#0D1117!important; color:#C9D1D9!important;
  border:1px solid rgba(201,209,217,.15)!important; border-radius:12px!important;
  font-family:'JetBrains Mono','Fira Code','Courier New',monospace!important;
  font-size:11.5px!important; line-height:1.65!important; padding:16px!important;
}

/* ─ Notifications ────────────────────────────────────── */
.shiny-notification{
  border-radius:14px!important; border:none!important;
  box-shadow:0 8px 32px rgba(0,0,0,.22)!important; font-weight:500!important;
}
.shiny-notification-message{background:linear-gradient(135deg,var(--blue2),var(--blue))!important;color:#fff!important;}
.shiny-notification-error  {background:linear-gradient(135deg,var(--red2),var(--red))!important;color:#fff!important;}
.shiny-notification-warning{background:linear-gradient(135deg,#B8520A,var(--orange))!important;color:#fff!important;}

/* ─ Section titles ───────────────────────────────────── */
.sec-title{font-size:1.2rem;font-weight:700;color:var(--dark);letter-spacing:-.01em;}
.sec-sub  {font-size:.82rem;color:var(--muted);margin-top:2px;}

/* ─ Info banner ──────────────────────────────────────── */
.info-banner{
  background:linear-gradient(135deg,rgba(0,92,151,.06),rgba(0,201,200,.06));
  border-left:4px solid var(--blue); border-radius:10px;
  padding:12px 18px; font-size:.82rem; color:var(--dark);
}

/* ─ Status dot ───────────────────────────────────────── */
@keyframes blink{0%,100%{opacity:1}50%{opacity:.3}}
.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px;vertical-align:middle;}
.dot-ok {background:var(--green);}
.dot-warn{background:var(--orange);animation:blink 1.4s ease infinite;}
.dot-err {background:var(--red);animation:blink 1s ease infinite;}
.dot-running{background:#fff;animation:blink 0.9s ease infinite;}
.dot-idle{background:#C9D1D9;border:1px solid rgba(0,0,0,.15);}

/* ─ Fade-in animation ────────────────────────────────── */
@keyframes fadeUp{from{opacity:0;transform:translateY(18px)}to{opacity:1;transform:none}}
.fade-up{animation:fadeUp .5s ease forwards;}
.d1{animation-delay:.05s;opacity:0;} .d2{animation-delay:.12s;opacity:0;}
.d3{animation-delay:.19s;opacity:0;} .d4{animation-delay:.26s;opacity:0;}
.d5{animation-delay:.33s;opacity:0;} .d6{animation-delay:.40s;opacity:0;}

/* ─ Misc ─────────────────────────────────────────────── */
.tab-content{padding-top:18px!important;}

/* ─ Download buttons (in card headers) ──────────────── */
.btn-dl{
  padding:3px 9px!important; font-size:.68rem!important; font-weight:600!important;
  border-radius:7px!important; background:transparent!important;
  border:1.5px solid rgba(0,92,151,.22)!important; color:var(--blue)!important;
  display:inline-flex!important; align-items:center!important; gap:4px!important;
  line-height:1.4!important; text-decoration:none!important;
  transition:var(--tr)!important; white-space:nowrap!important;
}
.btn-dl:hover{background:var(--blue)!important;color:#fff!important;
  border-color:var(--blue)!important;transform:none!important;
  box-shadow:0 2px 8px rgba(0,92,151,.22)!important;}
.btn-dl:active{transform:none!important;}

/* ─ Plotly modebar: always visible, styled ──────────── */
.modebar-container{opacity:1!important;display:flex!important;}
.modebar{background:rgba(255,255,255,.9)!important;border-radius:8px!important;
  box-shadow:0 2px 8px rgba(0,92,151,.12)!important;}
.modebar-btn svg{fill:var(--blue)!important;}
.modebar-btn:hover{background:rgba(0,92,151,.08)!important;border-radius:5px!important;}

.btn-dl-master{
  background:linear-gradient(135deg,var(--teal2),var(--teal))!important;
  color:#fff!important; border:none!important; border-radius:10px!important;
  font-size:.78rem!important; font-weight:700!important;
  padding:8px 14px!important; width:100%!important;
  display:flex!important; align-items:center!important;
  justify-content:center!important; gap:6px!important;
}
.btn-dl-master:hover{filter:brightness(1.08)!important;transform:translateY(-1px)!important;}

/* ─ Sidebar brand strip ──────────────────────────────── */
.sidebar-brand{
  background:rgba(255,255,255,.07);border-radius:13px;padding:13px 15px;
  margin-bottom:22px;display:flex;align-items:center;gap:11px;
  border:1px solid rgba(255,255,255,.10);
}
.sidebar-brand-icon{font-size:1.9rem;line-height:1;flex-shrink:0;}
.sidebar-brand-name{color:#fff;font-weight:800;font-size:.93rem;letter-spacing:-.01em;line-height:1.2;}
.sidebar-brand-sub{color:rgba(255,255,255,.36);font-size:.59rem;font-weight:700;
  letter-spacing:.11em;text-transform:uppercase;margin-top:2px;}

/* ─ Sidebar section dividers with icons ──────────────── */
.sidebar-sec{
  display:flex;align-items:center;gap:7px;
  color:rgba(255,255,255,.32)!important;font-size:.58rem!important;
  font-weight:800!important;letter-spacing:.13em!important;
  text-transform:uppercase!important;margin:18px 0 9px!important;
  padding-bottom:7px!important;border-bottom:1px solid rgba(255,255,255,.09)!important;
}

/* ─ Context hero banner ──────────────────────────────── */
.hero-ctx{
  background:linear-gradient(125deg,#002E4F 0%,#005C97 55%,#1369A8 100%);
  border-radius:16px;padding:18px 26px;color:#fff;margin-bottom:18px;
  box-shadow:0 10px 40px rgba(0,63,107,.28);position:relative;overflow:hidden;
}
.hero-ctx::before{
  content:'';position:absolute;top:-55px;right:-55px;
  width:210px;height:210px;border-radius:50%;background:rgba(255,255,255,.05);
  pointer-events:none;
}
.hero-ctx::after{
  content:'';position:absolute;bottom:-80px;right:120px;
  width:170px;height:170px;border-radius:50%;background:rgba(0,201,200,.07);
  pointer-events:none;
}
.hero-ctx-title{font-size:1.05rem;font-weight:800;letter-spacing:-.02em;line-height:1.2;}
.hero-ctx-sub  {font-size:.75rem;color:rgba(255,255,255,.62);margin-top:5px;font-weight:500;}
.hero-stats{display:flex;align-items:center;gap:0;}
.hero-stat{
  text-align:center;padding:0 20px;
  border-left:1px solid rgba(255,255,255,.15);
}
.hero-stat:first-child{border-left:none;}
.hero-stat-val{
  font-size:1.55rem;font-weight:900;
  font-variant-numeric:tabular-nums;letter-spacing:-.02em;
}
.hero-stat-lbl{
  font-size:.59rem;font-weight:700;text-transform:uppercase;
  letter-spacing:.09em;color:rgba(255,255,255,.52);margin-top:1px;
}

/* ─ Card header: colored top accent border ───────────── */
.card>.card-header{border-top:3px solid var(--blue)!important;}

/* ─ KPI value size boost ─────────────────────────────── */
.kpi-val{font-size:2.35rem!important;letter-spacing:-.02em!important;}

/* ─ KPI badge (target / benchmark tag) ──────────────── */
.kpi-badge{
  display:inline-flex;align-items:center;gap:3px;
  background:rgba(255,255,255,.20);border-radius:20px;
  padding:2px 9px 2px 7px;font-size:.62rem;font-weight:700;
  margin-top:7px;position:relative;z-index:1;
  letter-spacing:.01em;cursor:default;
}

/* ─ KPI progress bar (e.g. CV vs 90% target) ────────── */
.kpi-prog{
  background:rgba(255,255,255,.18);border-radius:6px;height:5px;
  margin-top:10px;overflow:hidden;position:relative;z-index:1;
}
.kpi-prog-fill{
  height:100%;border-radius:6px;
  background:rgba(255,255,255,.82);
  transition:width 1.4s cubic-bezier(.4,0,.2,1);
}

/* ─ 2024 KPI card redesign ───────────────────────────── */
.kpi2{
  border-radius:20px!important; padding:20px 22px 16px!important; color:#fff!important;
  position:relative!important; overflow:hidden!important; height:100%!important;
  min-height:148px!important;
  transition:transform .3s cubic-bezier(.4,0,.2,1),
             box-shadow .3s cubic-bezier(.4,0,.2,1)!important;
  box-shadow:0 4px 24px rgba(0,0,0,.18)!important;
  display:flex!important; flex-direction:column!important;
  justify-content:space-between!important;
}
.kpi2:hover{
  transform:translateY(-5px) scale(1.012)!important;
  box-shadow:0 16px 44px rgba(0,0,0,.26)!important;
}
/* decorative orbs */
.kpi2::before{
  content:''; position:absolute; top:-40px; right:-40px;
  width:140px; height:140px; border-radius:50%;
  background:rgba(255,255,255,.10); pointer-events:none;
}
.kpi2::after{
  content:''; position:absolute; bottom:-55px; left:-20px;
  width:120px; height:120px; border-radius:50%;
  background:rgba(0,0,0,.08); pointer-events:none;
}
/* icon chip */
.kpi2-chip{
  display:inline-flex; align-items:center; justify-content:center;
  width:40px; height:40px; border-radius:12px;
  background:rgba(255,255,255,.22); font-size:1.25rem; line-height:1;
  position:relative; z-index:1; flex-shrink:0;
  backdrop-filter:blur(4px); -webkit-backdrop-filter:blur(4px);
}
.kpi2-top{
  display:flex; align-items:flex-start;
  justify-content:space-between; position:relative; z-index:1;
}
.kpi2-trend{
  font-size:.65rem; font-weight:800; letter-spacing:.03em;
  background:rgba(255,255,255,.18); border-radius:20px;
  padding:3px 9px; backdrop-filter:blur(4px);
}
.kpi2-body{ position:relative; z-index:1; margin-top:10px; }
.kpi2-val{
  font-size:2.2rem; font-weight:900; line-height:1.05;
  letter-spacing:-.035em; font-variant-numeric:tabular-nums;
}
.kpi2-label{
  font-size:.67rem; font-weight:700; letter-spacing:.09em;
  text-transform:uppercase; opacity:.75; margin-top:2px;
}
/* thin progress strip at bottom */
.kpi2-bar{
  height:3px; border-radius:3px; background:rgba(255,255,255,.2);
  margin-top:14px; overflow:hidden; position:relative; z-index:1;
}
.kpi2-bar-fill{
  height:100%; border-radius:3px; background:rgba(255,255,255,.75);
  transition:width 1.6s cubic-bezier(.4,0,.2,1);
}
/* compact variant — used for the pinned top-of-dashboard KPI strip */
.kpi2-compact{
  border-radius:14px!important; padding:12px 14px 10px!important;
  min-height:96px!important;
}
.kpi2-compact .kpi2-chip{
  width:28px!important; height:28px!important; border-radius:8px!important;
  font-size:.9rem!important;
}
.kpi2-compact .kpi2-trend{ font-size:.55rem!important; padding:2px 7px!important; }
.kpi2-compact .kpi2-body{ margin-top:6px!important; }
.kpi2-compact .kpi2-val{ font-size:1.3rem!important; letter-spacing:-.02em!important; }
.kpi2-compact .kpi2-label{ font-size:.58rem!important; }
.kpi2-compact .kpi2-bar{ margin-top:8px!important; }

/* ─ Dot-grid page background ─────────────────────────── */
body::before{
  content:''; position:fixed; inset:0; z-index:-1; pointer-events:none;
  background-image:radial-gradient(circle, rgba(0,92,151,.09) 1px, transparent 1px);
  background-size:28px 28px;
}

/* ─ Page-level padding ───────────────────────────────── */
.tab-content>.tab-pane{ padding:4px 6px 24px!important; }

/* ─ Chart card: coloured left-bar accent ─────────────── */
.card-accent-blue  { border-left:4px solid var(--blue)!important;  }
.card-accent-teal  { border-left:4px solid var(--teal)!important;  }
.card-accent-green { border-left:4px solid var(--green)!important; }
.card-accent-orange{ border-left:4px solid var(--orange)!important;}
.card-accent-red   { border-left:4px solid var(--red)!important;   }
.card-accent-purple{ border-left:4px solid var(--purple)!important;}

/* ─ Metric change pill (↑ ↓ neutral) ─────────────────── */
.chg-up  { color:#27AE60; background:rgba(39,174,96,.1);  border-radius:20px; padding:2px 8px; font-size:.7rem; font-weight:700; }
.chg-dn  { color:#C0392B; background:rgba(192,57,43,.1);  border-radius:20px; padding:2px 8px; font-size:.7rem; font-weight:700; }
.chg-flat{ color:#6C7A8D; background:rgba(108,122,141,.1);border-radius:20px; padding:2px 8px; font-size:.7rem; font-weight:700; }

/* ─ Glassmorphism stat tile (for hero area) ──────────── */
.glass-tile{
  background:rgba(255,255,255,.08); border:1px solid rgba(255,255,255,.16);
  border-radius:14px; padding:12px 18px; text-align:center;
  backdrop-filter:blur(8px); -webkit-backdrop-filter:blur(8px);
}
.glass-tile-val{ font-size:1.6rem; font-weight:900; letter-spacing:-.025em; color:#fff; }
.glass-tile-lbl{ font-size:.6rem; font-weight:700; letter-spacing:.1em; text-transform:uppercase; color:rgba(255,255,255,.55); margin-top:2px; }

/* ─ Navbar shadow line ───────────────────────────────── */
.navbar::after{
  content:''; display:block; position:absolute; bottom:0; left:0; right:0;
  height:1px; background:linear-gradient(90deg,transparent,rgba(255,255,255,.15),transparent);
}
.navbar{ position:relative; }

/* ─ Number font in tables ────────────────────────────── */
table.dataTable tbody td{ font-variant-numeric:tabular-nums!important; }

/* ─ Empty-state placeholder ──────────────────────────── */
.empty-state{
  display:flex; flex-direction:column; align-items:center;
  justify-content:center; padding:48px 24px; color:var(--muted);
  gap:10px;
}
.empty-state-icon{ font-size:2.8rem; opacity:.4; }
.empty-state-txt { font-size:.85rem; font-weight:500; }

/* ─ Button ripple ────────────────────────────────────── */
@keyframes ripple{to{transform:scale(4);opacity:0;}}

/* ─ Smooth chart card entrance ───────────────────────── */
.card{ animation:fadeUp .4s ease both; }

/* ─ Value font for KPI cards ─────────────────────────── */
.kpi2-val{ font-family:'Inter',sans-serif; }

/* ─ AI Assistant floating widget ─────────────────────── */
.ai-fab{
  position:fixed; bottom:24px; right:24px; z-index:2000;
  width:56px; height:56px; border-radius:50%; border:none;
  background:linear-gradient(140deg,#003F6B 0%,#005C97 55%,#1A7BBF 100%);
  color:#fff; box-shadow:0 6px 20px rgba(0,0,0,.28);
  display:flex; align-items:center; justify-content:center;
  cursor:pointer; transition:transform .25s cubic-bezier(.4,0,.2,1), box-shadow .25s;
}
.ai-fab:hover{ transform:translateY(-3px) scale(1.06); box-shadow:0 10px 28px rgba(0,0,0,.36); }
.ai-panel{
  position:fixed; bottom:92px; right:24px; z-index:2000;
  width:min(400px, calc(100vw - 32px)); height:min(600px, calc(100vh - 140px));
  background:#fff; border-radius:18px; overflow:hidden;
  box-shadow:0 16px 48px rgba(0,0,0,.28);
  display:flex; flex-direction:column;
  opacity:0; transform:translateY(16px) scale(.97); pointer-events:none;
  transition:opacity .22s ease, transform .22s ease;
}
.ai-panel.open{ opacity:1; transform:translateY(0) scale(1); pointer-events:auto; }
.ai-panel-header{
  background:linear-gradient(140deg,#003F6B 0%,#005C97 100%); color:#fff;
  padding:12px 14px; display:flex; align-items:center; justify-content:space-between;
  flex-shrink:0; gap:10px;
}
.ai-panel-close{
  background:transparent; border:none; color:rgba(255,255,255,.8); cursor:pointer;
  padding:4px; border-radius:6px; display:flex; align-items:center; justify-content:center;
}
.ai-panel-close:hover{ background:rgba(255,255,255,.15); color:#fff; }
.ai-panel-body{ flex:1; overflow:auto; min-height:0; display:flex; flex-direction:column; }
"

# ── CUSTOM JS ─────────────────────────────────────────────────────────────────
JS <- "
// Animated counter
function countUp(elId, target, ms, isPercent) {
  var el = document.getElementById(elId); if (!el) return;
  var start = performance.now();
  function step(now) {
    var p = Math.min((now - start) / ms, 1);
    var e = p < .5 ? 2*p*p : -1+(4-2*p)*p;
    var v = e * target;
    el.textContent = isPercent ? v.toFixed(1)+'%' : Math.round(v).toLocaleString();
    if (p < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}
// Registering with Shiny has to wait until the Shiny JS bundle itself has
// actually loaded and run. This script tag lives in the page <head>, so on
// a slow connection (or once more scripts got added to <head> here) it can
// execute BEFORE Shiny's own script further down the page has - calling
// Shiny.addCustomMessageHandler() at that moment throws a Shiny-is-not-
// defined error and silently kills the REST of this script block too (a
// thrown error stops a script tag dead - everything after it, in this
// same tag, never runs). Poll briefly instead of assuming Shiny is ready.
function registerCountUpHandler() {
  if (window.Shiny && typeof Shiny.addCustomMessageHandler === 'function') {
    Shiny.addCustomMessageHandler('countUp', function(d) {
      setTimeout(function(){
        countUp(d.id, d.v, d.ms||1200, d.pct||false);
        // If this is a metric with a progress bar, animate the bar fill
        if (d.bar_max) {
          var pct = Math.min(d.v / d.bar_max * 100, 100);
          // find the kpi2-bar-fill inside the same kpi2 card
          var el = document.getElementById(d.id);
          if (el) {
            var card = el.closest('.kpi2');
            if (card) {
              var fill = card.querySelector('.kpi2-bar-fill');
              if (fill) setTimeout(function(){ fill.style.width = pct + '%'; }, 200);
            }
          }
        }
      }, d.delay||0);
    });
  } else {
    setTimeout(registerCountUpHandler, 30);
  }
}
registerCountUpHandler();

// ── Lightweight toast (never fails silently — always shows something) ────
function showToast(msg, isError) {
  var t = document.createElement('div');
  t.textContent = msg;
  t.style.cssText = 'position:fixed;top:20px;right:20px;z-index:99999;' +
    'background:' + (isError ? '#C0392B' : '#003A70') + ';color:#fff;' +
    'padding:10px 18px;border-radius:8px;font-family:Inter,sans-serif;' +
    'font-size:.82rem;font-weight:500;box-shadow:0 6px 24px rgba(0,0,0,.25);' +
    'max-width:360px;line-height:1.4;opacity:0;transition:opacity .25s ease;';
  document.body.appendChild(t);
  requestAnimationFrame(function(){ t.style.opacity = '1'; });
  var hideAfter = isError ? 7000 : 3000;
  setTimeout(function(){
    t.style.opacity = '0';
    setTimeout(function(){ t.remove(); }, 300);
  }, hideAfter);
}

// ── html2canvas loader with CDN fallbacks ─────────────────────────────────
// The <script> tag in <head> is the fast path; if it never loaded (blocked
// by a corporate proxy/firewall, slow network, etc.) this tries a couple of
// alternate CDNs before giving up — and either way the user always sees a
// toast, so the button is never silent.
var _h2cSources = [
  'https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js',
  'https://cdn.jsdelivr.net/npm/html2canvas@1.4.1/dist/html2canvas.min.js',
  'https://unpkg.com/html2canvas@1.4.1/dist/html2canvas.min.js'
];
function loadHtml2Canvas(cb) {
  if (typeof html2canvas !== 'undefined') { cb(true); return; }
  var i = 0;
  function tryNext() {
    if (i >= _h2cSources.length) { cb(false); return; }
    var s = document.createElement('script');
    s.src = _h2cSources[i++];
    s.onload = function() { cb(typeof html2canvas !== 'undefined'); };
    s.onerror = tryNext;
    document.head.appendChild(s);
  }
  tryNext();
}

// Export the Executive KPI Snapshot + headline KPI tiles as one PNG image
// (mirrors the camera icon plotly gives every chart, for a section that
// isn't a plotly widget)
function captureExecKPI() {
  var el = document.getElementById('exec_kpi_capture');
  if (!el) { showToast('Could not find the Executive Snapshot section on this page.', true); return; }

  showToast('Generating image…', false);

  loadHtml2Canvas(function(ok) {
    if (!ok) {
      showToast('Image export library could not load — your network/firewall may be blocking ' +
                'the CDN it needs. Use the CSV button instead, or check your internet connection.', true);
      return;
    }
    var btns = el.querySelectorAll('.btn, button');
    btns.forEach(function(b){ b.style.visibility = 'hidden'; });
    html2canvas(el, {backgroundColor: '#F0F4F8', scale: 2, useCORS: true}).then(function(canvas) {
      btns.forEach(function(b){ b.style.visibility = ''; });
      var link = document.createElement('a');
      var today = new Date().toISOString().slice(0,10);
      link.download = 'AFRO_IM_Executive_Snapshot_' + today + '.png';
      link.href = canvas.toDataURL('image/png');
      link.click();
      showToast('Image downloaded ✓', false);
    }).catch(function(err) {
      btns.forEach(function(b){ b.style.visibility = ''; });
      console.error('Executive snapshot capture failed:', err);
      showToast('Image export failed: ' + (err && err.message ? err.message : 'unknown error'), true);
    });
  });
}

// Auto-scroll logs
setInterval(function(){
  ['log_pre','rpt_console'].forEach(function(id){
    var el=document.getElementById(id); if(el) el.scrollTop=el.scrollHeight;
  });
}, 3500);

// Ripple effect on buttons
document.addEventListener('click', function(e){
  var btn = e.target.closest('.btn');
  if (!btn) return;
  var r = document.createElement('span');
  r.style.cssText='position:absolute;border-radius:50%;transform:scale(0);animation:ripple .5s linear;background:rgba(255,255,255,.3);pointer-events:none;';
  var rect = btn.getBoundingClientRect();
  var sz = Math.max(rect.width, rect.height);
  r.style.width = r.style.height = sz + 'px';
  r.style.left = (e.clientX - rect.left - sz/2) + 'px';
  r.style.top  = (e.clientY - rect.top  - sz/2) + 'px';
  btn.style.position='relative'; btn.style.overflow='hidden';
  btn.appendChild(r);
  setTimeout(function(){ r.remove(); }, 600);
});

// AI Assistant floating widget — pure client-side show/hide, no server
// round-trip needed just to open/close the panel.
function toggleAIAssistant(){
  var p = document.getElementById('ai_panel');
  if (!p) return;
  p.classList.toggle('open');
  if (p.classList.contains('open')) {
    var inputEl = document.getElementById('ai_chat_user_input');
    if (inputEl) setTimeout(function(){ inputEl.focus(); }, 250);
  }
}
// Bind the FAB/close-button clicks with addEventListener (not an inline
// onclick=, which some locked-down browser policies silently swallow) and
// re-parent the widget straight onto <body>. bslib nests page_navbar's
// footer inside a few wrapper divs; if any ancestor ever picks up a CSS
// transform/filter it would silently break `position:fixed` for everything
// inside it. Moving to <body> sidesteps that whole class of bug for good.
function wireAIAssistant(){
  var fab = document.getElementById('ai_fab');
  var panel = document.getElementById('ai_panel');
  if (panel && panel.parentNode !== document.body) document.body.appendChild(panel);
  if (fab && fab.parentNode !== document.body) document.body.appendChild(fab);
  if (fab) fab.addEventListener('click', toggleAIAssistant);
  if (panel) {
    var closeBtn = panel.querySelector('.ai-panel-close');
    if (closeBtn) closeBtn.addEventListener('click', toggleAIAssistant);
  }
}
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', wireAIAssistant);
} else {
  wireAIAssistant();
}
"
