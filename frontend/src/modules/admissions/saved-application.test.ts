import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import { FEE_PROOF, emptyApplicationDraft } from "@/modules/admissions/application-form";
import { FEE, OPTIONS, validDraft } from "@/modules/admissions/application-fixtures";
import {
  SAVED_CEILING_DAYS,
  SAVED_DAYS,
  defaultSaveEmail,
  draftError,
  fromSavedState,
  hasUnsavedChanges,
  interpretCreate,
  interpretLoad,
  interpretSave,
  keptUntil,
  readResumeFragment,
  savedKey,
  savedStep,
  toSavedState,
} from "@/modules/admissions/saved-application";
import { SAVE_COPY } from "@/modules/admissions/public-copy";

/** A saved state as JSON, for tampering with in tests. */
type RawState = {
  child: Record<string, unknown>;
  guardians: Record<string, unknown>[];
  [key: string]: unknown;
};

const FALLBACK = "We could not save your application right now. Please contact the school office.";
const fixture = () =>
  JSON.parse(
    readFileSync(
      resolve(
        __dirname,
        "../../../../supabase/functions/admissions-public/fixtures/saved-application-state.json",
      ),
      "utf8",
    ),
  ) as Record<string, unknown>;

/** Every key path, so two shapes can be compared. */
function keys(v: unknown, prefix = ""): string[] {
  if (Array.isArray(v)) return v.length ? keys(v[0], `${prefix}[]`) : [`${prefix}[]`];
  if (v && typeof v === "object")
    return Object.entries(v).flatMap(([k, x]) => keys(x, prefix ? `${prefix}.${k}` : k));
  return [prefix];
}

describe("what a save keeps", () => {
  it("leaves out the health answers, the declaration, the signature and media consent", () => {
    const d = validDraft();
    d.health = {
      hasNeeds: true,
      needs: "x",
      hasMedical: true,
      medical: "asthma",
      hasAllergies: false,
      allergies: "",
    };
    d.signature = "Ama Mensah";
    d.agreed = true;
    d.mediaConsent = true;
    const s = toSavedState(d) as Record<string, unknown>;
    for (const k of ["health", "signature", "agreed", "mediaConsent", "documents"])
      expect(s).not.toHaveProperty(k);
    expect(JSON.stringify(s)).not.toMatch(/asthma|Ama Mensah/);
    expect(s.child).toEqual(d.child);
    expect(s.guardians).toEqual(d.guardians);
  });

  it("has exactly the shape of the shared fixture the Edge integration test saves", () => {
    const shape = new Set(keys(toSavedState(validDraft())));
    expect(new Set(keys(fixture()))).toEqual(shape);
  });

  it("copies, so later typing doesn't change a snapshot", () => {
    const d = validDraft();
    const key = savedKey(d);
    d.child.fullName = "Changed";
    d.guardians[0].email = "changed@example.test";
    expect(savedKey(d)).not.toBe(key);
  });
});

describe("resuming", () => {
  it("rebuilds the form from its own saved state, with the unsaved parts empty", () => {
    const d = validDraft();
    const back = fromSavedState(JSON.parse(JSON.stringify(toSavedState(d))), OPTIONS);
    expect(toSavedState(back)).toEqual(toSavedState(d));
    const empty = emptyApplicationDraft();
    expect([back.health, back.signature, back.agreed, back.mediaConsent]).toEqual([
      empty.health,
      empty.signature,
      empty.agreed,
      empty.mediaConsent,
    ]);
  });

  it("blanks values no longer offered and drops anything unknown", () => {
    const d = validDraft();
    const raw = JSON.parse(JSON.stringify(toSavedState(d))) as RawState;
    raw.child.gradeId = "g-gone";
    raw.child.academicYear = "1999/2000";
    raw.child.month = "March";
    raw.child.nationality = "Atlantis";
    raw.child.currentGrade = "g-gone";
    raw.child.dateOfBirth = "<b>";
    raw.guardians[0].relationship = "uncle";
    raw.guardians[0].religion = "Pastafarian";
    raw.guardians.push(raw.guardians[0], raw.guardians[0]);
    raw.health = { hasMedical: true, medical: "asthma" };
    raw.signature = "Ama";
    raw.unknown = { x: 1 };
    const back = fromSavedState(raw, OPTIONS);
    expect([
      back.child.gradeId,
      back.child.academicYear,
      back.child.month,
      back.child.nationality,
      back.child.currentGrade,
      back.child.dateOfBirth,
    ]).toEqual(["", "", "", "", "", ""]);
    expect([back.guardians[0].relationship, back.guardians[0].religion]).toEqual(["", ""]);
    expect(back.guardians).toHaveLength(2);
    expect(back.health).toEqual(emptyApplicationDraft().health);
    expect(back.signature).toBe("");
    expect(back).not.toHaveProperty("unknown");
  });

  it("blanks a grade the chosen campus no longer takes", () => {
    const raw = JSON.parse(JSON.stringify(toSavedState(validDraft()))) as RawState;
    raw.campusId = "c-annex";
    raw.child.gradeId = "g-3";
    expect(fromSavedState(raw, OPTIONS).child.gradeId).toBe("");
  });

  it("never throws on junk", () => {
    for (const junk of [null, "x", 5, [], { guardians: "x", child: [], emergency: 3 }])
      expect(fromSavedState(junk, OPTIONS)).toEqual(emptyApplicationDraft());
  });

  it("clamps the saved step", () => {
    expect([
      savedStep(3),
      savedStep(5),
      savedStep(6),
      savedStep(-1),
      savedStep(1.5),
      savedStep("2"),
    ]).toEqual([3, 5, 0, 0, 0, 0]);
  });

  it("reads only #resume=<64 hex> from the fragment", () => {
    const t = "a".repeat(64);
    expect(readResumeFragment(`#resume=${t}`)).toBe(t);
    for (const h of [
      "",
      "#",
      `#resume=${t.toUpperCase()}`,
      `#resume=${t}x`,
      `?resume=${t}`,
      `#other=${t}`,
    ])
      expect(readResumeFragment(h)).toBeNull();
  });

  it("prefills guardian 1's email when it looks like one", () => {
    const d = validDraft();
    expect(defaultSaveEmail(d)).toBe(d.guardians[0].email.trim());
    d.guardians[0].email = "not an email";
    expect(defaultSaveEmail(d)).toBe("");
  });
});

