import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowLeft, Receipt } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { VoidTransactionDialog } from "@/components/void-transaction-dialog";
import { canWriteFinancials, useAuth } from "@/data/auth-store";
import { currencyPrecise } from "@/data/dashboard";
import { useExpenses, voidExpense } from "@/data/expenses-store";
import { formatDate, useDocumentSettings } from "@/data/settings-store";

export const Route = createFileRoute("/expenses/$expenseId")({
  head: ({ params }) => {
    const description = `Full details, receipt and audit trail for expense ${params.expenseId}.`;
    return {
      meta: [
        { title: `${params.expenseId} — Expenses — TCS` },
        { name: "description", content: description },
        { property: "og:title", content: `${params.expenseId} — Expenses — TCS` },
        { property: "og:description", content: description },
      ],
    };
  },
  component: ExpenseDetail,
});

function ExpenseDetail() {
  const { expenseId } = Route.useParams();
  const { expenses } = useExpenses();
  const { staff } = useAuth();
  const canWrite = canWriteFinancials(staff?.role);
  const settings = useDocumentSettings();
  const expense = expenses.find((e) => e.id === expenseId);

  if (!expense) {
    return (
      <>
        <BackLink />
        <PageHeader title="Expense not found" description={`No expense matches ${expenseId}.`} />
      </>
    );
  }

  const recordedAt = new Date(expense.recordedAt).toLocaleString("en-GB", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "UTC",
  });

  return (
    <>
      <BackLink />
      <PageHeader
        title={expense.description}
        description={`${expense.id} · ${expense.category}`}
        actions={
          !expense.voidedAt && canWrite ? (
            <VoidTransactionDialog
              kind="expense"
              id={expense.id}
              onVoid={(reason) => voidExpense(expense.id, reason)}
            />
          ) : undefined
        }
      />

      {expense.voidedAt && (
        <div className="mb-6 rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm">
          <span className="font-semibold text-destructive">This expense was voided</span>
          {expense.voidedBy ? ` by ${expense.voidedBy}` : ""} on{" "}
          {new Date(expense.voidedAt).toLocaleDateString()}. Its ledger entry was reversed and it no
          longer counts as a cost.
          {expense.voidReason ? (
            <span className="mt-1 block text-muted-foreground">Reason: {expense.voidReason}</span>
          ) : null}
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="card-surface space-y-4 p-6 lg:col-span-2">
          <div>
            <p className="text-sm text-muted-foreground">Amount</p>
            <p className="mt-1 text-3xl font-semibold tracking-tight">
              {currencyPrecise(expense.amount)}
            </p>
          </div>

          <dl className="grid gap-x-6 gap-y-4 border-t pt-4 sm:grid-cols-2">
            <Field
              label="Date"
              value={formatDate(expense.date, settings.localisation.dateFormat)}
            />
            <Field label="Category" value={expense.category} />
            <Field label="Payment method" value={expense.method} />
            <Field label="Reference" value={expense.reference ?? "—"} />
            <Field label="Description" value={expense.description} />
            <Field
              label="Cash impact"
              value={
                expense.voidedAt
                  ? "Voided — no longer affects cash on hand"
                  : expense.method === "Cash"
                    ? "Reduces cash on hand"
                    : "Settled outside the till"
              }
            />
          </dl>

          <div className="rounded-xl border bg-muted/40 p-4">
            <p className="text-sm font-medium">Audit trail</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Recorded by {expense.recordedBy} on {recordedAt}.
            </p>
          </div>
        </div>

        <div className="card-surface p-6">
          <p className="text-sm font-medium">Receipt</p>
          {expense.receiptUrl ? (
            <img
              src={expense.receiptUrl}
              alt={`Receipt for ${expense.description}`}
              className="mt-3 w-full rounded-xl border object-contain"
            />
          ) : (
            <div className="mt-3 flex flex-col items-center gap-2 rounded-xl border border-dashed px-4 py-12 text-center">
              <div className="flex size-12 items-center justify-center rounded-2xl bg-muted">
                <Receipt className="size-5 text-muted-foreground" />
              </div>
              <p className="text-sm text-muted-foreground">No receipt image was attached.</p>
            </div>
          )}
        </div>
      </div>
    </>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd className="mt-1 text-sm font-medium">{value}</dd>
    </div>
  );
}

function BackLink() {
  return (
    <Link
      to="/expenses"
      className="mb-4 inline-flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground"
    >
      <ArrowLeft className="size-4" /> Back to expenses
    </Link>
  );
}
