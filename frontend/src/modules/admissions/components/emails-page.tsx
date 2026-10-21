import { useMemo, useState } from "react";
import { Link } from "@tanstack/react-router";
import { RefreshCw } from "lucide-react";
import { toast } from "sonner";

import { PageHeader } from "@/components/page-header";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { cn, getErrorMessage } from "@/lib/utils";
import { RoleBlockedPanel } from "@/modules/admissions/components/role-blocked-panel";
import {
  getEmailHealth,
  listEmails,
  retryEmails,
  type EmailRow,
} from "@/modules/admissions/data/emails";
import {
  EMAIL_ERROR_LABELS,
  EMAIL_FILTERS,
  EMAIL_KIND_LABELS,
  EMAIL_STATUS_LABELS,
  EMAIL_STATUS_NOTES,
  canRetryEmail,
  healthMessages,
  recipientLabel,
  statusNote,
  statusTone,
  type EmailHealth,
  type EmailStatus,
  type Tone,
} from "@/modules/admissions/emails";
import { useAdmissionsAccess } from "@/modules/admissions/hooks/use-admissions-access";
import { useLoad, type LoadState } from "@/modules/admissions/hooks/use-load";
import { canViewAdmissionsEmails } from "@/modules/admissions/permissions";

const dateTime = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });

const TONE_TEXT: Record<Tone, string> = {
  ok: "text-muted-foreground",
  waiting: "text-foreground",
  problem: "text-destructive",
  none: "text-muted-foreground",
};

/** /admissions/emails (slice 12). Manager and Auditor see the admissions
 * email log with masked recipients and a health summary; a Manager can
 * retry failed emails. Every other role gets the blocked panel and the
 * content (with its queries) never mounts. */
export function AdmissionsEmailsPage() {
  const { role } = useAdmissionsAccess();
  if (!canViewAdmissionsEmails(role)) {
    return (
      <RoleBlockedPanel
        title="Admissions emails"
        description="Confirmation emails to parents and alerts to staff."
        what="Admissions emails"
        openTo="Managers and Auditors"
      />
    );
  }
  return <EmailsContent role={role} />;
}

