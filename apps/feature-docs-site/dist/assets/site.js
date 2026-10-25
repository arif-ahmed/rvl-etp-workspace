/* GoBCB feature-docs site — theme + language toggles, mobile nav, mermaid rendering. */
(function () {
  "use strict";

  var doc = document;

  function store(key, value) {
    try { localStorage.setItem(key, value); } catch (e) { /* file:// or blocked */ }
  }
  function load(key) {
    try { return localStorage.getItem(key); } catch (e) { return null; }
  }

  /* ---------- theme ---------- */

  function currentTheme() {
    return doc.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "light";
  }

  /* ---------- mermaid ---------- */

  var mermaidEls = [];

  function renderMermaid() {
    if (!window.mermaid || !mermaidEls.length) return;
    window.mermaid.initialize({
      startOnLoad: false,
      securityLevel: "loose",
      theme: currentTheme() === "dark" ? "dark" : "default",
      fontFamily: getComputedStyle(doc.body).fontFamily
    });
    mermaidEls.forEach(function (el) {
      el.removeAttribute("data-processed");
      el.innerHTML = el.getAttribute("data-src");
    });
    window.mermaid.run({ nodes: mermaidEls }).catch(function (err) {
      console.error("mermaid render failed", err);
    });
  }

  mermaidEls = Array.prototype.slice.call(doc.querySelectorAll(".mermaid"));
  mermaidEls.forEach(function (el) {
    el.setAttribute("data-src", el.innerHTML); // keep the original diagram source
  });

  var themeBtn = doc.getElementById("themeToggle");
  if (themeBtn) {
    themeBtn.addEventListener("click", function () {
      var next = currentTheme() === "dark" ? "light" : "dark";
      doc.documentElement.setAttribute("data-theme", next);
      store("fd-theme", next);
      renderMermaid();
    });
  }

  /* ---------- language toggle ---------- */

  var langBtn = doc.getElementById("langToggle");
  if (langBtn) {
    langBtn.addEventListener("click", function () {
      var match = location.pathname.match(/\/(en|bn)\//);
      if (!match) return;
      var other = match[1] === "en" ? "bn" : "en";
      store("fd-lang", other);
      location.href = location.pathname.replace(/\/(en|bn)\//, "/" + other + "/") + location.hash;
    });
  }

  /* ---------- mobile sidebar ---------- */

  var menuBtn = doc.getElementById("menuToggle");
  var sidebar = doc.getElementById("sidebar");
  if (menuBtn && sidebar) {
    menuBtn.addEventListener("click", function () {
      doc.body.classList.toggle("sidebar-open");
    });
    sidebar.addEventListener("click", function (e) {
      if (e.target.closest("a")) doc.body.classList.remove("sidebar-open");
    });
  }

  /* ---------- sidebar section groups (collapsible, persisted) ---------- */

  (function () {
    var KEY = "fd-side";
    var saved = {};
    try { saved = JSON.parse(load(KEY) || "{}"); } catch (e) { /* corrupted state */ }

    function setOpen(sec, open) {
      sec.classList.toggle("is-open", open);
      var head = sec.querySelector(".side-sec-head");
      if (head) head.setAttribute("aria-expanded", open ? "true" : "false");
    }

    var secs = Array.prototype.slice.call(doc.querySelectorAll(".side-sec"));
    secs.forEach(function (sec) {
      var dir = sec.getAttribute("data-dir");
      if (Object.prototype.hasOwnProperty.call(saved, dir)) {
        setOpen(sec, !!saved[dir]); // user's own choice beats the page default
      }
      var head = sec.querySelector(".side-sec-head");
      if (head) {
        head.addEventListener("click", function () {
          setOpen(sec, !sec.classList.contains("is-open"));
          var out = {};
          secs.forEach(function (s) { out[s.getAttribute("data-dir")] = s.classList.contains("is-open"); });
          store(KEY, JSON.stringify(out));
        });
      }
    });

    /* keep the active feature visible without jumping the page itself */
    var activeItem = doc.querySelector(".side-item.is-active");
    if (activeItem && sidebar) {
      sidebar.scrollTop = activeItem.offsetTop - sidebar.clientHeight / 2;
    }
  })();

  /* ---------- heading anchor links ---------- */

  Array.prototype.forEach.call(
    doc.querySelectorAll(".content h2[id], .content h3[id]"),
    function (h) {
      var a = doc.createElement("a");
      a.className = "hlink";
      a.href = "#" + h.id;
      a.textContent = "#";
      h.appendChild(a);
    }
  );

  /* ---------- initial mermaid paint ---------- */

  renderMermaid();
})();
