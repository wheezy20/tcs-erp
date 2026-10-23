import { describe, expect, it } from "vitest";

import { differenceRows, guardiansNotOnRecord } from "@/modules/admissions/submission-check";

describe("differenceRows", () => {
  it("lists guardian and child differences with labels", () => {
    const rows = differenceRows(
      {
        guardians: [
          { email: "a@x.com", new: false, fields: { phone: "+233590000000", address: "" } },
          { email: "b@x.com", new: true, fields: { surname: "Owusu" } },
        ],
        student: { current_grade_id: "g-2", prior_schooling: null, nationality: "Ghanaian" },
      },
      { "g-2": "Grade 2" },
    );
    expect(rows).toEqual([
      { who: "Guardian a@x.com", field: "Phone", submitted: "+233590000000" },
      { who: "Guardian a@x.com", field: "Address", submitted: "(blank)" },
      { who: "New guardian (not added): b@x.com", field: "Surname", submitted: "Owusu" },
      { who: "Child", field: "Current grade", submitted: "Grade 2" },
      { who: "Child", field: "Current grade", submitted: "(blank)" },
      { who: "Child", field: "Nationality", submitted: "Ghanaian" },
    ]);
  });
  it("skips anything it doesn't recognise", () => {
    expect(differenceRows(null, {})).toEqual([]);
    expect(
      differenceRows({ guardians: "x", student: { medical_conditions_details: "x" } }, {}),
    ).toEqual([]);
    expect(differenceRows({ guardians: [{ email: 1, fields: {} }] }, {})).toEqual([]);
  });
});

describe("guardiansNotOnRecord (slice 11)", () => {
  it("counts distinct typed addresses that are not on the family record", () => {
    expect(
      guardiansNotOnRecord({
        guardians: [
          { email: "a@x.com", new: false, fields: { phone: "1" } },
          { email: "b@x.com", new: true, fields: {} },
          { email: " B@X.com ", new: true, fields: {} },
          { email: "c@x.com", new: true, fields: { surname: "Owusu" } },
        ],
      }),
    ).toBe(2);
  });
  it("is 0 for no flag, no guardian differences or an unknown shape", () => {
    expect(guardiansNotOnRecord(null)).toBe(0);
    expect(guardiansNotOnRecord({ student: { nationality: "Ghanaian" } })).toBe(0);
    expect(guardiansNotOnRecord({ guardians: "x" })).toBe(0);
    expect(guardiansNotOnRecord({ guardians: [{ email: 5, new: true }, { new: true }] })).toBe(0);
    expect(guardiansNotOnRecord({ guardians: [{ email: "a@x.com", new: "true" }] })).toBe(0);
  });
});
