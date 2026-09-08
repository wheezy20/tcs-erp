export type ExpenseMethod = "Cash" | "Mobile Money" | "Bank";

export const EXPENSE_METHODS: ExpenseMethod[] = ["Cash", "Mobile Money", "Bank"];

export type Expense = {
  id: string;
  date: string;
  category: string;
  description: string;
  amount: number;
  method: ExpenseMethod;
  reference?: string;
  /** Which real bank account a "Bank" expense was paid from; null otherwise. */
  bankAccountId: string | null;
  recordedBy: string;
  /** ISO timestamp of when the record was created. */
  recordedAt: string;
  /** Public URL of an uploaded receipt photo, when one was attached. */
  receiptUrl: string | null;
  /** Set when a Manager has voided this expense (void_expense()): the whole
   * record was a mistake — its ledger entry is reversed and it no longer
   * counts anywhere. null on a normal expense. */
  voidedAt: string | null;
  voidedBy: string | null;
  voidReason: string | null;
};

export const expenseTotal = (rows: Expense[]) => rows.reduce((sum, e) => sum + e.amount, 0);
