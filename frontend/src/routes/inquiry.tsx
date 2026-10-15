import { createFileRoute } from "@tanstack/react-router";

import { InquiryPage } from "@/modules/admissions/components/inquiry-page";
import publicFormCss from "@/modules/admissions/public-form.css?url";

// Public, unauthenticated route (admissions slice 8): the Inquiry form at
// TCS OS's exact path, so links already sent keep resolving. __root.tsx
// lists /inquiry as auth-free. Every real check happens server-side in the
// admissions-public Edge Function and submit_inquiry. The TCS OS look and
// its self-hosted fonts (slice 9b) are linked here only, so the staff app
// never loads them.
export const Route = createFileRoute("/inquiry")({
  head: () => ({
    meta: [{ title: "Admissions enquiry · TCS" }],
    links: [{ rel: "stylesheet", href: publicFormCss }],
  }),
  component: InquiryPage,
});
