import { GraduationCap } from "lucide-react";

import { PageHeader } from "@/components/page-header";

/** The "not available for this role" page. Renders nothing that queries. */
export function RoleBlockedPanel({
  title,
  description,
  what,
  openTo,
}: {
  title: string;
  description: string;
  what: string;
  openTo: string;
}) {
  return (
    <div>
      <PageHeader title={title} description={description} />
      <div className="flex min-h-[50vh] flex-col items-center justify-center gap-3 rounded-2xl border border-dashed px-6 py-24 text-center">
        <GraduationCap className="size-8 text-muted-foreground" />
        <h2 className="text-lg font-semibold">{what} isn't available for this role</h2>
        <p className="max-w-sm text-sm text-muted-foreground">It's open to {openTo}.</p>
      </div>
    </div>
  );
}
