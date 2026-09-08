import { Construction } from "lucide-react";

import { PageHeader } from "@/components/page-header";

export function PlaceholderPage({ title, description }: { title: string; description: string }) {
  return (
    <>
      <PageHeader title={title} description={description} />
      <div className="card-surface flex flex-col items-center justify-center gap-3 px-6 py-20 text-center">
        <div className="flex size-12 items-center justify-center rounded-2xl bg-accent text-accent-foreground">
          <Construction className="size-6" />
        </div>
        <p className="text-base font-medium">{title} module coming next</p>
        <p className="max-w-sm text-sm text-muted-foreground">
          This area is scaffolded and ready. The full workflow will be built in an upcoming step.
        </p>
      </div>
    </>
  );
}
