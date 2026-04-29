const storageKey = "chat_app:theme";
const legacyStorageKey = "phx:theme";
const themes = ["swiss", "mid-century", "techno-brutalist", "editorial"];
const themeClasses = themes.map((theme) => `theme-${theme}`);
const legacyThemes = {
  system: "editorial",
  light: "swiss",
  dark: "techno-brutalist",
};

const storage = {
  get(key) {
    try {
      return window.localStorage.getItem(key);
    } catch (_error) {
      return null;
    }
  },
  set(key, value) {
    try {
      window.localStorage.setItem(key, value);
    } catch (_error) {
      // Theme changes should still apply when storage is unavailable.
    }
  },
  remove(key) {
    try {
      window.localStorage.removeItem(key);
    } catch (_error) {
      // Ignore blocked storage APIs.
    }
  },
};

const normalizeTheme = (theme) => {
  const mappedTheme = legacyThemes[theme] || theme;
  return themes.includes(mappedTheme) ? mappedTheme : "editorial";
};

const syncPressedState = (activeTheme) => {
  document.querySelectorAll("[data-phx-theme]").forEach((button) => {
    const isActive = button.dataset.phxTheme === activeTheme;
    button.setAttribute("aria-pressed", isActive ? "true" : "false");
  });
};

const setTheme = (theme = "editorial") => {
  const nextTheme = normalizeTheme(theme);

  document.documentElement.classList.remove(...themeClasses);
  document.documentElement.classList.add(`theme-${nextTheme}`);
  document.documentElement.dataset.theme = nextTheme;
  document.documentElement.dataset.themeSource = "js";
  syncPressedState(nextTheme);
  storage.set(storageKey, nextTheme);
  storage.remove(legacyStorageKey);
};

const persistedTheme = () =>
  storage.get(storageKey) ||
  storage.get(legacyStorageKey) ||
  document.documentElement.dataset.theme ||
  "editorial";

export const initThemeController = () => {
  setTheme(persistedTheme());

  window.addEventListener("storage", (event) => {
    if (event.key === storageKey) {
      setTheme(event.newValue);
    }
  });

  window.addEventListener("phx:set-theme", (event) => {
    const trigger =
      event.target instanceof Element ? event.target.closest("[data-phx-theme]") : null;

    setTheme(trigger?.dataset.phxTheme);
  });

  window.addEventListener("phx:page-loading-stop", () => setTheme(persistedTheme()));

  const observer = new MutationObserver(() => {
    syncPressedState(normalizeTheme(document.documentElement.dataset.theme));
  });

  const attachObserver = () => {
    if (document.body) {
      observer.observe(document.body, { childList: true, subtree: true });
      syncPressedState(normalizeTheme(document.documentElement.dataset.theme));
    }
  };

  if (document.body) {
    attachObserver();
  } else {
    document.addEventListener("DOMContentLoaded", attachObserver, { once: true });
  }
};
