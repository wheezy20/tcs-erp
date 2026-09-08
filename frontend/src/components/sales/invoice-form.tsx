import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "@tanstack/react-router";
import { toast } from "sonner";
import { Plus, RefreshCcw, Trash2, WifiOff } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { ProductSearchSelect } from "@/components/product-search-select";
import { InlineAddCustomerDialog } from "@/components/sales/inline-add-customer-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { useAuth } from "@/data/auth-store";
import { useCurrentBranch } from "@/data/branch-store";
import { currency } from "@/data/dashboard";
import type { NewCustomer } from "@/data/customer-store";
import { reloadCustomerDeposits, useCustomerDeposits } from "@/data/customer-deposits-store";
import { hasPrice, useInventory } from "@/data/inventory-store";
import {
  DEFAULT_VAT_RATE,
  DEFAULT_WHT_RATE,
  INVOICE_BANK_METHODS,
  PAYMENT_METHODS,
  invoiceTotals,
  lineGross,
  type Invoice,
  type InvoiceLine,
  type PaymentMethod,
} from "@/data/invoices";
import { BankAccountSelect, useActiveBankAccounts } from "@/components/banking/bank-account-select";
import {
  addCustomer,
  addPayment,
  createInvoice,
  updateInvoice,
  useSales,
} from "@/data/sales-store";
import { useDocumentSettings } from "@/data/settings-store";
import { useWhtRate } from "@/data/wht-settings-store";
import { isNetworkError } from "@/lib/network-error";
import { getErrorMessage } from "@/lib/utils";

const today = () => new Date().toISOString().slice(0, 10);
const addDays = (iso: string, days: number) => {
  const d = new Date(iso);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
};
const emptyLine = (): InvoiceLine => ({
  id: `L${Math.floor(Math.random() * 100000)}`,
  productId: null,
  name: "",
  unit: "Pieces",
  quantity: 1,
  unitPrice: 0,
  discount: 0,
  vat: true,
});

// One row per line item instead of a stacked card per field — shared between
// the header and every row so the columns can never drift out of alignment.
// Product gets whatever room is left; the rest are fixed widths sized to
// their content (a currency figure, a switch, a delete icon). The unit
// (kg/Pieces/Litres/...) isn't repeated in the Qty column — it's already
// part of the product's own label text ("Name — price / unit"), and
// repeating it per row would cost back the vertical space this is meant to
// save. overflow-x-auto + the min-width below is the same graceful-
// degradation-on-narrow-viewports approach every other data table in this
// app already uses, rather than a second, stacked mobile layout.
const LINE_ITEM_GRID_COLS = "grid-cols-[minmax(11rem,1fr)_4.5rem_6.5rem_6rem_3rem_6.5rem_2.25rem]";

