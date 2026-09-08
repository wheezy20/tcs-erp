import { useSyncExternalStore } from "react";

import type { Account } from "@/data/accounts-store";
import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

export type JournalLine = {
  id: string;
  position: number;
  accountId: string;
  accountCode: string;
  accountName: string;
  debit: number;
  credit: number;
  description: string;
};

export type JournalEntry = {
  id: string;
  branchId: string;
  entryDate: string;
  description: string;
  reference: string | null;
  reversesEntryId: string | null;
  reversedByEntryId: string | null;
  sourceTable: string | null;
  sourceId: string | null;
  /** True when this entry's COGS/inventory figure was computed against one
   * or more products with no recorded cost price (treated as 0 for
   * posting purposes) — the posted amount is a known underestimate, not a
   * confirmed figure. Always false for a manually-posted entry. */
  costDataIncomplete: boolean;
  createdBy: string;
  createdAt: string;
  lines: JournalLine[];
};

const SOURCE_LABELS: Record<string, string> = {
  sales: "POS sale",
  invoices: "Invoice",
  invoice_payments: "Invoice payment",
  expenses: "Expense",
  sale_returns: "Return",
  stock_movements: "Stock adjustment",
  day_closes: "End of day",
  bank_deposits: "Bank deposit",
};

/** "Manual" for anything a Manager posted by hand (post_journal_entry()
 * never sets source_table/source_id at all); otherwise a friendly label for
 * which Session 14 auto-poster produced it — see data/journal-store.ts and
 * the auto_posting_integration migration for the full mapping. */
export function sourceLabel(entry: Pick<JournalEntry, "sourceTable">): string {
  if (!entry.sourceTable) return "Manual";
  return SOURCE_LABELS[entry.sourceTable] ?? entry.sourceTable;
}

type EntryRow = Database["public"]["Tables"]["journal_entries"]["Row"];
type LineRow = Database["public"]["Tables"]["journal_lines"]["Row"];
type LineRowWithAccount = LineRow & { accounts: { code: string; name: string } | null };
type EntryRowWithStaffAndLines = EntryRow & {
  staff: { name: string } | null;
  journal_lines: LineRowWithAccount[];
};

function mapEntryRow(
  row: EntryRowWithStaffAndLines,
  reversedBy: Map<string, string>,
): JournalEntry {
  return {
    id: row.id,
    branchId: row.branch_id,
    entryDate: row.entry_date,
    description: row.description,
    reference: row.reference,
    reversesEntryId: row.reverses_entry_id,
    reversedByEntryId: reversedBy.get(row.id) ?? null,
    sourceTable: row.source_table,
    sourceId: row.source_id,
    costDataIncomplete: row.cost_data_incomplete,
    createdBy: row.staff?.name ?? "Unknown",
    createdAt: row.created_at,
    lines: [...row.journal_lines]
      .sort((a, b) => a.position - b.position)
      .map((line) => ({
        id: line.id,
        position: line.position,
        accountId: line.account_id,
        accountCode: line.accounts?.code ?? "?",
        accountName: line.accounts?.name ?? "Unknown account",
        debit: Number(line.debit),
        credit: Number(line.credit),
        description: line.description,
      })),
  };
}

type JournalState = {
  entries: JournalEntry[];
  loading: boolean;
  error: string | null;
};

