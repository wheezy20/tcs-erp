import { useState } from "react";
import { ShieldCheck } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Switch } from "@/components/ui/switch";
import type { Staff } from "@/data/auth-store";
import {
  BAND_LABELS,
  GRADE_BANDS,
  bandRangeLabel,
  setAdmissionsCapabilities,
  useAdmissionsGrades,
  type AdmissionsCapabilities,
  type GradeBand,
} from "@/data/admissions-capabilities-store";
import { getErrorMessage } from "@/lib/utils";

type Scope = "none" | "bands" | "all";

/** Manager-only editor for one staff member's admissions access. Only mounted
 * when a Manager opens it, so the grade list it loads never loads for anyone
 * else. It offers only what the member's role may hold; the database
 * (set_admissions_capabilities) enforces the same rules and is the authority. */
export function AdmissionsAccessDialog({
  member,
  current,
}: {
  member: Staff;
  current: AdmissionsCapabilities | undefined;
}) {
  const [open, setOpen] = useState(false);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="ghost" size="sm" className="h-7 gap-1.5 px-2 text-xs">
          <ShieldCheck className="size-3" /> Manage
        </Button>
      </DialogTrigger>
      {open && <AccessForm member={member} current={current} onDone={() => setOpen(false)} />}
    </Dialog>
  );
}

function AccessForm({
  member,
  current,
  onDone,
}: {
  member: Staff;
  current: AdmissionsCapabilities | undefined;
  onDone: () => void;
}) {
  const { grades } = useAdmissionsGrades();
  const role = member.role;
  const isOfficer = role === "Admissions Officer";
  const mayDecide = role === "Manager" || isOfficer;
  // can_view_health may be held by any role (D-2b-revised), but Attendant and
  // Accountant see no admissions rows, so it's only offered to them when
  // there's an existing grant to revoke (O-6).
  const healthHasEffect = role === "Manager" || role === "Auditor" || isOfficer;
  const offerHealth = healthHasEffect || Boolean(current?.canViewHealth);

  const [canDecide, setCanDecide] = useState(current?.canDecide ?? false);
  const [canViewHealth, setCanViewHealth] = useState(current?.canViewHealth ?? false);
  const [scope, setScope] = useState<Scope>(
    current?.allGrades ? "all" : current?.gradeBands.length ? "bands" : "none",
  );
  const [bands, setBands] = useState<GradeBand[]>(current?.gradeBands ?? []);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function toggleBand(band: GradeBand, checked: boolean) {
    setBands((prev) => (checked ? [...prev, band] : prev.filter((b) => b !== band)));
  }

  async function save() {
    setSaving(true);
    setError(null);
    try {
      await setAdmissionsCapabilities(member.id, {
        canDecide: mayDecide && canDecide,
        canViewHealth: offerHealth && canViewHealth,
        gradeBands: isOfficer && scope === "bands" ? bands : [],
        allGrades: isOfficer && scope === "all",
      });
      toast.success(`Admissions access updated for ${member.name}`);
      onDone();
    } catch (err) {
      setError(getErrorMessage(err, "Could not update admissions access."));
    } finally {
      setSaving(false);
    }
  }

  const nothingToOffer = !mayDecide && !offerHealth && !isOfficer;

  return (
    <DialogContent className="sm:max-w-md">
      <DialogHeader>
        <DialogTitle>Admissions access: {member.name}</DialogTitle>
        <DialogDescription>
          {role}. Narrows what this person can do inside admissions. Every change is recorded in the
          audit log.
        </DialogDescription>
      </DialogHeader>

      {nothingToOffer ? (
        <p className="text-sm text-muted-foreground">
          A {role} has no admissions access, so there is nothing to grant.
        </p>
      ) : (
        <div className="space-y-5">
          {mayDecide && (
            <div className="flex items-start justify-between gap-4">
              <div>
                <Label htmlFor="cap-decide">Record decisions and offers</Label>
                <p className="text-xs text-muted-foreground">
                  Accept, waitlist or reject, and generate or reset offers.
                </p>
              </div>
              <Switch id="cap-decide" checked={canDecide} onCheckedChange={setCanDecide} />
            </div>
          )}

          {offerHealth && (
            <div className="flex items-start justify-between gap-4">
              <div>
                <Label htmlFor="cap-health">View child health information</Label>
                <p className="text-xs text-muted-foreground">
                  {healthHasEffect
                    ? "Only for applications this person can already see."
                    : `Has no effect: a ${role} sees no admissions records. Switch off to revoke.`}
                </p>
              </div>
              <Switch id="cap-health" checked={canViewHealth} onCheckedChange={setCanViewHealth} />
            </div>
          )}

          {isOfficer && (
            <div className="space-y-2">
              <Label>Applications they can see</Label>
              <RadioGroup value={scope} onValueChange={(v) => setScope(v as Scope)}>
                <label className="flex items-center gap-2 text-sm">
                  <RadioGroupItem value="none" /> None
                </label>
                <label className="flex items-center gap-2 text-sm">
                  <RadioGroupItem value="bands" /> Specific grade bands
                </label>
                <label className="flex items-center gap-2 text-sm">
                  <RadioGroupItem value="all" /> All grades, including SHS and other grades
                </label>
              </RadioGroup>
              {scope === "bands" && (
                <div className="space-y-1.5 pl-6">
                  {GRADE_BANDS.map((band) => (
                    <label key={band} className="flex items-center gap-2 text-sm">
                      <Checkbox
                        checked={bands.includes(band)}
                        onCheckedChange={(checked) => toggleBand(band, checked === true)}
                      />
                      {BAND_LABELS[band]}
                      <span className="text-xs text-muted-foreground">
                        {bandRangeLabel(grades, band)}
                      </span>
                    </label>
                  ))}
                </div>
              )}
            </div>
          )}

          {error ? <p className="text-sm font-medium text-destructive">{error}</p> : null}
        </div>
      )}

      <DialogFooter>
        <Button variant="outline" onClick={onDone} disabled={saving}>
          Cancel
        </Button>
        {!nothingToOffer && (
          <Button onClick={save} disabled={saving}>
            {saving ? "Saving…" : "Save"}
          </Button>
        )}
      </DialogFooter>
    </DialogContent>
  );
}
