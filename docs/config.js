// One place to update links. Every page reads this.
window.RUXP = {
  TESTFLIGHT_URL: "",                       // paste the public TestFlight link when it exists
  APP_STORE_URL: "",                        // paste the App Store link after approval
  CONTACT_EMAIL: "admin@ruxp.app",
  GITHUB_URL: "https://github.com/realworldbuilder/ruxp",
  SEASON: { code: "S00", name: "EARLY ADOPTERS", start: "2026-09-01", end: "2026-11-30", goal: 32 }
};

document.addEventListener("DOMContentLoaded", function () {
  var c = window.RUXP;
  var subject = encodeURIComponent("RUXP Season 0");
  document.querySelectorAll("[data-mailto]").forEach(function (a) {
    a.href = "mailto:" + c.CONTACT_EMAIL + "?subject=" + subject;
    if (a.hasAttribute("data-mailto-text")) a.textContent = c.CONTACT_EMAIL;
  });
  document.querySelectorAll("[data-github]").forEach(function (a) { a.href = c.GITHUB_URL; });
  document.querySelectorAll("[data-issues]").forEach(function (a) { a.href = c.GITHUB_URL + "/issues"; });
  document.querySelectorAll("[data-testflight]").forEach(function (a) {
    if (c.TESTFLIGHT_URL) { a.href = c.TESTFLIGHT_URL; a.classList.remove("is-pending"); }
    else { a.removeAttribute("href"); a.classList.add("is-pending"); a.textContent = "TestFlight link coming soon"; }
  });
  document.querySelectorAll("[data-appstore]").forEach(function (a) {
    if (c.APP_STORE_URL) { a.href = c.APP_STORE_URL; a.hidden = false; } else { a.hidden = true; }
  });
  var end = new Date(c.SEASON.end + "T23:59:59");
  var days = Math.max(0, Math.ceil((end - new Date()) / 86400000));
  document.querySelectorAll("[data-days-left]").forEach(function (el) { el.textContent = days; });
});
