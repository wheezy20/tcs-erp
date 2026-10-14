import { createFileRoute } from "@tanstack/react-router";

import { InquiryPage } from "@/modules/admissions/components/inquiry-page";

// Public, unauthenticated route (admissions slice 8): the Inquiry form at
// TCS OS's exact path, so links already sent keep resolving. __root.tsx
// lists /inquiry as auth-free. Every real check happens server-side in the
// admissions-public Edge Function and submit_inquiry.
export const Route = createFileRoute("/inquiry")({
  head: () => ({ meta: [{ title: "Admissions enquiry · TCS" }] }),
  component: InquiryPage,
});
