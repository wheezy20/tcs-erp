import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowLeft, Lock } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { useEmployees } from "@/data/employees-store";
import { useStaff } from "@/data/staff-store";

export const Route = createFileRoute("/staff/$staffId")({
  head: () => ({ meta: [{ title: "Login account — TCS" }] }),
  component: LoginAccountPage,
});

// A `staff` row is an ERP login only (20260909130000). Contact / org
// placement and pay data live on the linked `employees` record, if any.
function LoginAccountPage() {
  const { staffId } = Route.useParams();
  const { staff: roster, pendingIds, loading } = useStaff();
  const { employees } = useEmployees();

  const member = roster.find((s) => s.id === staffId);

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  if (!member) {
    return (
      <>
        <BackLink />
        <PageHeader
          title="Login account not found"
          description={`No account matches ${staffId}.`}
        />
      </>
    );
  }

  const pending = pendingIds.has(member.id);
  const linkedEmployee = member.employeeId
    ? employees.find((e) => e.id === member.employeeId)
    : undefined;

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

      <div className="grid gap-6 lg:grid-cols-2">
        <section className="card-surface p-6">
          <h2 className="text-sm font-semibold">Account</h2>
          <dl className="mt-4 space-y-4">
            <Row label="Sign-in email" value={member.email} />
            <Row label="Role" value={member.role} hint="Changed in Settings → Staff." />
            <Row
              label="Status"
              value={pending ? "Invite pending" : member.active ? "Active" : "Inactive"}
            />
          </dl>
          <Link to="/settings" className="mt-4 inline-block text-sm text-primary hover:underline">
            Manage role &amp; access →
          </Link>
        </section>

        <section className="card-surface p-6">
          <h2 className="text-sm font-semibold">Linked employee</h2>
          {linkedEmployee ? (
            <>
              <p className="mt-3 text-sm">
                This login belongs to{" "}
                <Link
                  to="/employees/$employeeId"
                  params={{ employeeId: linkedEmployee.id }}
                  className="font-medium text-primary hover:underline"
                >
                  {linkedEmployee.name}
                </Link>
                {linkedEmployee.position ? ` · ${linkedEmployee.position}` : ""}.
              </p>
              <p className="mt-2 text-xs text-muted-foreground">
                Contact details and pay configuration are managed on the employee record.
              </p>
            </>
          ) : (
            <p className="mt-3 text-sm text-muted-foreground">
              Not linked to an employee record. Create one from{" "}
              <Link to="/employees" className="text-primary hover:underline">
                Employees
              </Link>{" "}
              if this person is also paid by TCS.
            </p>
          )}
        </section>
      </div>
    </>
  );
}

function Row({ label, value, hint }: { label: string; value: string; hint?: string }) {
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
      <ArrowLeft className="size-4" /> Back to login accounts
    </Link>
  );
}
