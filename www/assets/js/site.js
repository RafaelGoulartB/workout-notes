/* ==========================================================================
   Workout Notes: shared site behaviour
   Theme switch, sticky header state, mobile drawer, scroll reveal,
   GitHub star count. Loaded by every page.
   ========================================================================== */

(function () {
  "use strict";

  var root = document.documentElement;
  var STORE_KEY = "wn-theme";

  /* ---------------------------------------------------------------- theme */

  function currentTheme() {
    return root.getAttribute("data-theme") === "light" ? "light" : "dark";
  }

  function applyTheme(theme, persist) {
    root.setAttribute("data-theme", theme);
    if (persist) {
      try {
        localStorage.setItem(STORE_KEY, theme);
      } catch (e) {
        /* private mode, so the choice just won't survive a reload */
      }
    }
    document.querySelectorAll("[data-theme-toggle]").forEach(function (btn) {
      btn.setAttribute(
        "aria-label",
        theme === "light" ? "Switch to dark theme" : "Switch to light theme"
      );
      btn.setAttribute("aria-pressed", theme === "light" ? "true" : "false");
    });
  }

  applyTheme(currentTheme(), false);

  document.querySelectorAll("[data-theme-toggle]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      applyTheme(currentTheme() === "light" ? "dark" : "light", true);
    });
  });

  /* -------------------------------------------------------- sticky header */

  var header = document.querySelector("[data-header]");
  if (header) {
    var syncHeader = function () {
      header.classList.toggle("is-stuck", window.scrollY > 6);
    };
    syncHeader();
    window.addEventListener("scroll", syncHeader, { passive: true });
  }

  /* -------------------------------------------------------- mobile drawer */

  var navToggle = document.querySelector("[data-nav-toggle]");
  var mobileNav = document.getElementById("mobile-nav");
  if (navToggle && mobileNav) {
    var setNav = function (open) {
      mobileNav.classList.toggle("is-open", open);
      navToggle.setAttribute("aria-expanded", open ? "true" : "false");
      navToggle.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    };
    navToggle.addEventListener("click", function () {
      setNav(!mobileNav.classList.contains("is-open"));
    });
    mobileNav.addEventListener("click", function (event) {
      if (event.target.closest("a")) setNav(false);
    });
    window.addEventListener("keydown", function (event) {
      if (event.key === "Escape") setNav(false);
    });
  }

  /* --------------------------------------------------------- scroll reveal */

  var revealed = document.querySelectorAll("[data-reveal]");
  if (revealed.length) {
    revealed.forEach(function (el) {
      el.classList.add("reveal");
    });
    if ("IntersectionObserver" in window) {
      var io = new IntersectionObserver(
        function (entries) {
          entries.forEach(function (entry) {
            if (!entry.isIntersecting) return;
            entry.target.classList.add("is-in");
            io.unobserve(entry.target);
          });
        },
        { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
      );
      revealed.forEach(function (el) {
        io.observe(el);
      });
    } else {
      revealed.forEach(function (el) {
        el.classList.add("is-in");
      });
    }
  }

  /* ------------------------------------------------------- github stars */

  var starTargets = document.querySelectorAll("[data-stars]");
  if (starTargets.length) {
    var format = function (n) {
      if (typeof n !== "number" || !isFinite(n)) return null;
      if (n < 1000) return String(n);
      return (
        (n / 1000).toFixed(n >= 10000 ? 0 : 1).replace(/\.0$/, "") + "k"
      );
    };
    fetch("https://api.github.com/repos/RafaelGoulartB/workout-notes", {
      headers: { Accept: "application/vnd.github+json" },
    })
      .then(function (res) {
        return res.ok ? res.json() : null;
      })
      .then(function (data) {
        if (!data) return;
        var label = format(data.stargazers_count);
        if (!label) return;
        starTargets.forEach(function (el) {
          el.textContent = label;
        });
      })
      .catch(function () {
        /* offline or rate-limited, so keep the static fallback */
      });
  }

  /* --------------------------------------------------------- footer year */

  document.querySelectorAll("[data-year]").forEach(function (el) {
    el.textContent = String(new Date().getFullYear());
  });
})();
