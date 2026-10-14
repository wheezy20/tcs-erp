import { useEffect, useRef } from "react";

// Cloudflare Turnstile, rendered explicitly (admissions slice 8; TCS OS
// 02-stack-and-schema.md:615-619). The container has no "cf-turnstile"
// class, so Cloudflare's script never auto-renders a second widget whose
// token this page wouldn't see. The parent bumps resetKey after every
// attempt, because a token is single use. The site key is a public,
// build-time value (VITE_TURNSTILE_SITE_KEY); the secret lives only in the
// Edge Function.

type TurnstileApi = {
  render: (el: HTMLElement, opts: Record<string, unknown>) => string;
  reset: (id: string) => void;
  remove: (id: string) => void;
};

declare global {
  interface Window {
    turnstile?: TurnstileApi;
  }
}

const SCRIPT_SRC = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
let scriptPromise: Promise<TurnstileApi> | null = null;

function loadTurnstile(): Promise<TurnstileApi> {
  if (window.turnstile) return Promise.resolve(window.turnstile);
  if (!scriptPromise) {
    scriptPromise = new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = SCRIPT_SRC;
      s.async = true;
      s.onload = () =>
        window.turnstile ? resolve(window.turnstile) : reject(new Error("Turnstile missing"));
      s.onerror = () => {
        scriptPromise = null;
        reject(new Error("Turnstile failed to load"));
      };
      document.head.appendChild(s);
    });
  }
  return scriptPromise;
}

export function TurnstileWidget({
  siteKey,
  action,
  resetKey,
  onToken,
  onUnavailable,
}: {
  siteKey: string;
  action: string;
  resetKey: number;
  onToken: (token: string) => void;
  onUnavailable: () => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const widgetId = useRef<string | null>(null);
  const callbacks = useRef({ onToken, onUnavailable });
  callbacks.current = { onToken, onUnavailable };

  useEffect(() => {
    let cancelled = false;
    loadTurnstile()
      .then((api) => {
        if (cancelled || !ref.current) return;
        widgetId.current = api.render(ref.current, {
          sitekey: siteKey,
          action,
          callback: (token: string) => callbacks.current.onToken(token),
          "expired-callback": () => callbacks.current.onToken(""),
          "error-callback": () => callbacks.current.onToken(""),
        });
      })
      .catch(() => {
        if (!cancelled) callbacks.current.onUnavailable();
      });
    return () => {
      cancelled = true;
      if (widgetId.current && window.turnstile) window.turnstile.remove(widgetId.current);
      widgetId.current = null;
    };
  }, [siteKey, action]);

  useEffect(() => {
    if (resetKey > 0 && widgetId.current && window.turnstile) {
      window.turnstile.reset(widgetId.current);
      callbacks.current.onToken("");
    }
  }, [resetKey]);

  return <div ref={ref} />;
}
