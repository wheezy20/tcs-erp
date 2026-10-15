import { createFileRoute } from "@tanstack/react-router";

import { ApplicationPage } from "@/modules/admissions/components/application-page";
import publicFormCss from "@/modules/admissions/public-form.css?url";

// Public, unauthenticated route (admissions slice 9a): the Application form
// at TCS OS's path. __root.tsx lists /apply as auth-free. Every real check
// happens server-side in the admissions-public Edge Function and
// submit_application. The TCS OS look and its self-hosted fonts (slice 9b)
// are linked here and on /inquiry only, so the staff app never loads them.
export const Route = createFileRoute("/apply")({
  head: () => ({
    meta: [{ title: "Apply for admission · TCS" }],
    links: [{ rel: "stylesheet", href: publicFormCss }],
  }),
  component: ApplicationPage,
});
