import { Boxes, Grid2x2, Layers, PaintBucket, Package, Sparkles, Wrench } from "lucide-react";

import { cn } from "@/lib/utils";

// Keyed by the original six categories only, and deliberately a Partial —
// Settings lets a Manager add categories beyond these (the DB column is
// free text; Category is a narrow union covering only the original set,
// trusted at the row-mapping boundary per CLAUDE.md's Inventory notes).
// This map can never be assumed complete, so every read of it goes through
// a fallback below rather than an unchecked index.
const MAP: Partial<Record<string, { icon: typeof Boxes; className: string }>> = {
  Paint: { icon: PaintBucket, className: "bg-primary/15 text-primary" },
  Tiles: { icon: Grid2x2, className: "bg-sky-500/15 text-sky-600 dark:text-sky-400" },
  "PVC Panels": {
    icon: Layers,
    className: "bg-violet-500/15 text-violet-600 dark:text-violet-400",
  },
  Wallpaper: { icon: Sparkles, className: "bg-amber-500/15 text-amber-600 dark:text-amber-400" },
  Adhesives: { icon: Boxes, className: "bg-rose-500/15 text-rose-600 dark:text-rose-400" },
  Hardware: { icon: Wrench, className: "bg-muted text-muted-foreground" },
};

const DEFAULT_TINT = { icon: Package, className: "bg-muted text-muted-foreground" };

export function ProductThumb({
  category,
  className,
  iconClassName,
}: {
  // A plain string, not the Category union — this component's whole job is
  // to render something reasonable for a category it's never heard of, so
  // it shouldn't claim to only accept the original six.
  category: string;
  className?: string;
  iconClassName?: string;
}) {
  // Falls back to a generic icon for any category not in MAP — structural,
  // not a special case for one category name, so the next one a Manager
  // adds through Settings can't crash this render either (a real
  // production crash this exact shape caused for "Security & Fencing").
  const { icon: Icon, className: tint } = MAP[category] ?? DEFAULT_TINT;
  return (
    <div
      aria-hidden
      className={cn(
        "flex size-11 shrink-0 items-center justify-center rounded-xl border border-border/60",
        tint,
        className,
      )}
    >
      <Icon className={cn("size-5", iconClassName)} />
    </div>
  );
}