function EmailsContent({ role }: { role: string | null | undefined }) {
  const [filter, setFilter] = useState<EmailStatus | "all">("all");
  const health = useLoad(getEmailHealth, [], "Could not load the email summary.");
  const rows = useLoad(
    () => listEmails(filter === "all" ? null : filter),
    [filter],
    "Could not load the email log.",
  );
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const isManager = role === "Manager";

  const retryable = useMemo(
    () => (rows.data ?? []).filter((r) => canRetryEmail(role, r.status)),
    [rows.data, role],
  );
  const chosen = retryable.filter((r) => selected.has(r.id));

  async function reload() {
    await Promise.all([health.reload(), rows.reload()]);
  }

  async function retry() {
    setBusy(true);
    try {
      const n = await retryEmails(chosen.map((r) => r.id));
      toast.success(
        n === 1 ? "1 email put back in the queue" : `${n} emails put back in the queue`,
      );
      setSelected(new Set());
      await reload();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not retry these emails."));
    } finally {
      setBusy(false);
      setConfirming(false);
    }
  }

  function toggle(id: string, on: boolean) {
    setSelected((s) => {
      const next = new Set(s);
      if (on) next.add(id);
      else next.delete(id);
      return next;
    });
  }

  return (
    <>
      <PageHeader
        title="Admissions emails"
        description="Confirmation emails to parents and alerts to staff. Addresses are partly hidden."
        actions={
          <>
            {!isManager && <Badge variant="outline">Read-only</Badge>}
            <Button
              variant="outline"
              size="sm"
              onClick={reload}
              disabled={health.loading || rows.loading}
            >
              <RefreshCw className="size-4" /> Refresh
            </Button>
          </>
        }
      />
      <div className="grid gap-6">
        <HealthStrip health={health} />

        <section className="card-surface overflow-hidden">
          <div className="flex flex-wrap items-center justify-between gap-4 border-b p-6">
            <div className="flex items-center gap-3">
              <h2 className="text-sm font-semibold">Email log</h2>
              <Select
                value={filter}
                onValueChange={(v) => {
                  setFilter(v as EmailStatus | "all");
                  setSelected(new Set());
                }}
              >
                <SelectTrigger className="h-8 w-56" aria-label="Show emails">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {EMAIL_FILTERS.map((f) => (
                    <SelectItem key={f.value} value={f.value}>
                      {f.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            {isManager && retryable.length > 0 && (
              <Button
                size="sm"
                disabled={busy || chosen.length === 0}
                onClick={() => setConfirming(true)}
              >
                Retry selected ({chosen.length})
              </Button>
            )}
          </div>
          {filter === "expired" && (
            <p className="border-b bg-muted/40 px-6 py-3 text-sm">
              {EMAIL_STATUS_NOTES.expired} Contact the family another way if they still need it.
            </p>
          )}
          {rows.error && <p className="px-6 py-4 text-sm text-destructive">{rows.error}</p>}
          {rows.data && rows.data.length === 0 && (
            <p className="px-6 py-8 text-center text-sm text-muted-foreground">
              No emails to show.
            </p>
          )}
          {rows.data && rows.data.length > 0 && (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="border-b text-left text-xs text-muted-foreground">
                  <tr>
                    {isManager && <th className="w-10 px-4 py-2" />}
                    <th className="px-4 py-2 font-medium">Queued</th>
                    <th className="px-4 py-2 font-medium">Email</th>
                    <th className="px-4 py-2 font-medium">To</th>
                    <th className="px-4 py-2 font-medium">References</th>
                    <th className="px-4 py-2 font-medium">Status</th>
                    <th className="px-4 py-2 font-medium">Attempts</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {rows.data.map((r) => (
                    <EmailLogRow
                      key={r.id}
                      row={r}
                      showSelect={isManager}
                      selectable={canRetryEmail(role, r.status)}
                      selected={selected.has(r.id)}
                      onSelect={(on) => toggle(r.id, on)}
                    />
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      </div>

      <AlertDialog open={confirming} onOpenChange={(o) => !busy && !o && setConfirming(false)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Retry {chosen.length === 1 ? "this email" : `${chosen.length} emails`}?
            </AlertDialogTitle>
            <AlertDialogDescription>
              They go back in the queue with a fresh set of attempts and are sent on the next run.
              If an address was refused, fix it on the record first or the retry will fail again.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={busy}>Cancel</AlertDialogCancel>
            <AlertDialogAction disabled={busy} onClick={retry}>
              Retry
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

function HealthStrip({ health }: { health: LoadState<EmailHealth> }) {
  if (health.error) {
    return (
      <section className="card-surface p-6">
        <p className="text-sm text-destructive">{health.error}</p>
      </section>
    );
  }
  if (!health.data) return null;
  const h = health.data;
  const messages = healthMessages(h, new Date());
  const counts: Array<[string, number]> = [
    ["Waiting", h.waiting],
    ["Failed", h.failed],
    ["Expired", h.expired],
    ["Address limit", h.suppressed],
    ["Saved application links failed", h.draftFailed],
  ];
  return (
    <section className="card-surface p-6">
      <div className="flex flex-wrap items-baseline justify-between gap-4">
        <h2 className="text-sm font-semibold">Sending</h2>
        <p className="text-xs text-muted-foreground">
          Last run {h.lastRunAt ? dateTime.format(new Date(h.lastRunAt)) : "never"} · last sent{" "}
          {h.lastSuccessAt ? dateTime.format(new Date(h.lastSuccessAt)) : "never"}
        </p>
      </div>
      <dl className="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
        {counts.map(([label, n]) => (
          <div key={label}>
            <dt className="text-xs text-muted-foreground">{label}</dt>
            <dd
              className={cn(
                "text-2xl font-semibold tabular-nums",
                n > 0 && label !== "Waiting" && "text-destructive",
              )}
            >
              {n}
            </dd>
          </div>
        ))}
      </dl>
      <ul className="mt-4 space-y-1">
        {messages.map((m) => (
          <li key={m.text} className={cn("text-sm", TONE_TEXT[m.tone])}>
            {m.text}
          </li>
        ))}
      </ul>
    </section>
  );
}

function EmailLogRow({
  row,
  showSelect,
  selectable,
  selected,
  onSelect,
}: {
  row: EmailRow;
  showSelect: boolean;
  selectable: boolean;
  selected: boolean;
  onSelect: (on: boolean) => void;
}) {
  const status = row.status as EmailStatus;
  const tone = statusTone(row.status);
  const error = row.lastErrorClass
    ? `${EMAIL_ERROR_LABELS[row.lastErrorClass] ?? row.lastErrorClass}${row.lastHttpStatus ? ` (${row.lastHttpStatus})` : ""}`
    : null;
  return (
    <tr className={cn(status === "expired" && "bg-muted/40")}>
      {showSelect && (
        <td className="px-4 py-3 align-top">
          {selectable && (
            <Checkbox
              checked={selected}
              onCheckedChange={(v) => onSelect(v === true)}
              aria-label={`Select ${row.references.join(", ")}`}
            />
          )}
        </td>
      )}
      <td className="whitespace-nowrap px-4 py-3 align-top">
        {dateTime.format(new Date(row.createdAt))}
      </td>
      <td className="px-4 py-3 align-top">{EMAIL_KIND_LABELS[row.kind] ?? row.kind}</td>
      <td className="px-4 py-3 align-top font-mono text-xs">
        {recipientLabel(row.kind, row.recipientMasked)}
      </td>
      <td className="px-4 py-3 align-top">
        {row.references.map((ref, i) =>
          row.applicationIds[i] ? (
            <Link
              key={ref}
              to="/admissions/$applicationId"
              params={{ applicationId: row.applicationIds[i] }}
              className="mr-2 underline-offset-2 hover:underline"
            >
              {ref}
            </Link>
          ) : (
            <span key={ref} className="mr-2">
              {ref}
            </span>
          ),
        )}
      </td>
      <td className="px-4 py-3 align-top">
        <Badge
          variant={tone === "problem" ? "destructive" : tone === "ok" ? "secondary" : "outline"}
          className={cn(
            status === "expired" && "bg-muted text-foreground line-through decoration-1",
          )}
        >
          {EMAIL_STATUS_LABELS[status] ?? row.status}
        </Badge>
        {row.sentAt && (
          <p className="mt-1 text-xs text-muted-foreground">
            {dateTime.format(new Date(row.sentAt))}
          </p>
        )}
        {status === "pending" && row.attempts > 0 && (
          <p className="mt-1 text-xs text-muted-foreground">
            Next try {dateTime.format(new Date(row.nextAttemptAt))}
          </p>
        )}
        {statusNote(row.kind, status) && (
          <p className="mt-1 max-w-xs text-xs text-muted-foreground">
            {statusNote(row.kind, status)}
          </p>
        )}
        {error && <p className="mt-1 text-xs text-muted-foreground">{error}</p>}
        {row.requeuedAt && (
          <p className="mt-1 text-xs text-muted-foreground">
            Retried {dateTime.format(new Date(row.requeuedAt))}
          </p>
        )}
      </td>
      <td className="px-4 py-3 align-top tabular-nums">{row.attempts}</td>
    </tr>
  );
}
