import type { Account, AccountCategory } from "@/data/accounts-store";
import { round2 } from "@/data/pos";
import { sourceLabel, type JournalEntry } from "@/data/journal-store";

/**
 * Session 15: Trial Balance, Balance Sheet, Profit & Loss and Cash Flow —
 * all pure derivations over the already-loaded journal entries and chart of
 * accounts, the same "computed, never stored" precedent ledgerForAccount()
 * (journal-store.ts) already established for the General Ledger. There is
 * no new table, RPC or RLS here: every figure below is just a different
 * shape drawn from journal_lines, which Session 14's auto-posters and
 * Session 13's manual entries already populate.
 */

type LineTotals = { debit: number; credit: number };

/** One pass over every entry/line, bucketed by account, optionally bounded
 * to a date range (either bound omitted means unbounded on that side). */
function accountTotals(
  entries: JournalEntry[],
  range: { from?: string; to?: string } = {},
): Map<string, LineTotals> {
  const totals = new Map<string, LineTotals>();
  for (const entry of entries) {
    if (range.from && entry.entryDate < range.from) continue;
    if (range.to && entry.entryDate > range.to) continue;
    for (const line of entry.lines) {
      const t = totals.get(line.accountId) ?? { debit: 0, credit: 0 };
      t.debit += line.debit;
      t.credit += line.credit;
      totals.set(line.accountId, t);
    }
  }
  return totals;
}

/** An account's balance expressed in its own normal-balance terms — rises
 * with debits for a debit-normal account, with credits for a credit-normal
 * one. This is what makes a contra account (e.g. 4100 Sales Returns &
 * Allowances, category Revenue/credit-normal but routinely debited) net
 * out correctly when summed alongside its parent category: a contra
 * account's balance in normal terms comes out negative, subtracting from
 * the category total instead of needing separate contra-handling. */
function normalBalanceAmount(
  totals: LineTotals | undefined,
  account: Pick<Account, "normalBalance">,
) {
  const t = totals ?? { debit: 0, credit: 0 };
  return account.normalBalance === "debit"
    ? round2(t.debit - t.credit)
    : round2(t.credit - t.debit);
}

/* ==================================================================== Trial Balance */

export type TrialBalanceRow = {
  accountId: string;
  code: string;
  name: string;
  category: AccountCategory;
  debit: number;
  credit: number;
};

export type TrialBalance = {
  asOf: string;
  rows: TrialBalanceRow[];
  totalDebit: number;
  totalCredit: number;
};

/** Every account with a nonzero balance as of the chosen date, shown on
 * whichever side (debit or credit column) its actual raw net lands on —
 * not forced onto its category's usual side. This is the literal, raw
 * ledger net (debit - credit), unlike Balance Sheet/P&L below which read
 * each account in its own normal-balance terms; a trial balance's whole
 * point is to prove the ledger itself balances, and it does so by
 * construction: every journal_lines row is part of a debit = credit entry
 * (Session 13's deferred constraint trigger), so summing every account's
 * raw net across the whole chart is always exactly zero, which is exactly
 * what splitting each account's net into a debit-or-credit column and
 * totalling each column separately proves. If these two totals ever
 * differ, the ledger itself has a bug — this report can't produce that
 * result from any real, valid set of postings. */
export function trialBalance(
  entries: JournalEntry[],
  accounts: Account[],
  asOf: string,
): TrialBalance {
  const totals = accountTotals(entries, { to: asOf });
  const rows: TrialBalanceRow[] = [];
  for (const account of accounts) {
    const t = totals.get(account.id);
    if (!t) continue;
    const net = round2(t.debit - t.credit);
    if (Math.abs(net) < 0.005) continue;
    rows.push({
      accountId: account.id,
      code: account.code,
      name: account.name,
      category: account.category,
      debit: net > 0 ? net : 0,
      credit: net < 0 ? round2(-net) : 0,
    });
  }
  rows.sort((a, b) => a.code.localeCompare(b.code));
  return {
    asOf,
    rows,
    totalDebit: round2(rows.reduce((s, r) => s + r.debit, 0)),
    totalCredit: round2(rows.reduce((s, r) => s + r.credit, 0)),
  };
}

/* ==================================================================== Balance Sheet */

export type BalanceSheetRow = { accountId: string; code: string; name: string; amount: number };
export type BalanceSheetSection = { rows: BalanceSheetRow[]; total: number };

export type BalanceSheet = {
  asOf: string;
  assets: BalanceSheetSection;
  liabilities: BalanceSheetSection;
  equity: BalanceSheetSection;
  totalAssets: number;
  totalLiabilitiesAndEquity: number;
  /** The Equity-section plug closing the gap between assets and
   * liabilities+equity — see the block comment above balanceSheet(). Kept
   * on the result (not just folded into equity.rows) so the UI can call
   * it out distinctly rather than presenting it as an ordinary account. */
  currentEarnings: number;
};

