// One place to update links. Every page reads this.
window.RUXP = {
  TESTFLIGHT_URL: "",                       // paste the public TestFlight link when it exists
  APP_STORE_URL: "",                        // paste the App Store link after approval
  CONTACT_EMAIL: "admin@ruxp.app",
  GITHUB_URL: "https://github.com/realworldbuilder/ruxp",
  SEASON: { code: "S00", name: "EARLY ADOPTERS", start: "2026-09-01", end: "2026-11-30" }
};

document.addEventListener("DOMContentLoaded", function () {
  var c = window.RUXP;
  document.querySelectorAll("[data-mailto]").forEach(function (a) {
    var subject = encodeURIComponent(a.getAttribute("data-mailto") || "RUXP");
    a.href = "mailto:" + c.CONTACT_EMAIL + "?subject=" + subject;
    if (a.hasAttribute("data-mailto-text")) a.textContent = c.CONTACT_EMAIL;
  });
  document.querySelectorAll("[data-github]").forEach(function (a) { a.href = c.GITHUB_URL; });
  document.querySelectorAll("[data-issues]").forEach(function (a) { a.href = c.GITHUB_URL + "/issues"; });
  // Access button: TestFlight when the link exists, otherwise a request-access email.
  document.querySelectorAll("[data-access]").forEach(function (a) {
    if (c.TESTFLIGHT_URL) { a.href = c.TESTFLIGHT_URL; }
    else { a.href = "mailto:" + c.CONTACT_EMAIL + "?subject=" + encodeURIComponent("RUXP"); }
  });
  document.querySelectorAll("[data-appstore]").forEach(function (a) {
    if (c.APP_STORE_URL) { a.href = c.APP_STORE_URL; a.hidden = false; } else { a.hidden = true; }
  });
  // Countdown to the end of the season window.
  var end = new Date(c.SEASON.end + "T23:59:59");
  function pad(n) { return (n < 10 ? "0" : "") + n; }
  function tick() {
    var ms = Math.max(0, end - new Date());
    var d = Math.floor(ms / 86400000), h = Math.floor(ms / 3600000) % 24, m = Math.floor(ms / 60000) % 60, s = Math.floor(ms / 1000) % 60;
    document.querySelectorAll("[data-countdown]").forEach(function (el) { el.textContent = d + ":" + pad(h) + ":" + pad(m) + ":" + pad(s); });
    document.querySelectorAll("[data-days-left]").forEach(function (el) { el.textContent = d; });
  }
  tick(); setInterval(tick, 1000);
});
