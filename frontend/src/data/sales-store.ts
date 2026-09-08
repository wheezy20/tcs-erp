import { addCustomer, useCustomers } from "@/data/customer-store";
import {
  addPayment,
  createInvoice,
  updateInvoice,
  useInvoices,
  voidInvoice,
} from "@/data/invoice-store";

// Customers moved to their own table + store in Phase 1.5 Session 2, and
// invoices/payments in Session 3 (see supabase/migrations, customer-store.ts,
// invoice-store.ts). This file is now a pure delegator: useSales() re-exposes
// the combined `{ invoices, customers, vatRate }` shape so Sales-module
// consumers don't need to change how they read it, and the mutators are
// re-exported under their original names/import path.
export { addCustomer, addPayment, createInvoice, updateInvoice, voidInvoice };

export function useSales() {
  const { invoices, vatRate } = useInvoices();
  const { customers } = useCustomers();
  return { invoices, customers, vatRate };
}
