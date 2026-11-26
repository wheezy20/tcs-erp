import { createFileRoute } from "@tanstack/react-router";

import { PrivacyPage } from "@/modules/admissions/components/privacy-page";
import publicFormCss from "@/modules/admissions/public-form.css?url";

// Public, unauthenticated route (admissions slice 15 B): the school's
// privacy policy, linked relatively from PRIVACY_POLICY so it works on the
// workers.dev host and on the admissions host. __root.tsx lists /privacy as
// auth-free. Static: no data is read or written.
export const Route = createFileRoute("/privacy")({
  head: () => ({
    meta: [{ title: "Privacy policy · TCS" }],
    links: [{ rel: "stylesheet", href: publicFormCss }],
  }),
  component: PrivacyPage,
});
