/* ==========================================================================
   Workout Notes: landing page behaviour
   Screenshot gallery filter + lightbox.
   ========================================================================== */

(function () {
  "use strict";

  var gallery = document.querySelector("[data-gallery]");
  if (!gallery) return;

  var tabs = Array.prototype.slice.call(
    gallery.querySelectorAll("[data-filter]")
  );
  var shots = Array.prototype.slice.call(
    gallery.querySelectorAll("[data-shot]")
  );

  /* ------------------------------------------------------------- filtering */

  function applyFilter(group) {
    shots.forEach(function (shot) {
      var match = group === "all" || shot.dataset.group === group;
      shot.hidden = !match;
    });
    tabs.forEach(function (tab) {
      var active = tab.dataset.filter === group;
      tab.classList.toggle("is-active", active);
      tab.setAttribute("aria-pressed", active ? "true" : "false");
    });
  }

  tabs.forEach(function (tab) {
    tab.addEventListener("click", function () {
      applyFilter(tab.dataset.filter);
    });
  });

  /* -------------------------------------------------------------- lightbox */

  var box = document.querySelector("[data-lightbox]");
  if (!box) return;

  var boxImg = box.querySelector("[data-lightbox-img]");
  var boxCaption = box.querySelector("[data-lightbox-caption]");
  var lastFocus = null;
  var index = 0;

  function visibleShots() {
    return shots.filter(function (shot) {
      return !shot.hidden;
    });
  }

  function show(i) {
    var list = visibleShots();
    if (!list.length) return;
    index = (i + list.length) % list.length;
    var shot = list[index];
    var img = shot.querySelector("img");
    boxImg.src = img.getAttribute("src");
    boxImg.alt = img.getAttribute("alt") || "";
    boxCaption.textContent = shot.dataset.caption || "";
  }

  function open(shot) {
    lastFocus = document.activeElement;
    index = visibleShots().indexOf(shot);
    show(index);
    box.classList.add("is-open");
    box.removeAttribute("aria-hidden");
    document.body.style.overflow = "hidden";
    var close = box.querySelector("[data-lightbox-close]");
    if (close) close.focus();
  }

  function close() {
    box.classList.remove("is-open");
    box.setAttribute("aria-hidden", "true");
    document.body.style.overflow = "";
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  shots.forEach(function (shot) {
    shot.addEventListener("click", function () {
      open(shot);
    });
  });

  box.addEventListener("click", function (event) {
    if (event.target.closest("[data-lightbox-close]")) return close();
    if (event.target.closest("[data-lightbox-prev]")) return show(index - 1);
    if (event.target.closest("[data-lightbox-next]")) return show(index + 1);
    if (!event.target.closest("[data-lightbox-figure]")) close();
  });

  window.addEventListener("keydown", function (event) {
    if (!box.classList.contains("is-open")) return;
    if (event.key === "Escape") close();
    if (event.key === "ArrowLeft") show(index - 1);
    if (event.key === "ArrowRight") show(index + 1);
  });
})();
