export type Customer = {
  id: string;
  name: string;
  phone: string;
  email: string;
  address: string;
  type: "Retail" | "Contractor" | "Wholesale";
  since: string;
  balance: number;
  lifetime: number;
  /** What the business owes the customer (store credit issued on returns,
   * spendable as a payment method) — the opposite direction from `balance`
   * (what the customer owes the business on invoices). Never conflated. */
  storeCreditBalance: number;
};
