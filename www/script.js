/* ============================================================
   Workout Notes — landing page interactions
   ============================================================ */

(() => {
  // -------- sticky nav: add border once user scrolls --------
  const nav = document.getElementById("nav");
  if (nav) {
    const onScroll = () => {
      nav.classList.toggle("is-scrolled", window.scrollY > 8);
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  }

  // -------- mobile menu toggle --------
  const menuBtn = document.getElementById("menuBtn");
  const mobileMenu = document.getElementById("mobileMenu");
  if (menuBtn && mobileMenu) {
    menuBtn.addEventListener("click", () => {
      const isOpen = !mobileMenu.classList.contains("hidden");
      mobileMenu.classList.toggle("hidden", isOpen);
      menuBtn.setAttribute(
        "aria-label",
        isOpen ? "Open menu" : "Close menu"
      );
    });
    // close menu when a link is clicked
    mobileMenu.querySelectorAll("a").forEach((a) => {
      a.addEventListener("click", () => {
        mobileMenu.classList.add("hidden");
        menuBtn.setAttribute("aria-label", "Open menu");
      });
    });
  }

  // -------- reveal on scroll --------
  const revealTargets = document.querySelectorAll("section h2, section h3");
  revealTargets.forEach((el) => el.classList.add("reveal"));

  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.15, rootMargin: "0px 0px -10% 0px" }
    );
    revealTargets.forEach((el) => io.observe(el));
  } else {
    revealTargets.forEach((el) => el.classList.add("is-visible"));
  }

  // -------- smooth-scroll for in-page anchors --------
  document.querySelectorAll('a[href^="#"]').forEach((a) => {
    a.addEventListener("click", (e) => {
      const id = a.getAttribute("href");
      if (!id || id === "#") return;
      const target = document.querySelector(id);
      if (!target) return;
      e.preventDefault();
      target.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  });

  // -------- GitHub star count --------
  // Fetches live stargazers_count from the GitHub API and updates the
  // pill next to the nav button. Falls back silently to the SSR value
  // ("1") if the request fails or is rate-limited.
  const formatCount = (n) => {
    if (typeof n !== "number" || !isFinite(n)) return null;
    if (n >= 1000) return (n / 1000).toFixed(n >= 10000 ? 0 : 1).replace(/\.0$/, "") + "k";
    return String(n);
  };

  const applyStars = (n) => {
    const formatted = formatCount(n) ?? "1";
    const desktop = document.getElementById("starCount");
    const mobile = document.getElementById("starCountMobile");
    if (desktop) desktop.textContent = "★ " + formatted;
    if (mobile) mobile.textContent = formatted;
  };

  fetch("https://api.github.com/repos/RafaelGoulartB/workout-notes", {
    headers: { Accept: "application/vnd.github+json" },
  })
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => {
      if (data && typeof data.stargazers_count === "number") {
        applyStars(data.stargazers_count);
      }
    })
    .catch(() => {});
})();
