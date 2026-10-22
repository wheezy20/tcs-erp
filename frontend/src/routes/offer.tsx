import { createFileRoute } from "@tanstack/react-router";

import { OfferPage } from "@/modules/admissions/components/offer-page";
import publicFormCss from "@/modules/admissions/public-form.css?url";

// Public, unauthenticated route (admissions slice 11): the offer page at
// TCS OS's path. __root.tsx lists /offer as auth-free. The token arrives in
// the fragment and never reaches a server log; every real check happens in
// the admissions-public Edge Function and respond_to_offer.
export const Route = createFileRoute("/offer")({
  head: () => ({
    meta: [
      { title: "Your admissions offer · TCS" },
      { name: "referrer", content: "no-referrer" },
      { name: "robots", content: "noindex" },
    ],
    links: [{ rel: "stylesheet", href: publicFormCss }],
  }),
  component: OfferPage,
});