function sectionFor(
  totals: Map<string, LineTotals>,
  accounts: Account[],
  category: AccountCategory,
): BalanceSheetSection {
  const rows = accounts
    .filter((a) => a.category === category)
    .map((a) => ({
      accountId: a.id,
      code: a.code,
      name: a.name,
      amount: normalBalanceAmount(totals.get(a.id), a),
    }))
    .filter((r) => Math.abs(r.amount) > 0.005);
  return { rows, total: round2(rows.reduce((s, r) => s + r.amount, 0)) };
}

function netIncomeThrough(totals: Map<string, LineTotals>, accounts: Account[]): number {
  const revenue = accounts.filter((a) => a.category === "Revenue");
  const cogs = accounts.filter(
    (a) => a.category === "Expenses" && a.subtype === "Cost of Goods Sold",
  );
  const opex = accounts.filter(
    (a) => a.category === "Expenses" && a.subtype !== "Cost of Goods Sold",
  );
  const sum = (list: Account[]) =>
    list.reduce((s, a) => s + normalBalanceAmount(totals.get(a.id), a), 0);
  return round2(sum(revenue) - sum(cogs) - sum(opex));
}

/**
 * Assets = Liabilities + Equity, as of a chosen date. This app has no
 * formal period-close (no closing entries ever post to 3100 Retained
 * Earnings — Session 13/14 never built one, and nothing in the spec calls
 * for it yet), so without a plug, Revenue/Expense activity would sit
 * "unclosed" and the two sides of a raw balance sheet would never actually
 * match — every real transaction is fully double-entry balanced, but that
 * only proves the *whole ledger* nets to zero (Trial Balance's job), not
 * that Assets alone equals Liabilities+Equity alone once you carve out
 * Revenue and Expenses into their own report.
 *
 * The standard fix (what every real accounting system shows before its
 * first formal year-end close) is a single computed Equity line —
 * "Current earnings (undistributed)" here — equal to cumulative net income
 * since inception through the report date: the same Revenue − COGS −
 * Expenses arithmetic Profit & Loss uses below, just accumulated
 * unconditionally rather than over a chosen range. Folding exactly that
 * amount into Equity is what makes the identity hold by construction: the
 * whole ledger's balance-per-entry guarantee (Assets + Expenses = Liabilities
 * + Equity + Revenue, in debit-positive terms) rearranges directly into
 * Assets = Liabilities + Equity + (Revenue − Expenses).
 *
 * This line deliberately never uses the words "net profit" — that phrase
 * is reserved for the Profit & Loss report alone (see profitAndLoss()
 * below); this is the same figure, phrased as the balance-sheet concept it
 * actually represents (income not yet closed to Retained Earnings).
 */
export function balanceSheet(
  entries: JournalEntry[],
  accounts: Account[],
  asOf: string,
): BalanceSheet {
  const totals = accountTotals(entries, { to: asOf });

  const assets = sectionFor(totals, accounts, "Assets");
  const liabilities = sectionFor(totals, accounts, "Liabilities");
  const equityAccounts = sectionFor(totals, accounts, "Equity");
  const currentEarnings = netIncomeThrough(totals, accounts);

  const equity: BalanceSheetSection = {
    rows:
      Math.abs(currentEarnings) > 0.005
        ? [
            ...equityAccounts.rows,
            {
              accountId: "current-earnings",
              code: "",
              name: "Current earnings (undistributed, not yet closed to Retained Earnings)",
              amount: currentEarnings,
            },
          ]
        : equityAccounts.rows,
    total: round2(equityAccounts.total + currentEarnings),
  };

  return {
    asOf,
    assets,
    liabilities,
    equity,
    totalAssets: assets.total,
    totalLiabilitiesAndEquity: round2(liabilities.total + equity.total),
    currentEarnings,
  };
}

/* ==================================================================== Profit & Loss */

export type PLRow = { accountId: string; code: string; name: string; amount: number };

export type ProfitAndLoss = {
  from: string;
  to: string;
  revenue: PLRow[];
  totalRevenue: number;
  cogs: PLRow[];
  totalCogs: number;
  grossProfit: number;
  operatingExpenses: PLRow[];
  totalOperatingExpenses: number;
  /** Revenue − COGS − Expenses over the full chart of accounts. The only
   * report in this app allowed to call this "net profit" — everywhere else
   * (Phase 1's Reports) keeps "gross profit" / "operating margin", each
   * narrower than this because they were built before Sessions 12-14 gave
   * the app a real chart of accounts and General Ledger to draw from. */
  netProfit: number;
};

