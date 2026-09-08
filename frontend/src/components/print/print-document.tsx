import { useEffect, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

/**
 * Renders its children into a dedicated print container that is the only thing
 * visible when the browser prints. Also sets the @page size for the sheet.
 */
export function PrintDocument({
  pageSize,
  margin = "12mm",
  children,
}: {
  pageSize: string;
  margin?: string;
  children: ReactNode;
}) {
  const [host, setHost] = useState<HTMLElement | null>(null);

  useEffect(() => {
    let el = document.getElementById("print-area");
    if (!el) {
      el = document.createElement("div");
      el.id = "print-area";
      document.body.appendChild(el);
    }
    setHost(el);
  }, []);

  if (!host) return null;

  return createPortal(
    <>
      <style>{`@page { size: ${pageSize}; margin: ${margin}; }`}</style>
      {children}
    </>,
    host,
  );
}
