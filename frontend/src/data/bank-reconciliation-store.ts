import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

export type StatementLineStatus = "unmatched" | "matched" | "cleared";

export type BankStatementLine = {
  id: string;
  bankAccountId: string;
  date: string;
  description: string;
  amount: number;
  reference: string;
  status: StatementLineStatus;
  matchedJournalLineId: string | null;
  clearNote: string;
  reconciliationId: string | null;
  matchedBy: string | null;
  matchedAt: string | null;
  importedBy: string;
  createdAt: string;
};

export type BankReconciliation = {
  id: string;
  bankAccountId: string;
  statementDate: string;
  statementEndingBalance: number;
  openingBalance: number;
  reconciledBalance: number | null;
  difference: number | null;
  startedBy: string;
  startedAt: string;
  completedBy: string | null;
  completedAt: string | null;
  notes: string;
};

type StatementLineRow = Database["public"]["Tables"]["bank_statement_lines"]["Row"] & {
  staff: { name: string } | null;
};
type ReconciliationRow = Database["public"]["Tables"]["bank_reconciliations"]["Row"] & {
  starter: { name: string } | null;
  completer: { name: string } | null;
};

function mapLine(row: StatementLineRow): BankStatementLine {
  return {
    id: row.id,
    bankAccountId: row.bank_account_id,
    date: row.date,
    description: row.description,
    amount: Number(row.amount),
    reference: row.reference,
    status: row.status as StatementLineStatus,
    matchedJournalLineId: row.matched_journal_line_id,
    clearNote: row.clear_note,
    reconciliationId: row.reconciliation_id,
    matchedBy: row.staff?.name ?? null,
    matchedAt: row.matched_at,
    importedBy: row.imported_by,
    createdAt: row.created_at,
  };
}

function mapReconciliation(row: ReconciliationRow): BankReconciliation {
  return {
    id: row.id,
    bankAccountId: row.bank_account_id,
    statementDate: row.statement_date,
    statementEndingBalance: Number(row.statement_ending_balance),
    openingBalance: Number(row.opening_balance),
    reconciledBalance: row.reconciled_balance === null ? null : Number(row.reconciled_balance),
    difference: row.difference === null ? null : Number(row.difference),
    startedBy: row.starter?.name ?? "Unknown",
    startedAt: row.started_at,
    completedBy: row.completer?.name ?? (row.completed_by ? "Unknown" : null),
    completedAt: row.completed_at,
    notes: row.notes,
  };
}

type BankReconciliationState = {
  lines: BankStatementLine[];
  reconciliations: BankReconciliation[];
  loading: boolean;
  error: string | null;
};

let state: BankReconciliationState = {
  lines: [],
  reconciliations: [],
  loading: true,
  error: null,
};

const listeners = new Set<() => void>();

