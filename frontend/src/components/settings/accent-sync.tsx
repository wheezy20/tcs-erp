import { useEffect } from "react";

import { useDocumentSettings } from "@/data/settings-store";

function hexToRgb(hex: string) {
  const clean = hex.replace("#", "");
  const full =
    clean.length === 3
      ? clean
          .split("")
          .map((c) => c + c)
          .join("")
      : clean;
  if (full.length !== 6 || /[^0-9a-f]/i.test(full)) return null;
  return {
    r: parseInt(full.slice(0, 2), 16),
    g: parseInt(full.slice(2, 4), 16),
    b: parseInt(full.slice(4, 6), 16),
  };
}

/** Applies the accent colour from Settings to the primary design tokens. */
export function AccentSync() {
  const { appearance } = useDocumentSettings();

  useEffect(() => {
    const rgb = hexToRgb(appearance.accent);
    const root = document.documentElement;
    if (!rgb) return;
    const luminance = (0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b) / 255;
    const foreground = luminance > 0.6 ? "oklch(0.2 0 0)" : "oklch(0.99 0 0)";
    for (const token of ["--primary", "--accent", "--sidebar-primary", "--sidebar-accent", "--ring", "--chart-1"]) {
      root.style.setProperty(token, appearance.accent);
    }
    root.style.setProperty("--primary-foreground", foreground);
    root.style.setProperty("--accent-foreground", foreground);
    root.style.setProperty("--sidebar-primary-foreground", foreground);
    root.style.setProperty("--sidebar-accent-foreground", foreground);
  }, [appearance.accent]);

  return null;
}
