import { Link } from "@tanstack/react-router";
import { ArrowLeft, FileQuestion } from "lucide-react";

/** The one page for an application that doesn't exist, isn't visible to
 * the caller, or has a malformed id. All three must look identical. */
export function ApplicationNotFound() {
  return (
    <>
      <BackToApplications />
      <div className="flex min-h-[50vh] flex-col items-center justify-center gap-3 rounded-2xl border border-dashed px-6 py-24 text-center">
        <FileQuestion className="size-8 text-muted-foreground" />
        <h1 className="text-lg font-semibold">Application not found</h1>
        <p className="max-w-sm text-sm text-muted-foreground">
          It may have been removed, or the link may be wrong.
        </p>
      </div>
    </>
  );
}

export function BackToApplications() {
  return (
    <Link
      to="/admissions"
      className="mb-4 inline-flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground"
    >
      <ArrowLeft className="size-4" /> Back to applications
    </Link>
  );
}
