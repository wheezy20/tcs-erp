import { describe, expect, it } from "vitest";

import {
  NATIONALITIES,
  NATIONALITY_ALIASES,
  isListedNationality,
  listedNationality,
  normalise,
  searchNationalities,
} from "@/modules/admissions/nationalities";

describe("the nationality list", () => {
  it("has the 241 TCS OS country names, Ghana first, no duplicates, none over 100 characters", () => {
    expect(NATIONALITIES).toHaveLength(241);
    expect(NATIONALITIES[0]).toBe("Ghana");
    expect(new Set(NATIONALITIES).size).toBe(241);
    expect(new Set(NATIONALITIES.map(normalise)).size).toBe(241);
    for (const n of NATIONALITIES) expect(n.length, n).toBeLessThanOrEqual(100);
    expect(Math.max(...NATIONALITIES.map((n) => n.length))).toBe(44);
  });

  it("keeps the rest in English alphabetical order, accented names in place", () => {
    const rest = NATIONALITIES.slice(1);
    expect(rest).toEqual([...rest].sort(new Intl.Collator("en").compare));
    expect(rest.indexOf("Åland Islands")).toBe(rest.indexOf("Afghanistan") + 1);
  });

  it("every alias points at a listed country, and no alias is itself stored", () => {
    for (const [country, aliases] of Object.entries(NATIONALITY_ALIASES)) {
      expect(NATIONALITIES).toContain(country);
      for (const a of aliases) {
        if (normalise(a) !== normalise(country)) expect(isListedNationality(a), a).toBe(false);
      }
    }
  });
});

describe("searchNationalities", () => {
  it("gives the whole list, Ghana first, for an empty query", () => {
    expect(searchNationalities("  ")[0]).toBe("Ghana");
    expect(searchNationalities("")).toHaveLength(241);
  });

  it("finds a country from its demonym or short form", () => {
    expect(searchNationalities("Ghanaian")[0]).toBe("Ghana");
    expect(searchNationalities("UK")).toContain("United Kingdom");
    expect(searchNationalities("usa")[0]).toBe("United States");
    expect(searchNationalities("Ivory Coast")[0]).toBe("Côte d'Ivoire");
    expect(searchNationalities("turkey")[0]).toBe("Türkiye");
    expect(searchNationalities("nigerian")[0]).toBe("Nigeria");
  });

  it("ignores accents and puts prefix matches first", () => {
    expect(searchNationalities("cote")[0]).toBe("Côte d'Ivoire");
    expect(searchNationalities("turk")[0]).toBe("Türkiye");
    const ni = searchNationalities("ni");
    expect(ni[0]).toBe("Nicaragua");
    // "Benin" contains "ni" but doesn't start with it: after every prefix match.
    expect(ni.indexOf("Benin")).toBeGreaterThan(ni.indexOf("Nigeria"));
    expect(searchNationalities("guinea").slice(0, 2)).toEqual(["Guinea", "Guinea-Bissau"]);
  });

  it("finds nothing for a made-up name", () => {
    expect(searchNationalities("Wakanda")).toEqual([]);
  });
});

describe("listedNationality", () => {
  it("returns the listed name for the same name in any case or accents, else null", () => {
    expect(listedNationality("ghana")).toBe("Ghana");
    expect(listedNationality("COTE D’IVOIRE")).toBe("Côte d'Ivoire");
    expect(listedNationality("Ghanaian")).toBeNull();
    expect(listedNationality("timor leste")).toBe("Timor-Leste");
    expect(listedNationality("Guinea Bissau")).toBe("Guinea-Bissau");
    expect(listedNationality("")).toBeNull();
  });
});