function setState(next: BankReconciliationState) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function loadAll() {
  const [linesResult, reconResult] = await Promise.all([
    supabase
      .from("bank_statement_lines")
      // Two FKs into staff (imported_by, matched_by) — the same ambiguous-
      // embed shape (PGRST201) hit before in this codebase; qualify the
      // one actually used (matched_by) explicitly.
      .select("*, staff!bank_statement_lines_matched_by_fkey(name)")
      .order("date", { ascending: false }),
    supabase
      .from("bank_reconciliations")
      // Two FKs into staff (started_by, completed_by) — the same
      // ambiguous-embed shape day_closes hit (opener/closer), qualified
      // the same way here.
      .select(
        "*, starter:staff!bank_reconciliations_started_by_fkey(name), completer:staff!bank_reconciliations_completed_by_fkey(name)",
      )
      .order("statement_date", { ascending: false }),
  ]);
  if (linesResult.error) throw linesResult.error;
  if (reconResult.error) throw reconResult.error;
  setState({
    lines: (linesResult.data as StatementLineRow[]).map(mapLine),
    reconciliations: (reconResult.data as unknown as ReconciliationRow[]).map(mapReconciliation),
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadAll().catch((err) => {
      loadPromise = null;
      setState({
        ...state,
        loading: false,
        error: err instanceof Error ? err.message : String(err),
      });
      throw err;
    });
  }
  return loadPromise;
}

async function reload() {
  loadPromise = null;
  await ensureLoaded();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  ensureLoaded();
  return () => listeners.delete(listener);
}

function getSnapshot() {
  return state;
}

/** Every bank statement line and every reconciliation session, across every
 * bank account — RLS restricts both to Manager/Accountant-Auditor, same as
 * bank_accounts. Callers filter down to one bank account client-side, the
 * same pattern accounting.ledger.tsx uses for one account's journal lines. */
export function useBankReconciliationData() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

export type NewStatementLine = {
  date: string;
  description: string;
  amount: number;
  reference?: string;
};

/** One RPC for both a single manual entry and a bulk CSV import — the
 * frontend just calls it with a one-element array for the former, the same
 * addProduct()/addProducts() batching precedent Sessions 1-2 established. */
export async function importBankStatementLines(
  bankAccountId: string,
  lines: NewStatementLine[],
): Promise<void> {
  const { error } = await supabase.rpc("import_bank_statement_lines", {
    p_bank_account_id: bankAccountId,
    p_lines: lines.map((l) => ({
      date: l.date,
      description: l.description,
      amount: l.amount,
      reference: l.reference ?? "",
    })),
  });
  if (error) throw error;
  await reload();
}

export async function addStatementLine(
  bankAccountId: string,
  line: NewStatementLine,
): Promise<void> {
  await importBankStatementLines(bankAccountId, [line]);
}

export async function startBankReconciliation(input: {
  bankAccountId: string;
  statementDate: string;
  statementEndingBalance: number;
}): Promise<BankReconciliation> {
  const { data, error } = await supabase.rpc("start_bank_reconciliation", {
    p_bank_account_id: input.bankAccountId,
    p_statement_date: input.statementDate,
    p_statement_ending_balance: input.statementEndingBalance,
  });
  if (error) throw error;
  await reload();
  const row = (Array.isArray(data) ? data[0] : data) as { id: string } | null | undefined;
  const created = state.reconciliations.find((r) => r.id === row?.id);
  if (!created)
    throw new Error("Reconciliation was started but could not be found after reloading.");
  return created;
}

export async function matchStatementLine(lineId: string, journalLineId: string): Promise<void> {
  const { error } = await supabase.rpc("match_statement_line", {
    p_line_id: lineId,
    p_journal_line_id: journalLineId,
  });
  if (error) throw error;
  await reload();
}

export async function clearStatementLine(lineId: string, note: string): Promise<void> {
  const { error } = await supabase.rpc("clear_statement_line", {
    p_line_id: lineId,
    p_note: note,
  });
  if (error) throw error;
  await reload();
}

export async function unmatchStatementLine(lineId: string): Promise<void> {
  const { error } = await supabase.rpc("unmatch_statement_line", { p_line_id: lineId });
  if (error) throw error;
  await reload();
}

/** Structurally can't succeed unless every in-scope line is resolved and
 * the reconciled balance ties to the entered statement balance to the
 * cent — see the migration header for why. */
export async function completeBankReconciliation(reconciliationId: string): Promise<void> {
  const { error } = await supabase.rpc("complete_bank_reconciliation", {
    p_reconciliation_id: reconciliationId,
  });
  if (error) throw error;
  await reload();
}

/** The sanctioned way to undo a session that was started by mistake — resets
 * every line it had resolved back to unmatched, then removes the session.
 * A completed session has no equivalent; that's permanent. */
export async function cancelBankReconciliation(reconciliationId: string): Promise<void> {
  const { error } = await supabase.rpc("cancel_bank_reconciliation", {
    p_reconciliation_id: reconciliationId,
  });
  if (error) throw error;
  await reload();
}
