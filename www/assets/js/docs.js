/* ==========================================================================
   Workout Notes: documentation behaviour
   Current-page highlight, sidebar filter + drawer, on-this-page TOC with
   scroll spy, heading anchors and previous/next pagination.
   The sidebar markup is identical on every page; everything page-specific
   below is derived from the current URL, so nothing has to be hand-synced.
   ========================================================================== */

(function () {
  "use strict";

  var sidebar = document.getElementById("docs-sidebar");
  var main = document.querySelector(".docs-main");
  var prose = document.querySelector(".prose");

  /* --------------------------------------------------- current page state */

  function fileName(href) {
    var path = href.split("#")[0].split("?")[0];
    var parts = path.split("/");
    var last = parts[parts.length - 1];
    return last === "" ? "index.html" : last;
  }

  var here = fileName(window.location.pathname);
  var navLinks = sidebar
    ? Array.prototype.slice.call(sidebar.querySelectorAll(".docs-nav a"))
    : [];

  var currentIndex = -1;
  navLinks.forEach(function (link, i) {
    if (fileName(link.getAttribute("href")) === here) {
      link.classList.add("is-current");
      link.setAttribute("aria-current", "page");
      currentIndex = i;
    }
  });

  /* ------------------------------------------------------- sidebar filter */

  var filter = document.querySelector("[data-docs-filter]");
  if (filter && sidebar) {
    var groups = Array.prototype.slice.call(
      sidebar.querySelectorAll(".docs-nav__group")
    );
    var lists = Array.prototype.slice.call(sidebar.querySelectorAll(".docs-nav ul"));

    var empty = document.createElement("p");
    empty.className = "docs-nav__empty";
    empty.textContent = "No page matches that.";
    empty.hidden = true;
    sidebar.querySelector(".docs-nav").appendChild(empty);

    var runFilter = function () {
      var term = filter.value.trim().toLowerCase();
      var hits = 0;

      lists.forEach(function (list, listIndex) {
        var listHits = 0;
        Array.prototype.slice.call(list.children).forEach(function (li) {
          var link = li.querySelector("a");
          if (!link) return;
          var haystack = (
            link.textContent +
            " " +
            (link.dataset.keywords || "")
          ).toLowerCase();
          var match = !term || haystack.indexOf(term) !== -1;
          li.hidden = !match;
          if (match) listHits++;
        });
        hits += listHits;
        list.hidden = listHits === 0;
        if (groups[listIndex]) groups[listIndex].hidden = listHits === 0;
      });

      empty.hidden = hits !== 0;
    };

    filter.addEventListener("input", runFilter);
    filter.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        filter.value = "";
        runFilter();
        filter.blur();
      }
      if (event.key === "Enter") {
        var first = sidebar.querySelector(".docs-nav li:not([hidden]) a");
        if (first) window.location.href = first.getAttribute("href");
      }
    });

    // "/" focuses the filter, like most documentation sites.
    window.addEventListener("keydown", function (event) {
      if (event.key !== "/" || event.metaKey || event.ctrlKey) return;
      var tag = (document.activeElement && document.activeElement.tagName) || "";
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      event.preventDefault();
      filter.focus();
      filter.select();
    });
  }

  /* ------------------------------------------------------ sidebar drawer */

  var sidebarToggle = document.querySelector("[data-sidebar-toggle]");
  var backdrop = document.querySelector("[data-docs-backdrop]");
  if (sidebarToggle && sidebar) {
    var setDrawer = function (open) {
      sidebar.classList.toggle("is-open", open);
      if (backdrop) backdrop.classList.toggle("is-open", open);
      sidebarToggle.setAttribute("aria-expanded", open ? "true" : "false");
      document.body.style.overflow = open ? "hidden" : "";
    };
    sidebarToggle.addEventListener("click", function () {
      setDrawer(!sidebar.classList.contains("is-open"));
    });
    if (backdrop) {
      backdrop.addEventListener("click", function () {
        setDrawer(false);
      });
    }
    sidebar.addEventListener("click", function (event) {
      if (event.target.closest("a")) setDrawer(false);
    });
    window.addEventListener("keydown", function (event) {
      if (event.key === "Escape") setDrawer(false);
    });
  }

  /* ---------------------------------------------- heading anchors + TOC */

  var tocList = document.querySelector("[data-toc]");
  var tocLinks = [];

  if (prose) {
    var slugify = function (text) {
      return text
        .toLowerCase()
        .replace(/[^\w\s-]/g, "")
        .trim()
        .replace(/\s+/g, "-");
    };

    var used = {};
    var headings = Array.prototype.slice.call(prose.querySelectorAll("h2, h3"));
    headings.forEach(function (heading) {
      if (!heading.id) {
        var base = slugify(heading.textContent) || "section";
        var id = base;
        var n = 2;
        while (used[id] || document.getElementById(id)) {
          id = base + "-" + n++;
        }
        heading.id = id;
      }
      used[heading.id] = true;

      var anchor = document.createElement("a");
      anchor.className = "anchor";
      anchor.href = "#" + heading.id;
      anchor.setAttribute("aria-label", "Link to this section");
      anchor.textContent = "#";
      heading.appendChild(anchor);
    });

    if (tocList) {
      if (!headings.length) {
        var toc = tocList.closest(".docs-toc");
        if (toc) toc.style.display = "none";
      }
      // On very long pages (an FAQ, for instance) a third-level entry per
      // question makes the rail unreadable, so only top-level sections listed.
      var tocHeadings =
        headings.length > 18
          ? headings.filter(function (h) {
              return h.tagName === "H2";
            })
          : headings;
      tocHeadings.forEach(function (heading) {
        var li = document.createElement("li");
        li.className = heading.tagName === "H3" ? "lvl-3" : "lvl-2";
        var a = document.createElement("a");
        a.href = "#" + heading.id;
        a.textContent = heading.textContent.replace(/#$/, "").trim();
        li.appendChild(a);
        tocList.appendChild(li);
        tocLinks.push({ link: a, heading: heading });
      });
    }

    /* scroll spy: pick the last heading that has passed the reading line */
    if (tocLinks.length) {
      var activeLink = null;
      var setActive = function (entry) {
        if (activeLink === entry) return;
        activeLink = entry;
        tocLinks.forEach(function (item) {
          item.link.classList.toggle("is-active", item === entry);
        });
      };

      var readingLine = 140;
      var scheduled = false;

      var syncSpy = function () {
        scheduled = false;
        var current = tocLinks[0];
        for (var i = 0; i < tocLinks.length; i++) {
          if (tocLinks[i].heading.getBoundingClientRect().top <= readingLine) {
            current = tocLinks[i];
          } else {
            break;
          }
        }
        // At the very bottom of the page, favour the final section.
        if (
          window.innerHeight + window.scrollY >=
          document.documentElement.scrollHeight - 4
        ) {
          current = tocLinks[tocLinks.length - 1];
        }
        setActive(current);
      };

      var requestSpy = function () {
        if (scheduled) return;
        scheduled = true;
        window.requestAnimationFrame(syncSpy);
      };

      syncSpy();
      window.addEventListener("scroll", requestSpy, { passive: true });
      window.addEventListener("resize", requestSpy);
    }
  }

  /* ------------------------------------------------------------- pager */

  var pager = document.querySelector("[data-pager]");
  if (pager && currentIndex !== -1) {
    var build = function (link, kind) {
      var a = document.createElement("a");
      a.href = link.getAttribute("href");
      a.className = kind === "next" ? "pager__next" : "pager__prev";
      var small = document.createElement("small");
      small.textContent = kind === "next" ? "Next" : "Previous";
      var strong = document.createElement("strong");
      strong.textContent = link.textContent.trim();
      a.appendChild(small);
      a.appendChild(strong);
      return a;
    };

    var prev = navLinks[currentIndex - 1];
    var next = navLinks[currentIndex + 1];

    if (prev) {
      pager.appendChild(build(prev, "prev"));
    } else {
      pager.appendChild(document.createElement("span"));
    }
    if (next) pager.appendChild(build(next, "next"));
  }

  /* -------------------------------------------- wrap wide tables safely */

  if (prose) {
    Array.prototype.slice
      .call(prose.querySelectorAll("table"))
      .forEach(function (table) {
        if (table.parentElement.classList.contains("table-scroll")) return;
        var wrap = document.createElement("div");
        wrap.className = "table-scroll";
        table.parentNode.insertBefore(wrap, table);
        wrap.appendChild(table);
      });
  }

  void main;
})();
