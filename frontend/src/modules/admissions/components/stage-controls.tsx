import { useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { StaffRole } from "@/data/auth-store";
import { moveToDocumentReview, setApplicationStage } from "@/modules/admissions/data/mutations";
import { STAGE_LABELS, stageLabel } from "@/modules/admissions/labels";
import { canMoveToDocumentReview, stageChangeTargets } from "@/modules/admissions/permissions";
import { getErrorMessage } from "@/lib/utils";

/** Stage write controls. Rendered only for roles that may use them; the RPCs
 * re-check role, scope and stage under a row lock. */
export function StageControls({
  applicationId,
  stage,
  role,
  onChanged,
}: {
  applicationId: string;
  stage: string;
  role: StaffRole | undefined;
  onChanged: () => Promise<void>;
}) {
  const [busy, setBusy] = useState(false);
  const targets = stageChangeTargets(role, stage);
  const canMove = canMoveToDocumentReview(role, stage);
  if (!canMove && targets.length === 0) return null;

  async function move() {
    setBusy(true);
    try {
      await moveToDocumentReview(applicationId);
      toast.success("Moved to Document review");
      await onChanged();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not change the stage."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      {canMove && (
        <Button onClick={move} disabled={busy}>
          {busy ? "Moving…" : "Move to Document review"}
        </Button>
      )}
      {targets.length > 0 && (
        <ChangeStageDialog
          applicationId={applicationId}
          stage={stage}
          targets={targets}
          onChanged={onChanged}
        />
      )}
    </>
  );
}

function ChangeStageDialog({
  applicationId,
  stage,
  targets,
  onChanged,
}: {
  applicationId: string;
  stage: string;
  targets: string[];
  onChanged: () => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [target, setTarget] = useState<string>("");
  const [saving, setSaving] = useState(false);

  async function save() {
    if (!target) return;
    setSaving(true);
    try {
      await setApplicationStage(applicationId, target);
      toast.success(`Stage changed to ${stageLabel(target)}`);
      setOpen(false);
      await onChanged();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not change the stage."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        setOpen(o);
        if (o) setTarget("");
      }}
    >
      <DialogTrigger asChild>
        <Button variant="outline">Change stage</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Change stage</DialogTitle>
          <DialogDescription>
            Currently {stageLabel(stage)}. Offer and enrolment happen through their own steps, not
            here. The change is recorded in the audit log.
          </DialogDescription>
        </DialogHeader>
        <Select value={target} onValueChange={setTarget}>
          <SelectTrigger aria-label="New stage">
            <SelectValue placeholder="Choose a stage" />
          </SelectTrigger>
          <SelectContent>
            {targets.map((t) => (
              <SelectItem key={t} value={t}>
                {STAGE_LABELS[t as keyof typeof STAGE_LABELS] ?? t}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={save} disabled={saving || !target}>
            {saving ? "Saving…" : "Change stage"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