let state: JournalState = { entries: [], loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: JournalState) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function loadJournal() {
  const { data, error } = await supabase
    .from("journal_entries")
    .select("*, staff(name), journal_lines(*, accounts(code, name))")
    .order("entry_date", { ascending: false })
    .order("created_at", { ascending: false });
  if (error) throw error;

  const rows = data as unknown as EntryRowWithStaffAndLines[];
  // "Reversed by" is the inverse of reverses_entry_id — every entry knows
  // what it reverses, but not (without this) what reversed it. Built once
  // client-side from the same already-loaded rows rather than a second
  // query or a stored column, since it's a pure derivation.
  const reversedBy = new Map<string, string>();
  for (const row of rows) {
    if (row.reverses_entry_id) reversedBy.set(row.reverses_entry_id, row.id);
  }

  setState({
    entries: rows.map((row) => mapEntryRow(row, reversedBy)),
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadJournal().catch((err) => {
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

/** Every journal entry, every line, newest first. RLS's *_select policies
 * are what actually restrict this to Manager/Accountant-Auditor — Attendant
 * gets an empty list back, same as accounts. */
export function useJournalEntries() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

export type NewJournalLine = {
  accountId: string;
  debit: number;
  credit: number;
  description?: string;
};

export type NewJournalEntry = {
  date: string;
  description: string;
  reference?: string;
  lines: NewJournalLine[];
};

/** Manager-only, enforced server-side by post_journal_entry() — create-
 * can't-overwrite discipline (no client-supplied id/number) and the real
 * "can't post unbalanced" invariant is a deferred constraint trigger on
 * journal_lines, not just this call's own validation. */
export async function postJournalEntry(input: NewJournalEntry): Promise<JournalEntry> {
  const { data, error } = await supabase.rpc("post_journal_entry", {
    p_date: input.date,
    p_description: input.description,
    // post_journal_entry() itself treats an empty/whitespace-only
    // reference as "none" (nullif(trim(...), '')) — passing "" here
    // achieves the same thing while staying within the generated Args
    // type, which (a quirk of `supabase gen types` for `text default
    // null` parameters) is typed as plain `string`, not `string | null`.
    p_reference: input.reference ?? "",
    p_lines: input.lines.map((l) => ({
      account_id: l.accountId,
      debit: l.debit,
      credit: l.credit,
      description: l.description ?? "",
    })),
  });
  if (error) throw error;

  const row = (Array.isArray(data) ? data[0] : data) as { id: string } | null | undefined;
  if (!row?.id) throw new Error("Entry was posted but no id was returned.");

  await reload();
  const posted = state.entries.find((e) => e.id === row.id);
  if (!posted) throw new Error("Entry was posted but could not be found after reloading.");
  return posted;
}

/** "Once posted, immutable — a mistake gets corrected with a reversing
 * entry, not a change to history." Manager-only, server-side; rejects a
 * second reversal of the same entry. */
export async function reverseJournalEntry(
  entryId: string,
  description?: string,
): Promise<JournalEntry> {
  const { data, error } = await supabase.rpc("reverse_journal_entry", {
    p_entry_id: entryId,
    // Same "" -> nullif(...) -> "use the auto-generated description"
    // reasoning as post_journal_entry()'s p_reference, above.
    p_description: description ?? "",
  });
  if (error) throw error;

  const row = (Array.isArray(data) ? data[0] : data) as { id: string } | null | undefined;
  if (!row?.id) throw new Error("Reversal was posted but no id was returned.");

  await reload();
  const posted = state.entries.find((e) => e.id === row.id);
  if (!posted) throw new Error("Reversal was posted but could not be found after reloading.");
  return posted;
}

export type LedgerRow = {
  entryId: string;
  entryDate: string;
  description: string;
  reference: string | null;
  lineDescription: string;
  debit: number;
  credit: number;
  balance: number;
};

/** The General Ledger for one account: every line posted against it,
 * oldest first, with a running balance — derived here from the already-
 * loaded journal lines, never stored separately (there's no balances
 * table). "Running balance" is in the account's own natural terms: a
 * debit-normal account's balance rises with debits, a credit-normal
 * account's rises with credits, so Cash and Sales Revenue both read the
 * way an accountant expects instead of a single global sign convention. */
export function ledgerForAccount(
  entries: JournalEntry[],
  account: Pick<Account, "id" | "normalBalance">,
): LedgerRow[] {
  const sign: 1 | -1 = account.normalBalance === "debit" ? 1 : -1;
  const rows: Omit<LedgerRow, "balance">[] = [];

  for (const entry of entries) {
    for (const line of entry.lines) {
      if (line.accountId !== account.id) continue;
      rows.push({
        entryId: entry.id,
        entryDate: entry.entryDate,
        description: entry.description,
        reference: entry.reference,
        lineDescription: line.description,
        debit: line.debit,
        credit: line.credit,
      });
    }
  }

  rows.sort((a, b) => {
    if (a.entryDate !== b.entryDate) return a.entryDate < b.entryDate ? -1 : 1;
    return a.entryId < b.entryId ? -1 : a.entryId > b.entryId ? 1 : 0;
  });

  let balance = 0;
  return rows.map((row) => {
    balance += sign * (row.debit - row.credit);
    return { ...row, balance };
  });
}
