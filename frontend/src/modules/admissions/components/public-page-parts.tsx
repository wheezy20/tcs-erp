import { Children, cloneElement, isValidElement, useEffect, type ReactNode } from "react";

// The TCS OS look for the public admissions pages (slice 9b), with the
// classes in public-form.css. /inquiry uses these from C1; /apply moves to
// them in C2 (it still uses public-form-parts.tsx until then).

/** The page: the .tcs-public scope, and body.tcs-public-body while mounted
 * (the page background on overscroll, and anything rendered outside the
 * wrapper). */
export function PublicPage({ wide, children }: { wide?: boolean; children: ReactNode }) {
  useEffect(() => {
    document.body.classList.add("tcs-public-body");
    return () => document.body.classList.remove("tcs-public-body");
  }, []);
  return (
    <div className="tcs-public">
      <main className={wide ? "tcs-main tcs-wide" : "tcs-main"}>
        <div className="tcs-brand-header">
          <img src="/full-logo-transparent.png" alt="Treasures Christian School" />
        </div>
        {children}
      </main>
    </div>
  );
}

/** A thank-you, closed or error screen: the card with centred text. */
export function PublicNotice({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="tcs-card tcs-notice">
      <h2>{title}</h2>
      {children}
    </div>
  );
}

export function Section({
  number,
  title,
  children,
}: {
  number: number;
  title: string;
  children: ReactNode;
}) {
  return (
    <fieldset>
      <legend>
        <span className="tcs-section-number">{number}.</span>
        {title}
      </legend>
      {children}
    </fieldset>
  );
}

export function BlockHeading({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <p className="tcs-block-heading">
      {children}
      {action}
    </p>
  );
}

export function Row({ children }: { children: ReactNode }) {
  return <div className="tcs-row">{children}</div>;
}

export function PField({
  id,
  label,
  required,
  error,
  hint,
  children,
}: {
  id: string;
  label?: string;
  required?: boolean;
  error?: string;
  hint?: string | null;
  children: ReactNode;
}) {
  // The field's own control (the first child) is told which hint and error
  // describe it, and that it is required, so a screen reader reads the
  // reason with "invalid".
  const describedBy = [error ? `${id}-error` : null, hint ? `${id}-hint` : null]
    .filter(Boolean)
    .join(" ");
  const items = Children.toArray(children);
  const first = items[0];
  if (isValidElement<Record<string, unknown>>(first)) {
    items[0] = cloneElement(first, {
      "aria-describedby": describedBy || undefined,
      "aria-required": required || undefined,
    });
  }
  return (
    <div className="tcs-field">
      {label && (
        <label htmlFor={id}>
          {label}
          {required && (
            <>
              {" "}
              <span className="tcs-required" aria-hidden="true">
                *
              </span>
            </>
          )}
        </label>
      )}
      {items}
      {hint && (
        <div id={`${id}-hint`} className="tcs-hint">
          {hint}
        </div>
      )}
      {error && (
        <div id={`${id}-error`} className="tcs-field-error">
          {error}
        </div>
      )}
    </div>
  );
}

/** A native select, as TCS OS uses (decision Q11): the phone's own picker
 * on mobile and nothing rendered outside the page. The placeholder is the
 * disabled first option, as in TCS OS. */
export function NativeSelect({
  id,
  value,
  onChange,
  placeholder,
  items,
  invalid,
  "aria-describedby": describedBy,
  "aria-required": ariaRequired,
}: {
  id: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  items: readonly { value: string; label: string }[];
  invalid?: boolean;
  /** Set by PField. */
  "aria-describedby"?: string;
  "aria-required"?: boolean;
}) {
  return (
    <select
      id={id}
      value={value}
      aria-invalid={invalid || undefined}
      aria-describedby={describedBy}
      aria-required={ariaRequired}
      onChange={(e) => onChange(e.target.value)}
    >
      {placeholder !== undefined && (
        <option value="" disabled>
          {placeholder}
        </option>
      )}
      {items.map((i) => (
        <option key={i.value} value={i.value}>
          {i.label}
        </option>
      ))}
    </select>
  );
}
