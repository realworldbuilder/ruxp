// Knowledge base chrome: sidebar, active page, live season strip. No frameworks.
(function () {
  var pages = [
    { g: "Start here" },
    { id: "index", t: "Where we are", h: "index.html" },
    { id: "philosophy", t: "The philosophy", h: "philosophy.html" },
    { id: "screens", t: "Screen tour", h: "screens.html" },
    { g: "How it works" },
    { id: "systems", t: "Systems", h: "systems.html" },
    { id: "data", t: "Data & Game Center", h: "data.html" },
    { g: "Running it" },
    { id: "ops", t: "Runbooks", h: "ops.html" },
    { id: "roadmap", t: "Roadmap & debt", h: "roadmap.html" }
  ];
  var current = document.body.getAttribute("data-page") || "index";
  var side = document.createElement("aside");
  side.className = "side";
  var html = '<div class="brand"><img src="../assets/logo-96.png" alt=""><span class="wordmark" data-text="RUXP">RUXP</span></div>' +
    '<p class="sub">KNOWLEDGE BASE</p><nav>';
  pages.forEach(function (p) {
    if (p.g) { html += '<div class="group">' + p.g + '</div>'; return; }
    html += '<a href="' + p.h + '"' + (p.id === current ? ' class="active"' : '') + '>' + p.t + '</a>';
  });
  html += '</nav><div class="foot">Open source, MIT.<br><a href="https://github.com/realworldbuilder/ruxp">github.com/realworldbuilder/ruxp</a><br><a href="../">Signal page</a> · <a href="https://github.com/realworldbuilder/ruxp/blob/main/CLAUDE.md">CLAUDE.md</a></div>';
  side.innerHTML = html;
  var layout = document.querySelector(".layout");
  layout.insertBefore(side, layout.firstChild);

  var btn = document.createElement("button");
  btn.className = "menu-btn"; btn.type = "button"; btn.textContent = "☰ Menu";
  btn.addEventListener("click", function () { document.body.classList.toggle("nav-open"); });
  var main = document.querySelector("main");
  main.parentNode.insertBefore(btn, main);
  document.addEventListener("click", function (e) {
    if (document.body.classList.contains("nav-open") && !side.contains(e.target) && e.target !== btn) document.body.classList.remove("nav-open");
  });

  // Prev / next
  var flat = pages.filter(function (p) { return !p.g; });
  var i = flat.findIndex(function (p) { return p.id === current; });
  if (i >= 0) {
    var nav = document.createElement("div"); nav.className = "next";
    nav.innerHTML = (i > 0 ? '<a href="' + flat[i - 1].h + '">← ' + flat[i - 1].t + '</a>' : '<span></span>') +
      (i < flat.length - 1 ? '<a href="' + flat[i + 1].h + '">' + flat[i + 1].t + ' →</a>' : '<span></span>');
    main.appendChild(nav);
  }

  // Live season strip (mirrors Shared/RUXP/Season.swift and LiveEvents.swift; local time like the app).
  var strip = document.getElementById("live-strip");
  if (strip) {
    var seasons = [
      { code: "S00", name: "EARLY ADOPTERS", start: new Date(2026, 8, 1), end: new Date(2026, 11, 1) },
      { code: "S01", name: "PRESS START", start: new Date(2026, 11, 1), end: new Date(2027, 2, 1) }
    ];
    function tick() {
      var now = new Date();
      var s = seasons.find(function (x) { return now >= x.start && now < x.end; }) || seasons[seasons.length - 1];
      var daysLeft = Math.max(0, Math.floor((s.end - now) / 86400000));
      // next FRIDAY NIGHT (Fri 17:00) or SUNDAY RESET (Sun 00:00)
      var fri = new Date(now); fri.setDate(now.getDate() + ((5 - now.getDay() + 7) % 7)); fri.setHours(17, 0, 0, 0);
      if (fri <= now) { if (now.getDay() === 5) { fri = null; } else { fri.setDate(fri.getDate() + 7); } }
      var sun = new Date(now); sun.setDate(now.getDate() + ((7 - now.getDay()) % 7)); sun.setHours(0, 0, 0, 0);
      if (now.getDay() === 0) sun = null;
      var live = fri === null ? "FRIDAY NIGHT LIVE" : (sun === null ? "SUNDAY RESET LIVE" : null);
      var next = live || (function () { var n = [fri, sun].filter(Boolean).sort(function (a, b) { return a - b; })[0]; var ms = n - now; var d = Math.floor(ms / 86400000), h = Math.floor(ms % 86400000 / 3600000); return (n === fri ? "FRIDAY NIGHT" : "SUNDAY RESET") + " IN " + (d > 0 ? d + "D " : "") + h + "H"; })();
      var day = now.toLocaleDateString(undefined, { weekday: "short" }).toUpperCase();
      var time = now.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" }).toUpperCase();
      strip.textContent = day + " " + time + " · " + next + " · " + s.code + (daysLeft === 0 ? " ENDS TODAY" : " ENDS IN " + daysLeft + "D");
      var el = document.getElementById("season-code"); if (el) el.textContent = s.code + " · " + s.name;
      var dl = document.getElementById("days-left"); if (dl) dl.textContent = daysLeft + " days";
    }
    tick(); setInterval(tick, 20000);
  }
})();
