import { round2 } from "@/data/pos";
import type { JournalEntry } from "@/data/journal-store";

/**
 * Suggested-match computation for the Reconcile screen — a pure derivation
 * over the already-loaded journal entries, the same "computed, never
 * stored" precedent ledgerForAccount() and financial-reports.ts already
 * established. The database never materializes "candidates"; matching
 * itself (match_statement_line()) is the only thing that writes anything.
 */

export type LedgerActivityRow = {
  journalLineId: string;
  entryId: string;
  entryDate: string;
  description: string;
  /** Signed the same way a bank statement is: positive = money in
   * (debit, since every bank account's gl_account_id is Assets/debit-normal
   * by the validate_bank_account_gl_link trigger), negative = money out. */
  amount: number;
};

/** Every journal line ever posted against one bank account's GL account,
 * newest first — the full activity a statement line could conceivably
 * match against, before filtering out what's already spoken for. */
export function ledgerActivityForAccount(
  entries: JournalEntry[],
  glAccountId: string,
): LedgerActivityRow[] {
  const rows: LedgerActivityRow[] = [];
  for (const entry of entries) {
    for (const line of entry.lines) {
      if (line.accountId !== glAccountId) continue;
      rows.push({
        journalLineId: line.id,
        entryId: entry.id,
        entryDate: entry.entryDate,
        description: line.description || entry.description,
        amount: round2(line.debit - line.credit),
      });
    }
  }
  rows.sort((a, b) => (a.entryDate < b.entryDate ? 1 : a.entryDate > b.entryDate ? -1 : 0));
  return rows;
}

/** Ledger activity not yet claimed by any statement line — both the pool
 * suggestMatches() draws candidates from, and (unfiltered by date) a
 * transparency view of "what the books show that the bank hasn't
 * confirmed yet," shown informationally on the Reconcile screen. This
 * never gates completion — an outstanding item (e.g. a payment that
 * hasn't cleared the bank yet) is normal and expected to carry forward,
 * not an error. */
export function unmatchedLedgerActivity(
  activity: LedgerActivityRow[],
  matchedJournalLineIds: ReadonlySet<string>,
): LedgerActivityRow[] {
  return activity.filter((row) => !matchedJournalLineIds.has(row.journalLineId));
}

const daysBetween = (a: string, b: string) => {
  const diff = new Date(`${a}T00:00:00Z`).getTime() - new Date(`${b}T00:00:00Z`).getTime();
  return Math.round(diff / 86_400_000);
};

/** Candidates for one statement line: same signed amount to the cent
 * (match_statement_line() enforces this server-side too — this is purely
 * for what to suggest, not a relaxed client-side check), within a
 * clearing-lag tolerance window, closest date first. Anything looser than
 * an exact amount belongs in "Mark cleared," a deliberate override, not a
 * fuzzy auto-match. */
export function suggestMatches(
  statementLine: { date: string; amount: number },
  candidates: LedgerActivityRow[],
  toleranceDays = 7,
): LedgerActivityRow[] {
  return candidates
    .filter((c) => Math.abs(c.amount - statementLine.amount) < 0.005)
    .filter((c) => Math.abs(daysBetween(c.entryDate, statementLine.date)) <= toleranceDays)
    .sort(
      (a, b) =>
        Math.abs(daysBetween(a.entryDate, statementLine.date)) -
        Math.abs(daysBetween(b.entryDate, statementLine.date)),
    );
}
