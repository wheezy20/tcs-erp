import { useEffect, useId, useRef, useState } from "react";

import { listedNationality, searchNationalities } from "@/modules/admissions/nationalities";

// The searchable nationality field (admissions slice 9b C3): an input with
// a list under it, following the WAI-ARIA combobox pattern, rendered in
// the page (no portal) so the .tcs-public look applies. Typing filters
// (accents ignored, prefix matches first, aliases such as "Ghanaian" or
// "UK" find their country). Keyboard: Enter or ArrowDown opens, the arrows
// move, Enter picks, Escape closes and keeps focus in the field, Tab moves
// on. Touch: tapping the field opens the list, tapping a country picks
// it. The value is whatever is in the field; validation refuses anything
// that isn't a listed country (decision Q5).

export function NationalityCombobox({
  id,
  value,
  onChange,
  invalid,
  "aria-describedby": describedBy,
  "aria-required": ariaRequired,
}: {
  id: string;
  value: string;
  onChange: (value: string) => void;
  invalid?: boolean;
  /** Set by PField. */
  "aria-describedby"?: string;
  "aria-required"?: boolean;
}) {
  const listId = useId();
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const listRef = useRef<HTMLUListElement>(null);
  const results = open ? searchNationalities(value) : [];
  const activeId = open && results[active] ? `${listId}-${active}` : undefined;

  // Keep the highlighted country in view as the arrows move.
  useEffect(() => {
    if (!open) return;
    listRef.current
      ?.querySelector(`[data-index="${active}"]`)
      ?.scrollIntoView({ block: "nearest" });
  }, [active, open]);

  function pick(name: string) {
    onChange(name);
    setOpen(false);
  }

  return (
    <div className="tcs-combobox">
      <input
        id={id}
        type="text"
        role="combobox"
        aria-autocomplete="list"
        aria-expanded={open}
        aria-controls={listId}
        aria-activedescendant={activeId}
        aria-invalid={invalid || undefined}
        aria-describedby={describedBy}
        aria-required={ariaRequired}
        autoComplete="off"
        spellCheck={false}
        maxLength={100}
        placeholder="Start typing a country…"
        value={value}
        onClick={() => {
          if (!open) setActive(0);
          setOpen(true);
        }}
        onChange={(e) => {
          onChange(e.target.value);
          setOpen(true);
          setActive(0);
        }}
        onKeyDown={(e) => {
          if (e.key === "ArrowDown") {
            e.preventDefault();
            if (!open) {
              setOpen(true);
              setActive(0);
            } else {
              setActive((a) => Math.min(a + 1, Math.max(results.length - 1, 0)));
            }
          } else if (e.key === "ArrowUp") {
            e.preventDefault();
            if (open) setActive((a) => Math.max(a - 1, 0));
          } else if (e.key === "Enter") {
            // Never submits the form from here.
            e.preventDefault();
            if (!open) {
              setOpen(true);
              setActive(0);
            } else if (results[active]) {
              pick(results[active]);
            }
          } else if (e.key === "Escape") {
            if (open) {
              e.preventDefault();
              setOpen(false);
            }
          } else if (e.key === "Tab") {
            setOpen(false);
          }
        }}
        onBlur={() => {
          setOpen(false);
          // "ghana" or "cote divoire" typed in full becomes the listed name.
          const listed = listedNationality(value);
          if (listed && listed !== value) onChange(listed);
        }}
      />
      {open && (
        <ul
          id={listId}
          ref={listRef}
          role="listbox"
          className="tcs-combobox-list"
          // Keeps focus in the field while the list's scrollbar is dragged.
          onMouseDown={(e) => e.preventDefault()}
        >
          {results.length === 0 ? (
            <li className="tcs-combobox-empty" role="presentation">
              No match. Not listed? Please contact the school.
            </li>
          ) : (
            results.map((name, i) => (
              <li
                key={name}
                id={`${listId}-${i}`}
                data-index={i}
                role="option"
                aria-selected={i === active}
                className={i === active ? "tcs-combobox-option tcs-active" : "tcs-combobox-option"}
                // mousedown, not click, so the field keeps focus and its
                // blur doesn't close the list first.
                onMouseDown={(e) => {
                  e.preventDefault();
                  pick(name);
                }}
                onMouseMove={() => setActive(i)}
              >
                {name}
              </li>
            ))
          )}
        </ul>
      )}
    </div>
  );
}
