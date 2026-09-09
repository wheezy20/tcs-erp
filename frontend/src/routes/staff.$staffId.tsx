import { useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowLeft, Lock } from "lucide-react";
import { toast } from "sonner";

import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useAuth } from "@/data/auth-store";
import { currentConfigFor, usePayroll } from "@/data/payroll-store";
import { updateStaffProfile, useStaff } from "@/data/staff-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/staff/$staffId")({
  head: () => ({ meta: [{ title: "Staff profile — TCS" }] }),
  component: StaffProfilePage,
});

function StaffProfilePage() {
  const { staffId } = Route.useParams();
  const { staff: currentStaff } = useAuth();
  const { staff: roster, pendingIds, loading } = useStaff();
  const { payConfigs } = usePayroll();

  const canEdit = currentStaff?.role === "Manager";
  const member = roster.find((s) => s.id === staffId);

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  if (!member) {
    return (
      <>
        <BackLink />
        <PageHeader
          title="Staff member not found"
          description={`No staff record matches ${staffId}.`}
        />
      </>
    );
  }

  const config = currentConfigFor(payConfigs, member.id);
  const pending = pendingIds.has(member.id);

  return (
    <>
      <BackLink />
      <PageHeader title={member.name} description={member.email} />

      <div className="mb-6 flex flex-wrap items-center gap-2">
        <Badge variant="outline">{member.role}</Badge>
        {member.protected && (
          <Badge variant="outline" className="gap-1">
            <Lock className="size-3" /> Protected
          </Badge>
        )}
        <Badge variant={pending ? "outline" : member.active ? "secondary" : "outline"}>
          {pending ? "Invite pending" : member.active ? "Active" : "Inactive"}
        </Badge>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <ProfileForm key={member.id} member={member} canEdit={canEdit} />
        </div>

        <div className="space-y-6">
          <section className="card-surface p-6">
            <h2 className="text-sm font-semibold">Account</h2>
            <dl className="mt-4 space-y-4">
              <ReadOnly
                label="Sign-in email"
                value={member.email}
                hint="Changing this is a re-invite, not an edit here."
              />
              <ReadOnly label="Role" value={member.role} hint="Set in Settings → Staff." />
              <ReadOnly
                label="Status"
                value={pending ? "Invite pending" : member.active ? "Active" : "Inactive"}
              />
            </dl>
            <Link to="/settings" className="mt-4 inline-block text-sm text-primary hover:underline">
              Manage role &amp; access →
            </Link>
          </section>

          <section className="card-surface p-6">
            <h2 className="text-sm font-semibold">Pay &amp; bank</h2>
            <dl className="mt-4 space-y-4">
              <ReadOnly label="Bank" value={config?.bank ?? "Not set"} />
              <ReadOnly label="Account number" value={config?.accountNo ?? "Not set"} />
              <ReadOnly
                label="Basic salary"
                value={
                  config ? `GH₵ ${config.basicSalary.toLocaleString("en-GB")}` : "No pay config"
                }
              />
            </dl>
            <p className="mt-3 text-xs text-muted-foreground">
              Bank details are effective-dated pay data, edited on Pay Config so historical payslips
              stay tied to the details they were paid against.
            </p>
            <Link
              to="/payroll/pay-config"
              className="mt-3 inline-block text-sm text-primary hover:underline"
            >
              Open Pay Config →
            </Link>
          </section>
        </div>
      </div>
    </>
  );
}

function ProfileForm({
  member,
  canEdit,
}: {
  member: { id: string; phone: string | null; position: string | null; department: string | null };
  canEdit: boolean;
}) {
  const [phone, setPhone] = useState(member.phone ?? "");
  const [position, setPosition] = useState(member.position ?? "");
  const [department, setDepartment] = useState(member.department ?? "");
  const [saving, setSaving] = useState(false);

  const dirty =
    phone !== (member.phone ?? "") ||
    position !== (member.position ?? "") ||
    department !== (member.department ?? "");

  async function save() {
    setSaving(true);
    try {
      await updateStaffProfile(member.id, { phone, position, department });
      toast.success("Profile updated");
    } catch (err) {
      toast.error("Could not save the profile", {
        description: getErrorMessage(err, "Something went wrong."),
      });
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="card-surface p-6">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 className="text-sm font-semibold">Contact &amp; placement</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            {canEdit
              ? "Phone, position and department. Saved to the staff record."
              : "Read-only — only a Manager can edit staff records."}
          </p>
        </div>
      </div>

      <div className="mt-5 grid gap-5 sm:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor="staff-phone">Phone</Label>
          <Input
            id="staff-phone"
            value={phone}
            disabled={!canEdit}
            maxLength={40}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="e.g. +233 24 000 0000"
          />
        </div>
        <div />
        <div className="space-y-2">
          <Label htmlFor="staff-position">Position</Label>
          <Input
            id="staff-position"
            value={position}
            disabled={!canEdit}
            maxLength={80}
            onChange={(e) => setPosition(e.target.value)}
            placeholder="e.g. Class Teacher"
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="staff-department">Department</Label>
          <Input
            id="staff-department"
            value={department}
            disabled={!canEdit}
            maxLength={80}
            onChange={(e) => setDepartment(e.target.value)}
            placeholder="e.g. Lower Primary"
          />
        </div>
      </div>

      {canEdit && (
        <div className="mt-6 flex items-center gap-3">
          <Button onClick={save} disabled={!dirty || saving}>
            {saving ? "Saving…" : "Save changes"}
          </Button>
          {dirty && !saving && (
            <button
              type="button"
              className="text-sm text-muted-foreground hover:text-foreground"
              onClick={() => {
                setPhone(member.phone ?? "");
                setPosition(member.position ?? "");
                setDepartment(member.department ?? "");
              }}
            >
              Reset
            </button>
          )}
        </div>
      )}
    </section>
  );
}

function ReadOnly({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd className="mt-1 text-sm font-medium">{value}</dd>
      {hint && <dd className="mt-0.5 text-xs text-muted-foreground">{hint}</dd>}
    </div>
  );
}

function BackLink() {
  return (
    <Link
      to="/staff"
      className="mb-4 inline-flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground"
    >
      <ArrowLeft className="size-4" /> Back to staff
    </Link>
  );
}
