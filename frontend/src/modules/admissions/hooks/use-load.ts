import { useCallback, useEffect, useRef, useState } from "react";

import { getErrorMessage } from "@/lib/utils";

export type LoadState<T> = {
  data: T | undefined;
  loading: boolean;
  error: string | null;
  reload: () => Promise<void>;
};

/** Runs `load` on mount and whenever `deps` change, keeping the result in
 * this component's state only (no module cache, so nothing outlives the
 * page or carries over to the next signed-in user). A request id discards
 * a response that arrives after a newer request or after unmount. A reload
 * keeps the previous data on screen until the new data arrives, and keeps
 * it if the reload fails (with `error` set). */
export function useLoad<T>(
  load: () => Promise<T>,
  deps: unknown[],
  fallbackError = "Could not load this.",
): LoadState<T> {
  const [state, setState] = useState<{
    data: T | undefined;
    loading: boolean;
    error: string | null;
  }>({ data: undefined, loading: true, error: null });
  const requestId = useRef(0);

  const run = useCallback(async () => {
    const id = ++requestId.current;
    setState((s) => ({ ...s, loading: true, error: null }));
    try {
      const data = await load();
      if (id === requestId.current) setState({ data, loading: false, error: null });
    } catch (err) {
      if (id === requestId.current) {
        // Keep what was on screen: a failed reload after a write shouldn't
        // blank the panel. Callers show the error alongside it.
        setState((s) => ({
          data: s.data,
          loading: false,
          error: getErrorMessage(err, fallbackError),
        }));
      }
    }
    // `deps` is the caller's dependency list for `load`, as with useEffect.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(() => {
    run();
    return () => {
      requestId.current += 1;
    };
  }, [run]);

  return { ...state, reload: run };
}
