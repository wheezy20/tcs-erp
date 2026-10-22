import { call } from "@/modules/admissions/data/public-apply";
import {
  interpretOfferAnswer,
  interpretOfferRead,
  type OfferAnswer,
  type OfferRead,
  type OfferResponse,
} from "@/modules/admissions/offer-page";

// The public offer page's two calls (admissions slice 11). Both go to the
// admissions-public Edge Function, which holds the only key that can call
// the offer RPCs. The link's token lives only in the page's memory and in
// these POST bodies: never in a URL, in storage or in a log.

export async function readOffer(token: string): Promise<OfferRead> {
  const a = await call({ action: "offer_get", payload: { token } });
  return interpretOfferRead(a.status, a.body);
}

export async function answerOffer(token: string, response: OfferResponse): Promise<OfferAnswer> {
  const a = await call({ action: "offer_respond", payload: { token, response } });
  return interpretOfferAnswer(a.status, a.body);
}
