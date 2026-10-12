import { Badge } from "@/components/ui/badge";
import { STAGE_TONE, stageLabel, type Stage } from "@/modules/admissions/labels";

export function StageBadge({ stage }: { stage: string }) {
  return <Badge variant={STAGE_TONE[stage as Stage] ?? "outline"}>{stageLabel(stage)}</Badge>;
}

/** The grade as stored, with an "Unbanded" marker when it matches no grade
 * on the admissions grade list (legacy or free-text values). */
export function GradeCell({
  gradeAsEntered,
  gradeName,
}: {
  gradeAsEntered: string;
  gradeName: string | null;
}) {
  if (gradeName) return <span>{gradeName}</span>;
  return (
    <span className="inline-flex items-center gap-2">
      <span>{gradeAsEntered}</span>
      <Badge variant="outline" className="text-[10px] uppercase tracking-wide">
        Unbanded
      </Badge>
    </span>
  );
}
