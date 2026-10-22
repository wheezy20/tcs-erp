import { describe, expect, it } from "vitest";

import {
  interpretOfferAnswer,
  interpretOfferRead,
  offerDate,
  readOfferFragment,
} from "@/modules/admissions/offer-page";

const TOKEN = "a".repeat(64);
const OPEN = {
  state: "open",
  first_name: "Ama",
  grade: "Grade 3",
  academic_year: "2027/2028",
  campus: "Main campus",
  respond_by: "2026-11-05T09:00:00+00:00",
};

describe("the offer link", () => {
  it("reads only #token= with 64 lowercase hex", () => {
    expect(readOfferFragment(`#token=${TOKEN}`)).toBe(TOKEN);
    for (const hash of [
      "",
      `#token=${TOKEN.toUpperCase()}`,
      `#token=${TOKEN.slice(1)}`,
      `#resume=${TOKEN}`,
      `#token=${TOKEN}&x=1`,
      `?token=${TOKEN}`,
    ])
      expect(readOfferFragment(hash), hash).toBeNull();
  });
});

describe("reading the offer", () => {
  it("open: exactly the D-11a fields", () => {
    expect(interpretOfferRead(200, OPEN)).toEqual({
      kind: "open",
      details: {
        firstName: "Ama",
        grade: "Grade 3",
        academicYear: "2027/2028",
        campus: "Main campus",
        respondBy: OPEN.respond_by,
      },
    });
    const r = interpretOfferRead(200, { ...OPEN, campus: null, surname: "Mensah" });
    expect(r.kind === "open" && r.details).toEqual({
      firstName: "Ama",
      grade: "Grade 3",
      academicYear: "2027/2028",
      campus: null,
      respondBy: OPEN.respond_by,
    });
  });

  it("answered, invalid (404), limit (429), and an error for anything else", () => {
    expect(interpretOfferRead(200, { state: "answered", response: "declined" })).toEqual({
      kind: "answered",
      response: "declined",
    });
    expect(interpretOfferRead(404, { code: "offer_invalid" })).toEqual({ kind: "invalid" });
    expect(interpretOfferRead(429, {})).toEqual({ kind: "limit" });
    for (const [status, body] of [
      [0, null],
      [500, {}],
      [200, { ...OPEN, first_name: "" }],
      [200, { ...OPEN, respond_by: "soon" }],
      [200, { state: "answered", response: "maybe" }],
      [200, "x"],
    ] as const)
      expect(interpretOfferRead(status, body)).toEqual({ kind: "error" });
  });
});

describe("answering the offer", () => {
  it("recorded or answered with the response; refusals as for the read", () => {
    expect(interpretOfferAnswer(200, { status: "recorded", response: "accepted" })).toEqual({
      kind: "recorded",
      response: "accepted",
    });
    expect(interpretOfferAnswer(200, { status: "answered", response: "declined" })).toEqual({
      kind: "answered",
      response: "declined",
    });
    expect(interpretOfferAnswer(404, null)).toEqual({ kind: "invalid" });
    expect(interpretOfferAnswer(429, null)).toEqual({ kind: "limit" });
    expect(interpretOfferAnswer(200, { status: "recorded", response: "maybe" })).toEqual({
      kind: "error",
    });
    expect(interpretOfferAnswer(0, null)).toEqual({ kind: "error" });
  });

  it("writes the respond by date as the email does", () => {
    expect(offerDate("2026-11-05T09:00:00+00:00")).toBe("5 November 2026");
  });
});
