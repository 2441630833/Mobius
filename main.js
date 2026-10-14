document.addEventListener("DOMContentLoaded", () => {
  // 1. i18n Dictionary & Language Engine
  const I18N = {
    zh: {
      docTitle: "Mobius — 会自我进化的智能体开发环境",
      docDescription: "会自我进化的智能体开发环境 (ADE)。Mobius 沉淀经验为可复用技能，能力随使用持续累积。下载适用于 Windows、macOS 与 Linux 的 Mobius 桌面端。",
      badgeText: "会自我进化的智能体开发环境 (ADE)",
      tagline: "会自我进化的智能体开发环境。越用越聪明的 AI 编程伙伴。",
      navFastInstall: "一键安装",
      navDownloads: "桌面下载",
      navReleases: "版本发布",
      navAbout: "关于项目",
      copyText: "复制",
      copiedText: "已复制",
      quickNote: "全新安装或本地已安装版本原位一键同步更新",
      macGuideTrigger: "macOS 提示“无法打开”？3 秒放行指南",
      modalTitle: "macOS 首次打开放行指南",
      modalIntro: "由于 Mobius 为免费开源软件，尚未向 Apple 购买高额年费公证证书。从浏览器下载后首次打开若提示 <em>“无法验证是否包含恶意软件”</em> 属于 macOS Gatekeeper 正常拦截，只需运行一行命令即可彻底解除：",
      modalMethodBadge: "一步解除 · 永久生效",
      modalStep: "将 Mobius 拖入「应用程序」后，打开 Mac「终端 (Terminal)」并运行：",
      modalHint: "输入 Mac 锁屏开机密码后回车即可（输入密码时屏幕不会显示字符，直接输完回车）。之后双击 Mobius 图标直接秒开，永久不再拦截！",
      modalDone: "我知道了",
      langSwitchText: "English",
      mobileLangText: "Switch to English",
      winBtnTitle: "下载 Mobius Windows 版 (x64 安装包)",
      macBtnTitle: "下载 Mobius macOS 版 (Apple Silicon DMG)",
      linuxBtnTitle: "下载 Mobius Linux 版 (Debian / Ubuntu .deb)"
    },
    en: {
      docTitle: "Mobius — A Self-Evolving Agentic Development Environment",
      docDescription: "A self-evolving agentic development environment (ADE) that gets smarter the more you use it. Download Mobius desktop for Windows, macOS, and Linux.",
      badgeText: "Self-Evolving Agentic Development Environment (ADE)",
      tagline: "A self-evolving agentic development environment. The AI coding partner that gets smarter the more you use it.",
      navFastInstall: "Fast Install",
      navDownloads: "Downloads",
      navReleases: "Releases",
      navAbout: "About",
      copyText: "Copy",
      copiedText: "Copied",
      quickNote: "Fresh install or automatic in-place sync-update for existing installs",
      macGuideTrigger: 'macOS says "cannot be opened"? 3-second quick unblock guide',
      modalTitle: "macOS First-Launch Unblock Guide",
      modalIntro: "Because Mobius is free and open-source software without an expensive annual Apple notary certificate, macOS Gatekeeper may intercept it on first launch. Run this single command to permanently unblock it:",
      modalMethodBadge: "One Step · Permanently Effective",
      modalStep: "Drag Mobius into Applications, then open Terminal and run:",
      modalHint: "Enter your Mac lock-screen password and press Enter (characters will not show while typing). Mobius will open immediately without Gatekeeper prompts!",
      modalDone: "Got It",
      langSwitchText: "中文",
      mobileLangText: "切换为中文",
      winBtnTitle: "Download Mobius for Windows (x64 Installer)",
      macBtnTitle: "Download Mobius for macOS (Apple Silicon DMG)",
      linuxBtnTitle: "Download Mobius for Linux (Debian / Ubuntu .deb)"
    }
  };

  let currentLang = (() => {
    try {
      const saved = localStorage.getItem("mobius_lang");
      if (saved === "en" || saved === "zh") return saved;
    } catch (e) {}
    const navLang = (navigator.language || navigator.userLanguage || "zh").toLowerCase();
    return navLang.startsWith("zh") ? "zh" : "en";
  })();

  function applyLanguage(lang) {
    if (!I18N[lang]) lang = "zh";
    currentLang = lang;
    document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";
    const dict = I18N[lang];

    if (dict.docTitle) document.title = dict.docTitle;
    const metaDesc = document.querySelector('meta[name="description"]');
    if (metaDesc && dict.docDescription) metaDesc.setAttribute("content", dict.docDescription);

    document.querySelectorAll("[data-i18n]").forEach((el) => {
      const key = el.getAttribute("data-i18n");
      if (dict[key] !== undefined) el.textContent = dict[key];
    });

    document.querySelectorAll("[data-i18n-html]").forEach((el) => {
      const key = el.getAttribute("data-i18n-html");
      if (dict[key] !== undefined) el.innerHTML = dict[key];
    });

    const langBtn = document.getElementById("langSwitchBtn");
    if (langBtn) langBtn.textContent = dict.langSwitchText;

    const mobileLangBtn = document.getElementById("mobileLangBtn");
    if (mobileLangBtn) mobileLangBtn.textContent = dict.mobileLangText;
  }

  applyLanguage(currentLang);

  function toggleLanguage() {
    const nextLang = currentLang === "zh" ? "en" : "zh";
    try {
      localStorage.setItem("mobius_lang", nextLang);
    } catch (e) {}
    applyLanguage(nextLang);
  }

  const langBtn = document.getElementById("langSwitchBtn");
  if (langBtn) langBtn.addEventListener("click", toggleLanguage);

  const mobileLangBtn = document.getElementById("mobileLangBtn");
  if (mobileLangBtn) mobileLangBtn.addEventListener("click", toggleLanguage);

  // 2. Terminal Fast-Installer Tab Switcher
  const commands = {
    mac: "curl -fsSL https://raw.githubusercontent.com/2441630833/Mobius/main/scripts/install-mac.sh | bash",
    win: "irm https://raw.githubusercontent.com/2441630833/Mobius/main/scripts/install-win.ps1 | iex",
    linux: "curl -fsSL https://raw.githubusercontent.com/2441630833/Mobius/main/scripts/install-linux.sh | bash"
  };

  const prompts = {
    mac: "$",
    win: "PS >",
    linux: "$"
  };

  const tabs = document.querySelectorAll(".quick-tab-btn");
  const cmdEl = document.getElementById("installCmd");
  const promptEl = document.getElementById("installPrompt");
  const macGuideBtn = document.getElementById("openMacGuide");

  let currentOs = "mac";

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      tabs.forEach((t) => {
        t.classList.remove("active");
        t.setAttribute("aria-selected", "false");
      });
      tab.classList.add("active");
      tab.setAttribute("aria-selected", "true");

      currentOs = tab.getAttribute("data-os") || "mac";
      if (cmdEl && commands[currentOs]) {
        cmdEl.textContent = commands[currentOs];
      }
      if (promptEl && prompts[currentOs]) {
        promptEl.textContent = prompts[currentOs];
      }
      if (macGuideBtn) {
        macGuideBtn.style.display = currentOs === "mac" ? "inline-flex" : "none";
      }
    });
  });

  // 3. Clipboard Copy Functionality
  function fallbackCopy(text, btn) {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();
    try {
      document.execCommand("copy");
      showCopied(btn);
    } catch (e) {}
    document.body.removeChild(textarea);
  }

  function showCopied(btn) {
    if (!btn) return;
    const textEl = btn.querySelector(".copy-btn-text, .copy-inline-text");
    const originalText = textEl ? textEl.textContent : "";
    btn.classList.add("copied");
    if (textEl) {
      textEl.textContent = I18N[currentLang]?.copiedText || "Copied";
    }
    setTimeout(() => {
      btn.classList.remove("copied");
      if (textEl) {
        textEl.textContent = originalText;
      }
    }, 2000);
  }

  function copyText(text, btn) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(() => {
        showCopied(btn);
      }).catch(() => {
        fallbackCopy(text, btn);
      });
    } else {
      fallbackCopy(text, btn);
    }
  }

  const copyInstallBtn = document.getElementById("copyInstallBtn");
  if (copyInstallBtn && cmdEl) {
    copyInstallBtn.addEventListener("click", () => {
      copyText(cmdEl.textContent.trim(), copyInstallBtn);
    });
  }

  document.querySelectorAll(".copy-inline-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      const textToCopy = btn.getAttribute("data-copy") || "";
      if (textToCopy) copyText(textToCopy, btn);
    });
  });

  // 4. macOS Security / Gatekeeper Guide Dialog
  const macModal = document.getElementById("macGuideModal");
  const openMacBtn = document.getElementById("openMacGuide");
  const closeMacBtn = document.getElementById("closeMacGuide");
  const doneMacBtn = document.getElementById("doneMacGuide");

  function openModal() {
    if (macModal) {
      if (typeof macModal.showModal === "function") {
        macModal.showModal();
      } else {
        macModal.setAttribute("open", "");
      }
    }
  }

  function closeModal() {
    if (macModal) {
      if (typeof macModal.close === "function") {
        macModal.close();
      } else {
        macModal.removeAttribute("open");
      }
    }
  }

  if (openMacBtn) openMacBtn.addEventListener("click", openModal);
  if (closeMacBtn) closeMacBtn.addEventListener("click", closeModal);
  if (doneMacBtn) doneMacBtn.addEventListener("click", closeModal);

  if (macModal) {
    macModal.addEventListener("click", (e) => {
      if (e.target === macModal) closeModal();
    });
  }

  // 5. Dynamic Auto-Update for Mobius Desktop Downloads
  (() => {
    const apiUrl = "https://api.github.com/repos/2441630833/Mobius/releases";

    fetch(apiUrl, { headers: { Accept: "application/vnd.github.v3+json" } })
      .then((res) => {
        if (!res.ok) throw new Error("Status " + res.status);
        return res.json();
      })
      .then((releases) => {
        if (!Array.isArray(releases) || releases.length === 0) return;

        let winAsset = null;
        let macAsset = null;
        let linuxAsset = null;

        for (let i = 0; i < releases.length; i++) {
          const rel = releases[i];
          const assets = rel.assets || [];

          for (let j = 0; j < assets.length; j++) {
            const a = assets[j];
            const name = (a.name || "").toLowerCase();

            if (!winAsset && name.endsWith(".exe")) {
              winAsset = { url: a.browser_download_url, name: a.name, tag: rel.tag_name };
            }
            if (name.endsWith(".dmg")) {
              macAsset = { url: a.browser_download_url, name: a.name, tag: rel.tag_name };
            } else if (!macAsset && name.endsWith(".zip") && (name.includes("darwin") || name.includes("macos") || name.includes("mac"))) {
              macAsset = { url: a.browser_download_url, name: a.name, tag: rel.tag_name };
            }
            if (name.endsWith(".deb")) {
              linuxAsset = { url: a.browser_download_url, name: a.name, tag: rel.tag_name };
            } else if (!linuxAsset && name.endsWith(".tar.gz") && name.includes("linux")) {
              linuxAsset = { url: a.browser_download_url, name: a.name, tag: rel.tag_name };
            }
          }

          if (winAsset && macAsset && linuxAsset) break;
        }

        const winBtn = document.querySelector(".download-btn--win");
        if (winBtn && winAsset) {
          winBtn.href = winAsset.url;
          winBtn.title = (currentLang === "zh" ? "下载 Mobius Windows 版" : "Download Mobius for Windows") + " (" + (winAsset.tag ? winAsset.tag + " · " : "") + winAsset.name + ")";
        }

        const macBtn = document.querySelector(".download-btn--mac");
        if (macBtn && macAsset) {
          macBtn.href = macAsset.url;
          macBtn.title = (currentLang === "zh" ? "下载 Mobius macOS 版" : "Download Mobius for macOS") + " (" + (macAsset.tag ? macAsset.tag + " · " : "") + macAsset.name + ")";
        }

        const linuxBtn = document.querySelector(".download-btn--linux");
        if (linuxBtn && linuxAsset) {
          linuxBtn.href = linuxAsset.url;
          linuxBtn.title = (currentLang === "zh" ? "下载 Mobius Linux 版" : "Download Mobius for Linux") + " (" + (linuxAsset.tag ? linuxAsset.tag + " · " : "") + linuxAsset.name + ")";
        }
      })
      .catch(() => {
        // Fallback safely to pre-configured static URLs
      });
  })();

  // 6. Mobile Menu Controls
  const burgerBtn = document.getElementById("burgerBtn");
  const mobileMenu = document.getElementById("mobileMenu");
  const mobileOverlay = document.getElementById("mobileOverlay");
  const mobileLinks = document.querySelectorAll(".mobile-link, .mobile-sign-in");

  function openMobileMenu() {
    if (!burgerBtn || !mobileMenu || !mobileOverlay) return;
    burgerBtn.setAttribute("aria-expanded", "true");
    mobileMenu.removeAttribute("hidden");
    mobileOverlay.removeAttribute("hidden");
    document.body.classList.add("menu-open");
  }

  function closeMobileMenu() {
    if (!burgerBtn || !mobileMenu || !mobileOverlay) return;
    burgerBtn.setAttribute("aria-expanded", "false");
    mobileMenu.setAttribute("hidden", "");
    mobileOverlay.setAttribute("hidden", "");
    document.body.classList.remove("menu-open");
  }

  function toggleMobileMenu() {
    const isExpanded = burgerBtn?.getAttribute("aria-expanded") === "true";
    if (isExpanded) {
      closeMobileMenu();
    } else {
      openMobileMenu();
    }
  }

  if (burgerBtn) burgerBtn.addEventListener("click", toggleMobileMenu);
  if (mobileOverlay) mobileOverlay.addEventListener("click", closeMobileMenu);

  mobileLinks.forEach((link) => {
    link.addEventListener("click", () => {
      closeMobileMenu();
    });
  });

  window.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      closeMobileMenu();
      closeModal();
    }
  });

  window.addEventListener("resize", () => {
    if (window.innerWidth > 720 && burgerBtn?.getAttribute("aria-expanded") === "true") {
      closeMobileMenu();
    }
  });
});
