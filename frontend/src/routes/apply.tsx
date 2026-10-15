import { createFileRoute } from "@tanstack/react-router";

import { ApplicationPage } from "@/modules/admissions/components/application-page";

// Public, unauthenticated route (admissions slice 9a): the plain
// Application form at TCS OS's path. __root.tsx lists /apply as auth-free.
// Every real check happens server-side in the admissions-public Edge
// Function and submit_application.
export const Route = createFileRoute("/apply")({
  head: () => ({ meta: [{ title: "Apply for admission · TCS" }] }),
  component: ApplicationPage,
});