export function profitAndLoss(
  entries: JournalEntry[],
  accounts: Account[],
  from: string,
  to: string,
): ProfitAndLoss {
  const totals = accountTotals(entries, { from, to });

  const rowsFor = (list: Account[]): PLRow[] =>
    list
      .map((a) => ({
        accountId: a.id,
        code: a.code,
        name: a.name,
        amount: normalBalanceAmount(totals.get(a.id), a),
      }))
      .filter((r) => Math.abs(r.amount) > 0.005);

  const revenue = rowsFor(accounts.filter((a) => a.category === "Revenue"));
  const cogs = rowsFor(
    accounts.filter((a) => a.category === "Expenses" && a.subtype === "Cost of Goods Sold"),
  );
  const operatingExpenses = rowsFor(
    accounts.filter((a) => a.category === "Expenses" && a.subtype !== "Cost of Goods Sold"),
  );

  const totalRevenue = round2(revenue.reduce((s, r) => s + r.amount, 0));
  const totalCogs = round2(cogs.reduce((s, r) => s + r.amount, 0));
  const grossProfit = round2(totalRevenue - totalCogs);
  const totalOperatingExpenses = round2(operatingExpenses.reduce((s, r) => s + r.amount, 0));
  const netProfit = round2(grossProfit - totalOperatingExpenses);

  return {
    from,
    to,
    revenue,
    totalRevenue,
    cogs,
    totalCogs,
    grossProfit,
    operatingExpenses,
    totalOperatingExpenses,
    netProfit,
  };
}

/* ==================================================================== Cash Flow */

/** Cash on Hand, Cash in Bank, Mobile Money Float — the same three accounts
 * payment_method_account() (auto_posting_integration migration) maps every
 * non-Store-Credit payment method onto. Treated as one pooled "cash and
 * cash equivalents" balance, the standard Statement of Cash Flows
 * convention — a bank_deposit's Dr 1010/Cr 1000 transfer nets to zero
 * automatically below (both legs land inside the same pool), rather than
 * needing to be special-cased out as "not really a cash flow." */
export const CASH_ACCOUNT_CODES = ["1000", "1010", "1020"];

export type CashFlowSourceRow = { source: string; in: number; out: number; net: number };

export type CashFlowSummary = {
  from: string;
  to: string;
  totalIn: number;
  totalOut: number;
  net: number;
  bySource: CashFlowSourceRow[];
};

/**
 * Cash in vs cash out over a date range, read directly off the ledger's own
 * Cash/Bank/MoMo account activity (the direct method) — not recomputed
 * separately from POS/Expenses data the way Phase 1's Dashboard "Cash on
 * Hand" KPI (cashFromInvoices + cashFromTill - cashExpenses, data/dashboard.ts)
 * had to, before there was a ledger to read it from instead. Grouped by
 * sourceLabel() (journal-store.ts) — the same "POS sale" / "Invoice
 * payment" / "Expense" / etc. classification the journal entries list
 * already shows — so the breakdown lines up with what a Manager already
 * recognizes elsewhere in Accounting, with no new classification invented
 * here.
 */
export function cashFlow(
  entries: JournalEntry[],
  accounts: Account[],
  from: string,
  to: string,
): CashFlowSummary {
  const cashAccountIds = new Set(
    accounts.filter((a) => CASH_ACCOUNT_CODES.includes(a.code)).map((a) => a.id),
  );
  const bySource = new Map<string, { in: number; out: number }>();
  let totalIn = 0;
  let totalOut = 0;

  for (const entry of entries) {
    // Guarded the same way accountTotals() guards its range — an empty
    // from/to (the "All time" preset) must mean unbounded on that side,
    // not "reject everything," which a bare string comparison against ""
    // would otherwise do (any non-empty date string is > "").
    if (from && entry.entryDate < from) continue;
    if (to && entry.entryDate > to) continue;
    let entryIn = 0;
    let entryOut = 0;
    for (const line of entry.lines) {
      if (!cashAccountIds.has(line.accountId)) continue;
      entryIn += line.debit;
      entryOut += line.credit;
    }
    if (entryIn < 0.005 && entryOut < 0.005) continue;
    const label = sourceLabel(entry);
    const bucket = bySource.get(label) ?? { in: 0, out: 0 };
    bucket.in += entryIn;
    bucket.out += entryOut;
    bySource.set(label, bucket);
    totalIn += entryIn;
    totalOut += entryOut;
  }

  const rows = [...bySource.entries()]
    .map(([source, v]) => ({
      source,
      in: round2(v.in),
      out: round2(v.out),
      net: round2(v.in - v.out),
    }))
    .sort((a, b) => b.net - a.net);

  return {
    from,
    to,
    totalIn: round2(totalIn),
    totalOut: round2(totalOut),
    net: round2(totalIn - totalOut),
    bySource: rows,
  };
}
