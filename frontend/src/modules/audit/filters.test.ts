import { describe, expect, it } from "vitest";

import { dateRangeBounds, describeChanges } from "@/modules/audit/filters";

describe("dateRangeBounds", () => {
  it("leaves both bounds open when no date is set", () => {
    expect(dateRangeBounds("", "")).toEqual({ gte: null, lt: null, error: null });
  });

  it("includes the whole To day", () => {
    expect(dateRangeBounds("2026-10-01", "2026-10-13")).toEqual({
      gte: "2026-10-01T00:00:00.000Z",
      lt: "2026-10-14T00:00:00.000Z",
      error: null,
    });
  });

  it("allows one day, and one-sided ranges", () => {
    expect(dateRangeBounds("2026-10-13", "2026-10-13").lt).toBe("2026-10-14T00:00:00.000Z");
    expect(dateRangeBounds("2026-10-13", "")).toEqual({
      gte: "2026-10-13T00:00:00.000Z",
      lt: null,
      error: null,
    });
    expect(dateRangeBounds("", "2026-12-31").lt).toBe("2027-01-01T00:00:00.000Z");
  });

  it("refuses From after To", () => {
    expect(dateRangeBounds("2026-10-14", "2026-10-13").error).toBe(
      "The From date is after the To date.",
    );
  });

  it("refuses a malformed or impossible date", () => {
    expect(dateRangeBounds("13/10/2026", "").error).not.toBeNull();
    expect(dateRangeBounds("", "2026-02-30").error).not.toBeNull();
  });
});

describe("describeChanges", () => {
  it("lists only the fields that differ when both sides exist", () => {
    expect(
      describeChanges(
        { stage: "inquiry", ref: "APP-2026-0001" },
        { stage: "application", ref: "APP-2026-0001" },
      ),
    ).toEqual([{ key: "stage", before: "inquiry", after: "application" }]);
  });

  it("lists every field on a creation or a removal", () => {
    expect(describeChanges(null, { b: 2, a: true })).toEqual([
      { key: "a", before: null, after: "true" },
      { key: "b", before: null, after: "2" },
    ]);
    expect(describeChanges({ a: "x" }, null)).toEqual([{ key: "a", before: "x", after: null }]);
  });

  it("shows a field added or dropped between the two sides", () => {
    expect(describeChanges({ a: 1 }, { a: 1, b: null })).toEqual([]);
    expect(describeChanges({ a: 1 }, { a: 1, b: "new" })).toEqual([
      { key: "b", before: null, after: "new" },
    ]);
  });

  it("joins flat lists and writes nested values as JSON", () => {
    expect(describeChanges(null, { bands: ["primary", "jhs"], o: { x: 1 } })).toEqual([
      { key: "bands", before: null, after: "primary, jhs" },
      { key: "o", before: null, after: '{"x":1}' },
    ]);
  });

  it("returns nothing when neither side exists", () => {
    expect(describeChanges(null, null)).toEqual([]);
  });
});