describe("the leave page warning", () => {
  it("before any save: anything entered, or a file", () => {
    expect(hasUnsavedChanges(emptyApplicationDraft(), null, {})).toBe(false);
    expect(hasUnsavedChanges(validDraft(), null, {})).toBe(true);
    expect(hasUnsavedChanges(emptyApplicationDraft(), null, { [FEE_PROOF]: FEE })).toBe(true);
  });

  it("after a save: only changes since then, anything in a part never saved, or a file", () => {
    const d = validDraft();
    d.health = emptyApplicationDraft().health;
    d.signature = "";
    d.agreed = false;
    d.mediaConsent = false;
    const saved = savedKey(d);
    expect(hasUnsavedChanges(d, saved, {})).toBe(false);
    expect(hasUnsavedChanges({ ...d, child: { ...d.child, fullName: "New" } }, saved, {})).toBe(
      true,
    );
    expect(hasUnsavedChanges({ ...d, health: { ...d.health, hasMedical: false } }, saved, {})).toBe(
      true,
    );
    expect(hasUnsavedChanges({ ...d, signature: "Ama" }, saved, {})).toBe(true);
    expect(hasUnsavedChanges({ ...d, agreed: true }, saved, {})).toBe(true);
    expect(hasUnsavedChanges({ ...d, mediaConsent: true }, saved, {})).toBe(true);
    expect(hasUnsavedChanges(d, saved, { [FEE_PROOF]: FEE })).toBe(true);
  });
});

describe("draft answers", () => {
  const T = "b".repeat(64);
  const info = {
    version: 2,
    expires_at: "2026-11-20T06:34:29+00:00",
    email_masked: "a•••@e•••.test",
  };

  it("reads each success shape, and refuses a bad one", () => {
    expect(interpretCreate(200, { draft_token: T, ...info }, FALLBACK)).toEqual({
      ok: true,
      token: T,
      version: 2,
      expiresAt: info.expires_at,
      emailMasked: info.email_masked,
    });
    expect(interpretCreate(200, { draft_token: "short", ...info }, FALLBACK)).toMatchObject({
      ok: false,
      code: "error",
    });
    expect(interpretSave(200, { email_queued: true, ...info }, FALLBACK)).toMatchObject({
      ok: true,
      emailQueued: true,
    });
    expect(
      interpretLoad(200, { state: { campusId: "x" }, step: 9, ...info }, FALLBACK),
    ).toMatchObject({
      ok: true,
      step: 0,
      state: { campusId: "x" },
    });
    expect(interpretLoad(200, { state: [], step: 1, ...info }, FALLBACK)).toMatchObject({
      ok: false,
    });
  });

  it("keeps the server's message and code, except the live-draft limit, which is always generic", () => {
    expect(
      draftError(429, { error: "Too many emails today.", code: "draft_email_limit" }, FALLBACK),
    ).toEqual({
      ok: false,
      code: "draft_email_limit",
      message: "Too many emails today.",
    });
    const limit = draftError(
      429,
      { error: "This address already has saved applications.", code: "draft_limit" },
      FALLBACK,
    );
    expect(limit).toEqual({ ok: false, code: "draft_limit", message: FALLBACK });
    expect(limit.message).not.toMatch(/saved applications|draft|already/i);
    expect(draftError(409, {}, FALLBACK)).toMatchObject({ code: "closed" });
    expect(draftError(0, null, FALLBACK)).toEqual({ ok: false, code: "error", message: FALLBACK });
    expect(draftError(400, { error: "x", code: "made_up" }, FALLBACK)).toMatchObject({
      code: "error",
    });
  });

  it("writes the kept-until date as the email does", () => {
    expect(keptUntil("2026-11-20T06:34:29+00:00")).toBe("20 November 2026");
    expect(keptUntil("soon")).toBe("");
  });
});

describe("the numbers", () => {
  it("match the database's _application_draft_lifetime", () => {
    const sql = readFileSync(
      resolve(__dirname, "../../../../supabase/migrations/20261028100000_admissions_drafts.sql"),
      "utf8",
    );
    const body =
      /function public\._application_draft_lifetime\([\s\S]*?\$\$([\s\S]*?)\$\$/.exec(sql)?.[1] ??
      "";
    expect(body).toContain(`interval '${SAVED_DAYS} days', interval '${SAVED_CEILING_DAYS} days'`);
  });

  it("are the numbers the consent line states", () => {
    expect(SAVE_COPY.consentBefore).toContain(`${SAVED_DAYS} days after my last save`);
    expect(SAVE_COPY.consentBefore).toContain(`no more than ${SAVED_CEILING_DAYS} days in all`);
  });
});