export function InvoiceForm({
  existing,
  depositId,
}: {
  existing?: Invoice;
  /** Set when this form was opened from a customer deposit's "Fulfil with
   * an invoice" action — pre-selects the customer and applies the deposit
   * as a payment once the invoice is created. */
  depositId?: string;
}) {
  const navigate = useNavigate();
  const { deposits } = useCustomerDeposits();
  const fulfilmentDeposit =
    depositId != null
      ? (deposits.find((d) => d.id === depositId && d.status === "Open") ?? null)
      : null;
  const { customers, vatRate: defaultVatRate } = useSales();
  const { products } = useInventory();
  const settings = useDocumentSettings();
  const { name: branchName } = useCurrentBranch();
  const { staff: currentStaff } = useAuth();

  const [customerId, setCustomerId] = useState(existing?.customerId ?? "");
  const [date, setDate] = useState(existing?.date ?? today());
  const [dueDate, setDueDate] = useState(
    existing?.dueDate ?? addDays(today(), settings.sales.paymentTermsDays),
  );
  const [notes, setNotes] = useState(existing?.notes ?? "");
  const [lines, setLines] = useState<InvoiceLine[]>(existing?.lines ?? [emptyLine()]);
  const [invoiceDiscount, setInvoiceDiscount] = useState(String(existing?.invoiceDiscount ?? 0));
  // Not user-editable: the database now decides this (business_settings for
  // new invoices, the invoice's own already-issued rate for edits) — see
  // create_invoice()/update_invoice() in the Session 4 migration. Shown here
  // only so the live total preview below matches what the server will save.
  const vatRate = existing?.vatRate ?? defaultVatRate ?? DEFAULT_VAT_RATE;
  const { whtRate: currentWhtRate } = useWhtRate();
  // Toggle "on invoices" per the spec's own wording — available to both
  // Attendant and Manager, no PIN gate. Only settable when creating a new
  // invoice: once issued, whtApplied/whtRate/whtAmount are fixed (see
  // create_invoice() in the Session 19 migration — update_invoice() never
  // touches them), so editing shows the frozen state read-only instead.
  const [whtApplied, setWhtApplied] = useState(existing?.whtApplied ?? false);
  const previewWhtRate = existing?.whtRate ?? currentWhtRate ?? DEFAULT_WHT_RATE;
  const [logPayment, setLogPayment] = useState(false);
  const [payAmount, setPayAmount] = useState("");
  const [payMethod, setPayMethod] = useState<PaymentMethod>("Mobile Money");
  const [payReference, setPayReference] = useState("");
  const [payBankAccountId, setPayBankAccountId] = useState("");
  const [error, setError] = useState<string | null>(null);
  // True only when submit() failed because the request never reached the
  // server — see isNetworkError(). Never for a real rejection (a missing
  // customer, an unpriced line, a payment over the balance), which still
  // sets `error` above instead. Nothing in this form is cleared on any
  // failure (see the catch block below), so a retry is just calling
  // submit() again against the exact same, still-intact draft.
  const [connectionIssue, setConnectionIssue] = useState(false);
  const [saving, setSaving] = useState(false);
  // Set once create/update actually succeeds within an attempt, so a retry
  // after addPayment() alone drops the connection skips straight to
  // retrying the payment instead of calling createInvoice() a second time
  // (which would mint a genuine duplicate invoice — updateInvoice() has no
  // equivalent risk, it's a plain update-by-id, safe to repeat).
  const [pendingInvoiceId, setPendingInvoiceId] = useState<string | null>(null);
  // Set once the deposit leg has actually been applied within an attempt,
  // so a retry after a later step fails doesn't double-apply it (same
  // retry-safety shape as pendingInvoiceId).
  const [depositApplied, setDepositApplied] = useState(false);

  // "Fulfil with an invoice" — lock the form to the deposit's customer.
  useEffect(() => {
    if (fulfilmentDeposit) setCustomerId(fulfilmentDeposit.customerId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fulfilmentDeposit?.id]);

  const selectedCustomer = customers.find((c) => c.id === customerId) ?? null;
  const storeCreditBalance = selectedCustomer?.storeCreditBalance ?? 0;
  const payMethodOptions: PaymentMethod[] =
    storeCreditBalance > 0 ? [...PAYMENT_METHODS, "Store Credit"] : PAYMENT_METHODS;
  const { defaultId: defaultBankAccountId } = useActiveBankAccounts();
  const payNeedsBankAccount = INVOICE_BANK_METHODS.includes(payMethod);
  const effectivePayBankAccountId = payBankAccountId || defaultBankAccountId;

  const draft: Invoice = useMemo(
    () => ({
      id: existing?.id ?? "DRAFT",
      customerId,
      customerName: customers.find((c) => c.id === customerId)?.name ?? "",
      date,
      dueDate,
      branch: existing?.branch ?? branchName ?? "",
      // Display-only: create_invoice()/update_invoice() always set this
      // server-side from the signed-in user, never from what's shown here.
      issuedBy: existing?.issuedBy ?? currentStaff?.name ?? "—",
      notes,
      lines,
      invoiceDiscount: Number(invoiceDiscount) || 0,
      vatRate,
      payments: existing?.payments ?? [],
      whtApplied,
      whtRate: existing?.whtRate ?? null,
      whtAmount: existing?.whtAmount ?? 0,
      voidedAt: existing?.voidedAt ?? null,
      voidedBy: existing?.voidedBy ?? null,
      voidReason: existing?.voidReason ?? null,
    }),
    [
      existing,
      customerId,
      customers,
      date,
      dueDate,
      notes,
      lines,
      invoiceDiscount,
      vatRate,
      branchName,
      currentStaff,
      whtApplied,
    ],
  );

  const totals = invoiceTotals(draft);
  const allVat = lines.length > 0 && lines.every((l) => l.vat);
  // Preview only — the server independently recomputes this from the same
  // (post-discount, pre-VAT) base via compute_invoice_posting_amounts(),
  // never trusts this figure.
  const previewWhtAmount = existing
    ? existing.whtAmount
    : whtApplied
      ? Math.round(totals.netAfterDiscount * (previewWhtRate / 100) * 100) / 100
      : 0;
  // A manual "log a payment now" is on top of the deposit that will be
  // applied first, so it can't exceed what's left after the deposit.
  const maxPayable =
    (existing ? totals.balance : totals.total - previewWhtAmount) -
    (fulfilmentDeposit ? fulfilmentDeposit.amount : 0);

  const updateLine = (id: string, patch: Partial<InvoiceLine>) =>
    setLines((prev) => prev.map((l) => (l.id === id ? { ...l, ...patch } : l)));

  const pickProduct = (id: string, productId: string) => {
    const product = products.find((p) => p.id === productId);
    if (!product) return;
    // Defense-in-depth: the picker below already disables an unpriced
    // product, but this is where a line is actually populated — the real,
    // unbypassable enforcement is server-side (create_invoice()/
    // update_invoice() both reject a line referencing an unpriced
    // product), same as POS checkout.
    if (!hasPrice(product)) {
      toast.error(`${product.name} has no selling price set — add one in Inventory to invoice it.`);
      return;
    }
    updateLine(id, {
      productId: product.id,
      name: product.name,
      unit: product.unit,
      unitPrice: product.price,
    });
  };

  const submit = async () => {
    if (!customerId) {
      setError("Select a customer for this invoice.");
      return;
    }
    if (lines.length === 0 || lines.some((l) => !l.name.trim() || l.quantity <= 0)) {
      setError("Every line item needs a product and a quantity above zero.");
      return;
    }
    if (fulfilmentDeposit && totals.total < fulfilmentDeposit.amount - 0.01) {
      setError(
        `The invoice total must be at least the ${currency(fulfilmentDeposit.amount)} deposit.`,
      );
      return;
    }
    let payValue = 0;
    if (logPayment) {
      payValue = Number(payAmount);
      if (!Number.isFinite(payValue) || payValue <= 0) {
        setError("Enter a valid payment amount, or turn off the payment toggle.");
        return;
      }
      if (payValue > maxPayable + 0.01) {
        setError(
          whtApplied && !existing
            ? `Payment cannot exceed ${currency(maxPayable)} — the total less withholding tax.`
            : "Payment cannot exceed the invoice total.",
        );
        return;
      }
      if (payMethod === "Store Credit" && payValue > storeCreditBalance + 0.01) {
        setError(
          `Payment cannot exceed the customer's store credit of ${currency(storeCreditBalance)}.`,
        );
        return;
      }
      if (payNeedsBankAccount && !effectivePayBankAccountId) {
        setError(`Pick the bank account this ${payMethod} settled into.`);
        return;
      }
    }

    setSaving(true);
    setError(null);
    setConnectionIssue(false);
    try {
      const trimmedNotes = notes.trim().slice(0, 240);
      let id = pendingInvoiceId;
      if (!id) {
        if (existing) {
          id = existing.id;
          await updateInvoice({ ...draft, id, notes: trimmedNotes, payments: existing.payments });
        } else {
          const {
            id: _draftId,
            payments: _draftPayments,
            issuedBy: _draftIssuedBy,
            whtRate: _draftWhtRate,
            whtAmount: _draftWhtAmount,
            ...newInvoice
          } = draft;
          const created = await createInvoice({ ...newInvoice, notes: trimmedNotes });
          id = created.id;
        }
        setPendingInvoiceId(id);
      }
      if (fulfilmentDeposit && !depositApplied) {
        // Applied first: clears the 2450 liability by the full deposit
        // amount (record_invoice_payment() flips the deposit to Fulfilled).
        await addPayment(id, {
          date,
          amount: fulfilmentDeposit.amount,
          method: "Deposit",
          reference: `Deposit ${fulfilmentDeposit.id}`,
          depositId: fulfilmentDeposit.id,
        });
        setDepositApplied(true);
      }
      if (logPayment) {
        await addPayment(id, {
          date,
          amount: Math.round(payValue * 100) / 100,
          method: payMethod,
          reference: payReference.trim().slice(0, 60) || "Counter payment",
          bankAccountId: payNeedsBankAccount ? effectivePayBankAccountId : null,
        });
      }
      if (fulfilmentDeposit) void reloadCustomerDeposits();
      toast.success(existing ? `${id} updated` : `${id} created`);
      navigate({ to: "/sales/$invoiceId", params: { invoiceId: id } });
    } catch (err) {
      // A dropped connection means that specific request never reached the
      // server — pendingInvoiceId (if already set) is left exactly as is,
      // so a retry never re-runs a step that already succeeded. A real
      // rejection still falls through to the ordinary error banner below,
      // unchanged in spirit — err instanceof Error was the actual bug here:
      // supabase-js's default (non-throwOnError) error objects are plain
      // objects, not Error instances (see getErrorMessage()'s own note),
      // so every real backend message was silently replaced by the generic
      // fallback before this fix, the same bug already found and fixed at
      // six other call sites.
      if (isNetworkError(err)) {
        setConnectionIssue(true);
      } else {
        setError(getErrorMessage(err, "Could not save the invoice."));
      }
    } finally {
      setSaving(false);
    }
  };

  const onNewCustomer = async (input: NewCustomer) => {
    const created = await addCustomer(input);
    setCustomerId(created.id);
  };

  return (
    <>
      <PageHeader
        title={existing ? `Edit ${existing.id}` : "New invoice"}
        description={`Line items pull live pricing from Inventory · ${branchName ?? "…"}`}
        actions={
          <>
            <Button variant="outline" onClick={() => navigate({ to: "/sales" })} disabled={saving}>
              Cancel
            </Button>
            <Button onClick={submit} disabled={saving}>
              {saving ? "Saving…" : existing ? "Save changes" : "Create invoice"}
            </Button>
          </>
        }
      />

      <div className="grid gap-6 xl:grid-cols-[1fr_340px]">
        <div className="space-y-6">
          <section className="card-surface p-5">
            <h2 className="text-sm font-semibold">Customer & dates</h2>
            <div className="mt-4 grid gap-4 sm:grid-cols-2">
              <div className="grid gap-2 sm:col-span-2">
                <Label>Customer</Label>
                <div className="flex gap-2">
                  <Select
                    value={customerId}
                    disabled={!!fulfilmentDeposit}
                    onValueChange={(id) => {
                      setCustomerId(id);
                      // A Store Credit selection is a claim against the
                      // previous customer's balance — same reasoning as
                      // POS's pickCustomer() — so it can't silently carry
                      // over to whichever customer is picked next.
                      if (payMethod === "Store Credit") setPayMethod("Mobile Money");
                    }}
                  >
                    <SelectTrigger className="rounded-xl">
                      <SelectValue placeholder="Select a customer" />
                    </SelectTrigger>
                    <SelectContent>
                      {customers.map((c) => (
                        <SelectItem key={c.id} value={c.id}>
                          {c.name} · {c.phone}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {!fulfilmentDeposit && <InlineAddCustomerDialog onAdd={onNewCustomer} />}
                </div>
                {fulfilmentDeposit && (
                  <p className="text-xs text-muted-foreground">
                    Fulfilling deposit {fulfilmentDeposit.id} — {currency(fulfilmentDeposit.amount)}{" "}
                    is applied as a payment when this invoice is created; collect the balance
                    normally.
                  </p>
                )}
              </div>
              <div className="grid gap-2">
                <Label htmlFor="inv-date">Invoice date</Label>
                <Input
                  id="inv-date"
                  type="date"
                  value={date}
                  onChange={(e) => setDate(e.target.value)}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="inv-due">Due date</Label>
                <Input
                  id="inv-due"
                  type="date"
                  value={dueDate}
                  onChange={(e) => setDueDate(e.target.value)}
                />
              </div>
            </div>
          </section>

          <section className="card-surface p-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h2 className="text-sm font-semibold">Line items</h2>
              <div className="flex items-center gap-3">
                <label className="flex items-center gap-2 text-sm text-muted-foreground">
                  <Switch
                    checked={allVat}
                    onCheckedChange={(v) => setLines((prev) => prev.map((l) => ({ ...l, vat: v })))}
                  />
                  VAT on all items
                </label>
                <Button
                  variant="outline"
                  size="sm"
                  className="gap-1.5"
                  onClick={() => setLines((prev) => [...prev, emptyLine()])}
                >
                  <Plus className="size-4" /> Add item
                </Button>
              </div>
            </div>

            <div className="mt-4 overflow-x-auto">
              <div className="min-w-[42rem]">
                <div
                  className={`grid items-center gap-2 px-1 pb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground ${LINE_ITEM_GRID_COLS}`}
                >
                  <span>Product</span>
                  <span className="text-right">Qty</span>
                  <span className="text-right">Unit price</span>
                  <span className="text-right">Discount</span>
                  <span className="text-center">VAT</span>
                  <span className="text-right">Amount</span>
                  <span aria-hidden />
                </div>

                <div className="divide-y rounded-xl border">
                  {lines.map((l) => (
                    <div
                      key={l.id}
                      className={`grid items-center gap-2 px-3 py-2 ${LINE_ITEM_GRID_COLS}`}
                    >
                      <ProductSearchSelect
                        products={products}
                        value={l.productId}
                        onSelect={(p) => pickProduct(l.id, p.id)}
                        optionLabel={(p) =>
                          `${p.name} — ${hasPrice(p) ? currency(p.price) : "No price set"} / ${p.unit.toLowerCase()}`
                        }
                        isOptionDisabled={(p) => !hasPrice(p)}
                        disabledHint="No price set — add one in Inventory to invoice it."
                      />
                      <Input
                        type="number"
                        min={0}
                        step="1"
                        value={l.quantity}
                        aria-label={`Quantity, in ${l.unit.toLowerCase()}`}
                        className="text-right"
                        onChange={(e) =>
                          updateLine(l.id, { quantity: Number(e.target.value) || 0 })
                        }
                      />
                      <Input
                        type="number"
                        min={0}
                        step="0.01"
                        value={l.unitPrice}
                        aria-label="Unit price (GHS)"
                        className="text-right"
                        onChange={(e) =>
                          updateLine(l.id, { unitPrice: Number(e.target.value) || 0 })
                        }
                      />
                      <Input
                        type="number"
                        min={0}
                        step="0.01"
                        value={l.discount}
                        aria-label="Line discount (GHS)"
                        className="text-right"
                        onChange={(e) =>
                          updateLine(l.id, { discount: Number(e.target.value) || 0 })
                        }
                      />
                      <div className="flex justify-center">
                        <Switch
                          checked={l.vat}
                          onCheckedChange={(v) => updateLine(l.id, { vat: v })}
                          aria-label={`Apply ${vatRate}% VAT to this line`}
                        />
                      </div>
                      <span className="text-right text-sm font-medium tabular-nums">
                        {currency(Math.max(0, lineGross(l) - l.discount))}
                      </span>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="size-8 justify-self-end text-muted-foreground hover:text-destructive"
                        onClick={() => setLines((prev) => prev.filter((x) => x.id !== l.id))}
                        aria-label="Remove line item"
                      >
                        <Trash2 className="size-4" />
                      </Button>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </section>

          <section className="card-surface p-5">
            <h2 className="text-sm font-semibold">Notes</h2>
            <Textarea
              className="mt-3"
              rows={3}
              maxLength={240}
              value={notes}
              placeholder="Delivery instructions, site reference, agreed payment plan…"
              onChange={(e) => setNotes(e.target.value)}
            />
          </section>
        </div>

        <aside className="space-y-6">
          <section className="card-surface p-5">
            <h2 className="text-sm font-semibold">Totals</h2>
            <div className="mt-4 grid gap-3">
              <div className="grid gap-2">
                <Label htmlFor="inv-discount">Invoice discount (GHS)</Label>
                <Input
                  id="inv-discount"
                  type="number"
                  min={0}
                  step="0.01"
                  value={invoiceDiscount}
                  onChange={(e) => setInvoiceDiscount(e.target.value)}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="inv-vat">VAT rate (%)</Label>
                <Input id="inv-vat" type="number" value={vatRate} disabled readOnly />
                <p className="text-xs text-muted-foreground">
                  Set business-wide, not editable per invoice.
                </p>
              </div>
              <div className="flex items-center justify-between gap-3 rounded-xl border p-3">
                <div className="min-w-0">
                  <p className="text-sm font-medium">Withholding tax (WHT)</p>
                  <p className="text-xs text-muted-foreground">
                    {existing
                      ? "Fixed at issue, not editable on an already-created invoice."
                      : `Deducted from what the customer pays at ${previewWhtRate}% of the taxable subtotal; the invoice still shows full revenue.`}
                  </p>
                </div>
                <Switch
                  checked={whtApplied}
                  onCheckedChange={setWhtApplied}
                  disabled={!!existing}
                />
              </div>
            </div>

            <dl className="mt-5 space-y-2 border-t pt-4 text-sm">
              <Row label="Subtotal" value={currency(totals.subtotal)} />
              <Row label="Line discounts" value={`− ${currency(totals.lineDiscounts)}`} muted />
              <Row label="Invoice discount" value={`− ${currency(totals.invoiceDiscount)}`} muted />
              <Row label={`VAT (${vatRate}%)`} value={currency(totals.vat)} muted />
              <div className="flex items-center justify-between border-t pt-3 text-base font-semibold">
                <span>Total</span>
                <span className="tabular-nums">{currency(totals.total)}</span>
              </div>
              {(whtApplied || existing?.whtApplied) && (
                <>
                  <Row
                    label={`Withholding tax (${previewWhtRate}%)`}
                    value={`− ${currency(previewWhtAmount)}`}
                    muted
                  />
                  <div className="flex items-center justify-between text-sm font-semibold">
                    <span>Customer pays</span>
                    <span className="tabular-nums">
                      {currency(Math.max(0, totals.total - previewWhtAmount))}
                    </span>
                  </div>
                </>
              )}
            </dl>
          </section>

          <section className="card-surface p-5">
            <label className="flex items-center justify-between gap-3">
              <span className="text-sm font-semibold">Log a payment now</span>
              <Switch checked={logPayment} onCheckedChange={setLogPayment} />
            </label>
            {logPayment && (
              <div className="mt-4 grid gap-3">
                <div className="grid gap-2">
                  <Label htmlFor="np-amount">Amount (GHS)</Label>
                  <Input
                    id="np-amount"
                    type="number"
                    min={0}
                    step="0.01"
                    value={payAmount}
                    placeholder={String(maxPayable)}
                    onChange={(e) => setPayAmount(e.target.value)}
                  />
                </div>
                <div className="grid gap-2">
                  <Label>Method</Label>
                  <Select value={payMethod} onValueChange={(v) => setPayMethod(v as PaymentMethod)}>
                    <SelectTrigger className="rounded-xl">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {payMethodOptions.map((m) => (
                        <SelectItem key={m} value={m}>
                          {m}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {storeCreditBalance > 0 && (
                    <p className="text-xs text-muted-foreground">
                      {currency(storeCreditBalance)} store credit available
                    </p>
                  )}
                </div>
                {payNeedsBankAccount && (
                  <div className="grid gap-2">
                    <Label htmlFor="np-bank">Bank account</Label>
                    <BankAccountSelect
                      id="np-bank"
                      value={effectivePayBankAccountId}
                      onChange={setPayBankAccountId}
                      placeholder={`Which bank received this ${payMethod}?`}
                    />
                  </div>
                )}
                <div className="grid gap-2">
                  <Label htmlFor="np-ref">Reference</Label>
                  <Input
                    id="np-ref"
                    value={payReference}
                    maxLength={60}
                    placeholder="MTN 8841, Till 04…"
                    onChange={(e) => setPayReference(e.target.value)}
                  />
                </div>
                <p className="text-xs text-muted-foreground">
                  Partial payments are fine — the invoice will show the remaining balance.
                </p>
              </div>
            )}
          </section>

          {connectionIssue ? (
            <div className="flex items-start gap-2 rounded-2xl border border-destructive/30 bg-destructive/10 p-4 text-sm text-destructive">
              <WifiOff className="mt-0.5 size-4 shrink-0" />
              <div className="flex-1">
                <p className="font-medium">
                  Connection lost — this {existing ? "update" : "invoice"} wasn&apos;t saved
                </p>
                <p className="mt-0.5 text-xs text-destructive/90">
                  Nothing on this form was lost. Check your connection, then try again.
                </p>
              </div>
              <Button
                size="sm"
                variant="outline"
                className="gap-1.5 border-destructive/40 text-destructive hover:text-destructive"
                onClick={submit}
                disabled={saving}
              >
                <RefreshCcw className="size-3.5" /> Retry
              </Button>
            </div>
          ) : (
            error && (
              <p className="rounded-2xl border border-destructive/30 bg-destructive/10 px-4 py-3 text-sm text-destructive">
                {error}
              </p>
            )
          )}
        </aside>
      </div>
    </>
  );
}

function Row({ label, value, muted }: { label: string; value: string; muted?: boolean }) {
  return (
    <div className="flex items-center justify-between">
      <dt className={muted ? "text-muted-foreground" : ""}>{label}</dt>
      <dd className="tabular-nums">{value}</dd>
    </div>
  );
}
