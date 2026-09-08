// One place to update links. Every page reads this.
window.RUXP = {
  TESTFLIGHT_URL: "",                       // paste the public TestFlight link when it exists
  APP_STORE_URL: "",                        // paste the App Store link after approval
  CONTACT_EMAIL: "admin@ruxp.app",
  GITHUB_URL: "https://github.com/realworldbuilder/ruxp",
  // Every season the site knows about. `SEASON` below resolves to the one active today, so the
  // pages flip on their own at each player's local midnight. Mirrors SeasonCatalog in the app.
  SEASONS: [
    { code: "S00", name: "EARLY ADOPTERS", start: "2026-09-01", end: "2026-09-30" },
    { code: "S01", name: "NIGHTMARE MODE", start: "2026-10-01", end: "2026-11-30" },
    { code: "S02", name: "PRESS START",    start: "2026-12-01", end: "2027-02-28" }
  ]
};

// "now" can be pinned with ?at=2026-10-05 to preview a future state of the page.
window.RUXP.now = function () {
  var at = new RegExp("[?&]at=(\\d{4}-\\d{2}-\\d{2}(?:T\\d{2}:\\d{2})?)").exec(location.search);
  return at ? new Date(at[1].length === 10 ? at[1] + "T12:00:00" : at[1]) : new Date();
};
window.RUXP.seasonAt = function (d) {
  var list = window.RUXP.SEASONS, active = null, last = list[0];
  list.forEach(function (s) {
    var start = new Date(s.start + "T00:00:00"), end = new Date(s.end + "T23:59:59");
    if (d >= start && d <= end) active = s;
    if (d >= start) last = s;
  });
  return active || last;
};
window.RUXP.SEASON = window.RUXP.seasonAt(window.RUXP.now());

document.addEventListener("DOMContentLoaded", function () {
  var c = window.RUXP;
  document.querySelectorAll("[data-mailto]").forEach(function (a) {
    var subject = encodeURIComponent(a.getAttribute("data-mailto") || "RUXP");
    a.href = "mailto:" + c.CONTACT_EMAIL + "?subject=" + subject;
    if (a.hasAttribute("data-mailto-text")) a.textContent = c.CONTACT_EMAIL;
  });
  document.querySelectorAll("[data-github]").forEach(function (a) { a.href = c.GITHUB_URL; });
  document.querySelectorAll("[data-issues]").forEach(function (a) { a.href = c.GITHUB_URL + "/issues"; });
  // Access button: the App Store once it exists, else TestFlight, else a request-access email.
  document.querySelectorAll("[data-access]").forEach(function (a) {
    if (c.APP_STORE_URL) { a.href = c.APP_STORE_URL; a.textContent = "Get RUXP"; }
    else if (c.TESTFLIGHT_URL) { a.href = c.TESTFLIGHT_URL; a.textContent = "Enter"; }
    else { a.href = "mailto:" + c.CONTACT_EMAIL + "?subject=" + encodeURIComponent("RUXP access"); }
  });
  // Season text: "S01", "S01 · NIGHTMARE MODE", "11.30.26"
  var closes = c.SEASON.end.slice(5, 7) + "." + c.SEASON.end.slice(8, 10) + "." + c.SEASON.end.slice(2, 4);
  document.querySelectorAll("[data-season-code]").forEach(function (el) { el.textContent = c.SEASON.code; });
  document.querySelectorAll("[data-season-label]").forEach(function (el) { el.textContent = c.SEASON.code + " \u00b7 " + c.SEASON.name; });
  document.querySelectorAll("[data-window-closes]").forEach(function (el) { el.textContent = "WINDOW CLOSES " + closes; });
  if (document.body.classList.contains("sig-body")) document.title = c.SEASON.code;
  document.querySelectorAll("[data-appstore]").forEach(function (a) {
    if (c.APP_STORE_URL) { a.href = c.APP_STORE_URL; a.hidden = false; } else { a.hidden = true; }
  });
  // Countdown to the end of the season window (offset by the ?at= pin, if any).
  var end = new Date(c.SEASON.end + "T23:59:59"), skew = c.now() - new Date();
  function pad(n) { return (n < 10 ? "0" : "") + n; }
  function tick() {
    var ms = Math.max(0, end - new Date() - skew);
    var d = Math.floor(ms / 86400000), h = Math.floor(ms / 3600000) % 24, m = Math.floor(ms / 60000) % 60, s = Math.floor(ms / 1000) % 60;
    document.querySelectorAll("[data-countdown]").forEach(function (el) { el.textContent = d + ":" + pad(h) + ":" + pad(m) + ":" + pad(s); });
    document.querySelectorAll("[data-days-left]").forEach(function (el) { el.textContent = d; });
  }
  tick(); setInterval(tick, 1000);
});
