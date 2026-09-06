import { useEffect, useState } from "react";

type Mode = "light" | "dark";

const STORAGE_KEY = "webapp-theme-mode";

function initialMode(): Mode {
  const stored = localStorage.getItem(STORAGE_KEY);
  if (stored === "light" || stored === "dark") return stored;
  return window.matchMedia("(prefers-color-scheme: light)").matches
    ? "light"
    : "dark";
}

export function ThemeToggle() {
  const [mode, setMode] = useState<Mode>(initialMode);

  useEffect(() => {
    document.documentElement.dataset.mode = mode;
    localStorage.setItem(STORAGE_KEY, mode);
  }, [mode]);

  const next = mode === "dark" ? "light" : "dark";
  return (
    <button
      className="theme-toggle"
      onClick={() => setMode(next)}
      aria-label={`Switch to ${next} mode`}
      title={`Switch to ${next} mode`}
    >
      {mode === "dark" ? "☀️ Light" : "🌙 Dark"}
    </button>
  );
}
