import { describe, expect, it } from "vitest";

import {
  SEARCH_MAX_LENGTH,
  notInListFilter,
  searchFilter,
  searchPattern,
} from "@/modules/admissions/data/search";

describe("list search", () => {
  it("is null for an empty or symbol-only search", () => {
    expect(searchPattern("")).toBeNull();
    expect(searchPattern("   ")).toBeNull();
    expect(searchPattern("%_,()*")).toBeNull();
  });

  it("keeps names and references, quoted for PostgREST", () => {
    expect(searchPattern("  Ama  Owusu ")).toBe('"%Ama Owusu%"');
    expect(searchPattern("APP-2026-0001")).toBe('"%APP-2026-0001%"');
    expect(searchPattern("O'Neil Adjei-Mensah")).toBe(`"%O'Neil Adjei-Mensah%"`);
    expect(searchPattern("Àdébáyọ̀")).not.toBeNull();
  });

  it("drops characters that would break the or filter or act as wildcards", () => {
    const p = searchPattern('a,b)c(d"e%f_g*h\\i')!;
    expect(p).toBe('"%abcdefghi%"');
    expect(searchFilter(p)).toBe(
      'student_full_name.ilike."%abcdefghi%",inquiry_reference.ilike."%abcdefghi%",application_reference.ilike."%abcdefghi%"',
    );
  });

  it("caps the search length", () => {
    expect(searchPattern("x".repeat(500))).toBe(`"%${"x".repeat(SEARCH_MAX_LENGTH)}%"`);
  });

  it("quotes each academic year label for not in", () => {
    expect(notInListFilter(["2026/2027", "2027/2028"])).toBe('("2026/2027","2027/2028")');
  });
});
