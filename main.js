document.addEventListener("DOMContentLoaded", () => {
  // --- Mobile Menu Interaction ---
  const burgerBtn = document.getElementById("burgerBtn");
  const mobileMenu = document.getElementById("mobileMenu");
  const mobileOverlay = document.getElementById("mobileOverlay");
  const mobileLinks = document.querySelectorAll(".mobile-link, .mobile-sign-in");

  function openMenu() {
    if (!burgerBtn || !mobileMenu || !mobileOverlay) return;
    burgerBtn.setAttribute("aria-expanded", "true");
    mobileMenu.removeAttribute("hidden");
    mobileOverlay.removeAttribute("hidden");
    document.body.classList.add("menu-open");
  }

  function closeMenu() {
    if (!burgerBtn || !mobileMenu || !mobileOverlay) return;
    burgerBtn.setAttribute("aria-expanded", "false");
    mobileMenu.setAttribute("hidden", "");
    mobileOverlay.setAttribute("hidden", "");
    document.body.classList.remove("menu-open");
  }

  function toggleMenu() {
    const isExpanded = burgerBtn?.getAttribute("aria-expanded") === "true";
    if (isExpanded) {
      closeMenu();
    } else {
      openMenu();
    }
  }

  if (burgerBtn) {
    burgerBtn.addEventListener("click", toggleMenu);
  }

  if (mobileOverlay) {
    mobileOverlay.addEventListener("click", closeMenu);
  }

  mobileLinks.forEach((link) => {
    link.addEventListener("click", () => {
      closeMenu();
    });
  });

  window.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && burgerBtn?.getAttribute("aria-expanded") === "true") {
      closeMenu();
    }
  });

  window.addEventListener("resize", () => {
    if (window.innerWidth > 720 && burgerBtn?.getAttribute("aria-expanded") === "true") {
      closeMenu();
    }
  });

  // --- Count-up Animation for Stats ---
  function easeOutCubic(t) {
    return 1 - Math.pow(1 - t, 3);
  }

  const statValues = document.querySelectorAll(".stat-value");
  let countersStarted = false;

  function runCounters() {
    if (countersStarted) return;
    countersStarted = true;

    statValues.forEach((el, index) => {
      const target = parseFloat(el.getAttribute("data-target")) || 0;
      const decimals = parseInt(el.getAttribute("data-decimals"), 10) || 0;
      const duration = 1500 + index * 80;
      const startOffset = 480 + index * 90;

      setTimeout(() => {
        let startTime = null;

        function step(timestamp) {
          if (!startTime) startTime = timestamp;
          const elapsed = timestamp - startTime;
          const progress = Math.min(elapsed / duration, 1);
          const eased = easeOutCubic(progress);
          const current = eased * target;

          el.textContent = current.toFixed(decimals);

          if (progress < 1) {
            requestAnimationFrame(step);
          } else {
            el.textContent = target.toFixed(decimals);
          }
        }

        requestAnimationFrame(step);
      }, startOffset);
    });
  }

  const statsFooter = document.querySelector(".stats-footer");
  if (statsFooter) {
    if ("IntersectionObserver" in window) {
      const observer = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (entry.isIntersecting) {
              runCounters();
              observer.unobserve(entry.target);
            }
          });
        },
        { threshold: 0.25 }
      );
      observer.observe(statsFooter);
    } else {
      runCounters();
    }
  }
});
