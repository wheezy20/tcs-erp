import { useEffect, useMemo, useRef, useState } from "react";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import {
  Minus,
  PauseCircle,
  Plus,
  Printer,
  Receipt,
  RefreshCcw,
  ShieldCheck,
  ShoppingCart,
  Trash2,
  UserRound,
  WifiOff,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { HeldSalesDialog } from "@/components/pos/held-sales-dialog";
import { ManagerOverrideDialog } from "@/components/pos/manager-override-dialog";
import { BankAccountSelect, useActiveBankAccounts } from "@/components/banking/bank-account-select";
import { ProductGrid } from "@/components/pos/product-grid";
import { ReceiptPreview } from "@/components/pos/receipt-preview";
import { PrintDocument } from "@/components/print/print-document";
import { PrintableReceipt } from "@/components/print/printable-receipt";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
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
import { useCustomerDiscounts } from "@/data/customer-discounts-store";
import { currency } from "@/data/dashboard";
import { holdSale, useHeldSales } from "@/data/held-sales-store";
import { hasPrice, useInventory } from "@/data/inventory-store";
import type { Product } from "@/data/inventory";
import {
  discountAmount,
  lineGross,
  lineNet,
  noDiscount,
  posTotals,
  round2,
  POS_METHODS,
  POS_BANK_METHODS,
  type Discount,
  type HeldSale,
  type PosLine,
  type PosMethod,
  type PosPayment,
  type PosSale,
  type VatMode,
} from "@/data/pos";
import { createPosSale } from "@/data/pos-store";
import { reloadCustomerDeposits, useCustomerDeposits } from "@/data/customer-deposits-store";
import { useSales } from "@/data/sales-store";
import { useDocumentSettings } from "@/data/settings-store";
import { isNetworkError } from "@/lib/network-error";
import { cn, getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/pos/")({
  // Optional deep-link from a customer deposit's "Fulfil with a POS sale"
  // action — the checkout pre-selects that customer and applies the deposit
  // as a payment leg (see customer-deposits handling below).
  validateSearch: (search: Record<string, unknown>): { depositId?: string } => ({
    depositId: typeof search.depositId === "string" ? search.depositId : undefined,
  }),
  component: PosCheckoutPage,
});

const today = () => new Date().toISOString().slice(0, 10);
const now = () => new Date().toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });

function PosCheckoutPage() {
  const { products, defaultThreshold } = useInventory();
  const { customers, vatRate } = useSales();
  const settings = useDocumentSettings();
  const { name: branchName } = useCurrentBranch();
  const { staff: currentStaff } = useAuth();
  const { discounts: customerDiscounts } = useCustomerDiscounts();
  const isManager = currentStaff?.role === "Manager";
  // Session 9: a redeemed Manager-authorization ticket lifts the same
  // discount/VAT restrictions a real Manager role would, for this one sale
  // only. Everywhere below that used to gate on isManager alone now gates on
  // this instead — isManager itself is unchanged, still true only for an
  // actual Manager session.
  const [overrideTicket, setOverrideTicket] = useState<string | null>(null);
  const [overrideDialogOpen, setOverrideDialogOpen] = useState(false);
  const canOverride = isManager || !!overrideTicket;

  const [query, setQuery] = useState("");
  const [category, setCategory] = useState("all");

  // "Fulfil with a POS sale" deep-link from a customer deposit. When it
  // resolves to an Open deposit, the checkout locks to that customer and
  // carries a non-removable Deposit payment leg for the full deposit amount
  // (create_sale() redeems it and clears the 2450 liability).
  const navigate = useNavigate();
  const { depositId } = Route.useSearch();
  const { deposits } = useCustomerDeposits();
  const fulfilmentDeposit =
    depositId != null
      ? (deposits.find((d) => d.id === depositId && d.status === "Open") ?? null)
      : null;

  const [lines, setLines] = useState<PosLine[]>([]);
  const [customerId, setCustomerId] = useState("walk-in");
  const [saleDiscount, setSaleDiscount] = useState<Discount>(noDiscount());
  // Only meaningful for a non-Manager: which of the customer's existing
  // customer_discounts rows (if any) is currently applied. "none" clears it.
  const [selectedDiscountId, setSelectedDiscountId] = useState("none");
  const [vatMode, setVatMode] = useState<VatMode>(settings.tax.defaultVatMode);
  const [payments, setPayments] = useState<PosPayment[]>([{ id: "P1", method: "Cash", amount: 0 }]);
  // Optional free-text note — printed on the receipt only when filled in.
  // Same 240-char cap as invoice-form.tsx's Notes field.
  const [note, setNote] = useState("");
  // Only prefills when there's exactly one active bank account (no real
  // choice); "" otherwise, so a Card/Bank Transfer leg is never silently
  // routed to a guessed account.
  const { defaultId: defaultBankAccountId } = useActiveBankAccounts();
  const [completed, setCompleted] = useState<PosSale | null>(null);
  // Guards against a double-click firing two concurrent checkout() calls —
  // without this, a second click before the first request resolves creates
  // two separate sales (double stock deduction, duplicate charge).
  const [submitting, setSubmitting] = useState(false);
  const [holding, setHolding] = useState(false);
  const [heldSalesOpen, setHeldSalesOpen] = useState(false);
  const { heldSales } = useHeldSales();
  // True only when checkout() failed because the request never reached the
  // server (see isNetworkError()) — never for a real rejection (insufficient
  // stock, an unpriced product, a declined discount). The cart/payments/
  // customer are never touched here, only on a successful sale (see
  // resetSale() below), so there's nothing to restore — retrying just means
  // calling checkout() again against the exact same, still-intact state.
  const [connectionIssue, setConnectionIssue] = useState(false);

  // Inject the deposit once, when the deep-link resolves. Locks the sale to
  // the deposit's customer and seeds payments with the fixed Deposit leg +
  // an empty Cash leg for the balance. Keyed on the deposit id so it never
  // re-fires (after checkout the deposit is Fulfilled -> fulfilmentDeposit
  // is null and this is a no-op).
  useEffect(() => {
    if (!fulfilmentDeposit) return;
    setCustomerId(fulfilmentDeposit.customerId);
    setPayments([
      {
        id: "deposit",
        method: "Deposit",
        amount: fulfilmentDeposit.amount,
        depositId: fulfilmentDeposit.id,
      },
      { id: "P1", method: "Cash", amount: 0 },
    ]);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fulfilmentDeposit?.id]);

  // The deep-link pointed at a deposit that's already fulfilled/cancelled
  // (or gone) — drop the stale param and tell the cashier once.
  useEffect(() => {
    if (depositId == null || completed) return;
    if (!deposits.some((d) => d.id === depositId)) return; // still loading, or truly gone
    if (!fulfilmentDeposit) {
      toast.error("That deposit is no longer open.");
      navigate({ to: "/pos", search: {} });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [depositId, fulfilmentDeposit, deposits.length, completed]);

  // Mobile-only (see the fixed bottom bar below): where "tap the summary
  // bar" scrolls to. A plain DOM ref + scrollIntoView rather than any
  // routing/state change — this is purely a same-page scroll position.
  const cartSectionRef = useRef<HTMLElement>(null);
  function scrollToCart() {
    cartSectionRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  // Same SSR guard as useCurrentBranch(): today()/now() read the real clock,
  // which can tick a minute between the server render and the client's
  // hydration pass and trigger a hydration mismatch. Starting at null (never
  // computed during SSR) and filling it in from an effect — which only runs
  // client-side, after hydration — means the first paint the server sends
  // and the first paint the client hydrates against are identical.
  const [draftClock, setDraftClock] = useState<{ date: string; time: string } | null>(null);
  useEffect(() => {
    const update = () => setDraftClock({ date: today(), time: now() });
    update();
    const id = setInterval(update, 30_000);
    return () => clearInterval(id);
  }, []);

  const selectedCustomer =
    customerId === "walk-in" ? null : (customers.find((c) => c.id === customerId) ?? null);
  const customerName = selectedCustomer?.name ?? "Walk-in customer";

  // Store Credit only ever appears as a payment option once a real customer
  // with a spendable balance is picked — create_sale() enforces the same
  // "requires a customer, capped at their balance" rule server-side, so
  // this is a UI convenience (and a clearer error than a generic rejection
  // after the fact), not the actual boundary.
  const storeCreditAvailable = selectedCustomer?.storeCreditBalance ?? 0;
  const paymentMethodOptions: PosMethod[] =
    storeCreditAvailable > 0 ? [...POS_METHODS, "Store Credit"] : POS_METHODS;

  // A discount is always tied to one specific customer — this is only ever
  // non-empty once a real customer (not walk-in) is picked. create_sale()
  // enforces the same "must match an active row for this exact customer"
  // rule server-side, so this list is a UI convenience, not the boundary.
  const availableDiscounts =
    customerId === "walk-in"
      ? []
      : customerDiscounts.filter((d) => d.customerId === customerId && d.active);

  function pickCustomer(id: string) {
    setCustomerId(id);
    // A discount picked for the previous customer can't carry over to a
    // different one (or to walk-in, which can never have one at all).
    setSelectedDiscountId("none");
    setSaleDiscount(noDiscount());
    // Same reasoning as the discount above: a Store Credit leg is a claim
    // against one specific customer's balance, so switching customers (or
    // dropping to Walk-in) can't leave a stale leg pointed at someone else's.
    setPayments((prev) => {
      const withoutStoreCredit = prev.filter((p) => p.method !== "Store Credit");
      if (withoutStoreCredit.length === prev.length) return prev;
      return withoutStoreCredit.length > 0
        ? withoutStoreCredit
        : [{ id: "P1", method: "Cash", amount: 0 }];
    });
  }

  function pickCustomerDiscount(id: string) {
    setSelectedDiscountId(id);
    if (id === "none") {
      setSaleDiscount(noDiscount());
      return;
    }
    const picked = availableDiscounts.find((d) => d.id === id);
    if (picked) setSaleDiscount({ mode: picked.mode, value: picked.value });
  }

  // The server reads business_settings.vat_rate on checkout. This value is only
  // a preview; it keeps the screen aligned with that shared setting when loaded.
  const effectiveVatRate = vatRate ?? settings.tax.vatRate;
  // Built inside the memo (rather than closing over an outer `draft` object)
  // so the dependency list stays exhaustive: effectiveVatRate starts as
  // settings.tax.vatRate and swaps to the real business_settings.vat_rate
  // once useSales() finishes loading, and totals needs to recompute then.
  const totals = useMemo(
    () => posTotals({ lines, saleDiscount, vatMode, vatRate: effectiveVatRate, payments }),
    [lines, saleDiscount, vatMode, payments, effectiveVatRate],
  );
  const remaining = Math.round((totals.total - totals.paid) * 100) / 100;

  // Only cash can run over (and produce change); mobile money, card and bank
  // transfer must land on their exact share of the total.
  const cashPaid = round2(
    payments.filter((p) => p.method === "Cash").reduce((sum, p) => sum + p.amount, 0),
  );
  const nonCashPaid = round2(
    payments.filter((p) => p.method !== "Cash").reduce((sum, p) => sum + p.amount, 0),
  );
  const nonCashOverpaid = nonCashPaid > totals.total + 0.01;
  const underpaid = round2(cashPaid + nonCashPaid) < totals.total - 0.01;

  function addProduct(product: Product) {
    // Defense-in-depth: ProductGrid already disables the tile for a
    // priceless product, but this is the one place a line is actually
    // constructed, so it's the real client-side backstop — the
    // unbypassable enforcement is create_sale() rejecting the line
    // server-side regardless.
    if (!hasPrice(product)) {
      toast.error(`${product.name} has no selling price set — add one in Inventory to sell it.`);
      return;
    }
    // A quick confirmation near the tap — the product grid can be a full
    // screen scroll away from the cart on a narrow viewport, so there's
    // otherwise no feedback that the tap actually registered.
    toast.success(`Added ${product.name}`);
    setLines((prev) => {
      const existing = prev.find((l) => l.productId === product.id);
      if (existing) {
        return prev.map((l) =>
          l.productId === product.id ? { ...l, quantity: l.quantity + 1 } : l,
        );
      }
      return [
        ...prev,
        {
          id: `L${prev.length + 1}-${product.id}`,
          productId: product.id,
          name: product.name,
          unit: product.unit,
          category: product.category,
          quantity: 1,
          unitPrice: product.price,
          discount: noDiscount(),
          vat: true,
        },
      ];
    });
  }

  const updateLine = (id: string, patch: Partial<PosLine>) =>
    setLines((prev) => prev.map((l) => (l.id === id ? { ...l, ...patch } : l)));
  const removeLine = (id: string) => setLines((prev) => prev.filter((l) => l.id !== id));

  function resetSale() {
    setLines([]);
    setCustomerId("walk-in");
    setSaleDiscount(noDiscount());
    setSelectedDiscountId("none");
    setVatMode(settings.tax.defaultVatMode);
    setPayments([{ id: "P1", method: "Cash", amount: 0 }]);
    setNote("");
    setOverrideTicket(null);
    setConnectionIssue(false);
  }

  // A held sale is a draft, not an economic event — no server-side
  // validation happens at hold time (unlike checkout()), so this never
  // needs the connection-issue banner treatment: a failed hold just leaves
  // the cart exactly as it was, retryable with a plain toast.
  async function holdCurrentSale() {
    if (lines.length === 0 || submitting || holding) return;
    setHolding(true);
    try {
      await holdSale({
        customerId: customerId === "walk-in" ? null : customerId,
        customerName,
        lines,
        saleDiscount,
        vatMode,
        payments,
      });
      toast.success("Sale held — resume it anytime from Held sales.");
      resetSale();
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not hold this sale."));
    } finally {
      setHolding(false);
    }
  }

  // Restores a held sale exactly as it was parked — same fields
  // resetSale() clears, just populated instead of defaulted. The override
  // ticket is deliberately never carried forward: it's single-use and
  // time-boxed to the sale that requested it, so a resumed sale that still
  // needs one is asked for fresh, the same as any other unauthorized
  // discount/VAT deviation.
  function applyHeldSale(sale: HeldSale) {
    setLines(sale.lines);
    setCustomerId(sale.customerId ?? "walk-in");
    setSaleDiscount(sale.saleDiscount);
    setSelectedDiscountId("none");
    setVatMode(sale.vatMode);
    setPayments(
      sale.payments.length > 0 ? sale.payments : [{ id: "P1", method: "Cash", amount: 0 }],
    );
    setOverrideTicket(null);
    setConnectionIssue(false);
    toast.success(`Resumed ${sale.customerName}'s held sale.`);
  }

  // Mirrors create_sale()'s own "is this actually a deviation" checks, so a
  // still-active override ticket only gets spent on a sale that genuinely
  // needs one — an Attendant who gets authorized, then backs out to a
  // default-VAT, no-discount (or matching customer-discount) sale, keeps the
  // ticket usable for the rest of its 5-minute window instead of it being
  // silently consumed by a checkout that never needed it.
  const needsManagerOverride =
    !isManager &&
    (vatMode !== "per-item" ||
      lines.some((l) => !l.vat) ||
      lines.some((l) => l.discount.value !== 0) ||
      (saleDiscount.value !== 0 &&
        !availableDiscounts.some(
          (d) => d.mode === saleDiscount.mode && d.value === saleDiscount.value,
        )));

  async function checkout() {
    if (lines.length === 0 || submitting) return;
    if (settings.sales.requireCustomerOnPos && customerId === "walk-in") {
      toast.error("A customer is required on every sale. Pick one to continue.");
      return;
    }

    if (nonCashOverpaid) {
      toast.error(
        "Mobile money, card and bank transfer payments can't exceed the total — only cash can take change.",
      );
      return;
    }
    if (underpaid) {
      toast.error("Payments don't cover the total yet.");
      return;
    }
    if (payments.some((p) => POS_BANK_METHODS.includes(p.method) && !p.bankAccountId)) {
      toast.error("Pick the bank account for each card / bank transfer payment.");
      return;
    }
    if (fulfilmentDeposit && totals.total < fulfilmentDeposit.amount - 0.01) {
      toast.error(
        `Add items worth at least the ${currency(fulfilmentDeposit.amount)} deposit, or fulfil this deposit with an invoice instead.`,
      );
      return;
    }
    setSubmitting(true);
    setConnectionIssue(false);
    try {
      const sale = await createPosSale({
        customerId: customerId === "walk-in" ? null : customerId,
        customerName,
        lines,
        saleDiscount,
        vatMode,
        payments,
        overrideTicket: needsManagerOverride ? overrideTicket : null,
        notes: note.trim().slice(0, 240),
      });
      setCompleted(sale);
      toast.success(`Sale ${sale.id} completed`);
      const hadDeposit = payments.some((p) => p.method === "Deposit");
      resetSale();
      if (hadDeposit) {
        // The deposit is now Fulfilled server-side — refresh its store and
        // drop the deep-link param so a follow-up sale starts clean.
        void reloadCustomerDeposits();
        navigate({ to: "/pos", search: {} });
      }
    } catch (error) {
      // A dropped connection means the request never reached the server —
      // stock, pricing and the cart are all exactly as they were, nothing
      // to lose. Surfaced as a persistent inline banner with its own Retry
      // button rather than folded into the generic toast below, so it
      // reads as "try again once you're back" rather than "something went
      // wrong with your sale" — a real rejection (insufficient stock, an
      // unpriced product, a declined discount) still only ever gets the
      // toast, unchanged.
      if (isNetworkError(error)) {
        setConnectionIssue(true);
      } else {
        toast.error(getErrorMessage(error, "Could not complete sale."));
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="grid gap-6 pb-20 xl:grid-cols-[minmax(0,1fr)_400px] xl:pb-0">
      <ProductGrid
        products={products}
        defaultThreshold={defaultThreshold}
        query={query}
        onQueryChange={setQuery}
        category={category}
        onCategoryChange={setCategory}
        onSelect={addProduct}
      />

      <aside className="flex min-w-0 flex-col gap-4">
        {/* Customer */}
        <section className="card-surface p-4">
          <div className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3">
            <div className="flex min-w-0 items-center gap-2">
              <UserRound className="size-4 shrink-0 text-muted-foreground" />
              <Label className="text-sm">Customer</Label>
            </div>
            <Badge variant="outline">Optional</Badge>
          </div>
          <Select value={customerId} onValueChange={pickCustomer} disabled={!!fulfilmentDeposit}>
            <SelectTrigger className="mt-3 w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="walk-in">Walk-in customer</SelectItem>
              {customers.map((c) => (
                <SelectItem key={c.id} value={c.id}>
                  {c.name} · {c.phone}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          {fulfilmentDeposit && (
            <p className="mt-2 text-xs text-muted-foreground">
              Fulfilling deposit {fulfilmentDeposit.id} — {currency(fulfilmentDeposit.amount)} is
              pre-applied below; add the reserved items and collect the balance.
            </p>
          )}
          {storeCreditAvailable > 0 && (
            <p className="mt-2 text-xs text-muted-foreground">
              {currency(storeCreditAvailable)} store credit available
            </p>
          )}
        </section>

        {/* Cart */}
        <section ref={cartSectionRef} className="card-surface flex flex-col overflow-hidden">
          <div className="flex items-center justify-between border-b border-border px-4 py-3">
            <div className="flex items-center gap-2">
              <ShoppingCart className="size-4 text-muted-foreground" />
              <h2 className="text-sm font-semibold">Current cart</h2>
              <Badge variant="secondary">{lines.length}</Badge>
            </div>
            <div className="flex items-center gap-1">
              <Button
                variant="outline"
                size="sm"
                className="gap-1.5"
                onClick={() => setHeldSalesOpen(true)}
              >
                <PauseCircle className="size-3.5" /> Held sales
                {heldSales.length > 0 && <Badge variant="secondary">{heldSales.length}</Badge>}
              </Button>
              {lines.length > 0 && (
                <Button variant="ghost" size="sm" onClick={resetSale}>
                  Clear
                </Button>
              )}
            </div>
          </div>

          <div className="max-h-[380px] divide-y divide-border overflow-y-auto">
            {lines.length === 0 && (
              <p className="px-4 py-10 text-center text-sm text-muted-foreground">
                Tap a product to start a sale.
              </p>
            )}
            {lines.map((line) => (
              <CartLine
                key={line.id}
                line={line}
                vatMode={vatMode}
                canOverride={canOverride}
                onUpdate={updateLine}
                onRemove={removeLine}
              />
            ))}
          </div>
        </section>

        {/* Sale-level discount and VAT */}
        <section className="card-surface space-y-3 p-4">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-semibold">Whole sale</h2>
            {!isManager &&
              (overrideTicket ? (
                <Badge variant="secondary" className="gap-1">
                  <ShieldCheck className="size-3" /> Manager override active
                </Badge>
              ) : (
                <Button
                  variant="outline"
                  size="sm"
                  className="h-7 gap-1.5 text-xs"
                  onClick={() => setOverrideDialogOpen(true)}
                >
                  <ShieldCheck className="size-3.5" /> Ask a Manager
                </Button>
              ))}
          </div>
          <div className="flex items-center gap-2">
            <Label className="w-20 shrink-0 text-xs text-muted-foreground">Discount</Label>
            {canOverride ? (
              <>
                <Select
                  value={saleDiscount.mode}
                  onValueChange={(mode) =>
                    setSaleDiscount((d) => ({ ...d, mode: mode as Discount["mode"] }))
                  }
                >
                  <SelectTrigger className="h-9 w-[100px] text-xs">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="amount">GHS off</SelectItem>
                    <SelectItem value="percent">% off</SelectItem>
                  </SelectContent>
                </Select>
                <Input
                  value={saleDiscount.value || ""}
                  placeholder="0"
                  onChange={(e) =>
                    setSaleDiscount((d) => ({ ...d, value: Number(e.target.value) || 0 }))
                  }
                  className="h-9 flex-1"
                  aria-label="Whole sale discount"
                />
              </>
            ) : availableDiscounts.length > 0 ? (
              // An Attendant can only pick one of this customer's existing
              // discounts, never type an amount — create_sale() rejects any
              // other value from a non-Manager server-side regardless.
              <Select value={selectedDiscountId} onValueChange={pickCustomerDiscount}>
                <SelectTrigger className="h-9 flex-1 text-xs">
                  <SelectValue placeholder="No discount" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">No discount</SelectItem>
                  {availableDiscounts.map((d) => (
                    <SelectItem key={d.id} value={d.id}>
                      {d.label} ({d.mode === "percent" ? `${d.value}%` : currency(d.value)})
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            ) : (
              <p className="flex-1 text-xs text-muted-foreground">
                {customerId === "walk-in"
                  ? "Pick a customer to see their discounts."
                  : "No discounts set up for this customer — ask a Manager to create one."}
              </p>
            )}
          </div>
          <div className="flex items-center gap-2">
            <Label className="w-20 shrink-0 text-xs text-muted-foreground">VAT</Label>
            <Select
              value={vatMode}
              onValueChange={(v) => setVatMode(v as VatMode)}
              disabled={!canOverride}
            >
              <SelectTrigger className="h-9 flex-1 text-xs">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="per-item">Per item (default)</SelectItem>
                <SelectItem value="all">Charge VAT on everything</SelectItem>
                <SelectItem value="none">No VAT on this sale</SelectItem>
              </SelectContent>
            </Select>
            <span className="text-xs text-muted-foreground">{effectiveVatRate}%</span>
          </div>
          {!canOverride && (
            <p className="text-xs text-muted-foreground">
              Changing VAT for the whole sale needs a Manager — ask a Manager above.
            </p>
          )}
        </section>

        <ManagerOverrideDialog
          open={overrideDialogOpen}
          onOpenChange={setOverrideDialogOpen}
          requestedBy={currentStaff?.id ?? ""}
          onAuthorized={setOverrideTicket}
        />

        {/* Payments */}
        <section className="card-surface space-y-3 p-4">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-semibold">Payment</h2>
            <Button
              variant="outline"
              size="sm"
              onClick={() =>
                setPayments((p) => [
                  ...p,
                  {
                    id: `P${p.length + 1}-${Math.random().toString(36).slice(2, 6)}`,
                    method: "Mobile Money",
                    amount: Math.max(0, remaining),
                  },
                ])
              }
            >
              <Plus className="size-3.5" /> Split
            </Button>
          </div>

          {payments.map((payment, index) =>
            payment.method === "Deposit" ? (
              <div
                key={payment.id}
                className="flex items-center justify-between rounded-lg border border-primary/40 bg-primary/5 px-3 py-2 text-sm"
              >
                <span className="font-medium">Deposit {payment.depositId} applied</span>
                <span className="tabular-nums font-semibold">{currency(payment.amount)}</span>
              </div>
            ) : (
              <div key={payment.id} className="space-y-2">
                <div className="flex items-center gap-2">
                  <Select
                    value={payment.method}
                    onValueChange={(method) =>
                      setPayments((prev) =>
                        prev.map((p) =>
                          p.id === payment.id
                            ? {
                                ...p,
                                method: method as PosMethod,
                                bankAccountId: POS_BANK_METHODS.includes(method as PosMethod)
                                  ? (p.bankAccountId ?? defaultBankAccountId ?? null)
                                  : null,
                              }
                            : p,
                        ),
                      )
                    }
                  >
                    <SelectTrigger className="h-9 flex-1 text-xs">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {paymentMethodOptions.map((m) => (
                        <SelectItem key={m} value={m}>
                          {m}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <Input
                    value={payment.amount || ""}
                    placeholder="0.00"
                    onChange={(e) =>
                      setPayments((prev) =>
                        prev.map((p) =>
                          p.id === payment.id ? { ...p, amount: Number(e.target.value) || 0 } : p,
                        ),
                      )
                    }
                    className="h-9 w-28 text-right"
                    aria-label={`${payment.method} amount`}
                  />
                  {payments.length > 1 && (
                    <button
                      type="button"
                      aria-label="Remove payment"
                      onClick={() => setPayments((prev) => prev.filter((p) => p.id !== payment.id))}
                      className="rounded-md p-1 text-muted-foreground hover:text-destructive"
                    >
                      <X className="size-4" />
                    </button>
                  )}
                  {payments.length === 1 && index === 0 && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() =>
                        setPayments((prev) =>
                          prev.map((p) =>
                            p.id === payment.id ? { ...p, amount: totals.total } : p,
                          ),
                        )
                      }
                    >
                      Exact
                    </Button>
                  )}
                </div>
                {POS_BANK_METHODS.includes(payment.method) && (
                  <div className="pl-1">
                    <BankAccountSelect
                      value={payment.bankAccountId ?? ""}
                      onChange={(bankAccountId) =>
                        setPayments((prev) =>
                          prev.map((p) => (p.id === payment.id ? { ...p, bankAccountId } : p)),
                        )
                      }
                      placeholder={`Which bank received this ${payment.method}?`}
                    />
                  </div>
                )}
              </div>
            ),
          )}

          <div className="space-y-1.5 pt-1">
            <Label htmlFor="pos-note" className="text-xs text-muted-foreground">
              Note (optional — printed on the receipt)
            </Label>
            <Textarea
              id="pos-note"
              rows={2}
              maxLength={240}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Delivery instructions, site reference, customer request…"
              className="text-sm"
            />
          </div>

          <div className="space-y-1.5 border-t border-border pt-3 text-sm">
            <Row label="Subtotal" value={currency(totals.subtotal)} />
            {totals.lineDiscounts > 0 && (
              <Row label="Item discounts" value={`-${currency(totals.lineDiscounts)}`} />
            )}
            {totals.saleDiscount > 0 && (
              <Row label="Sale discount" value={`-${currency(totals.saleDiscount)}`} />
            )}
            <Row label={`VAT (${settings.tax.vatRate}%)`} value={currency(totals.vat)} />
            <div className="flex items-center justify-between pt-1 text-base font-semibold">
              <span>Total</span>
              <span>{currency(totals.total)}</span>
            </div>
            <Row label="Paid" value={currency(totals.paid)} />
            <div
              className={cn(
                "flex items-center justify-between text-sm font-medium",
                nonCashOverpaid
                  ? "text-destructive"
                  : underpaid
                    ? "text-amber-600 dark:text-amber-400"
                    : "text-primary",
              )}
            >
              <span>
                {nonCashOverpaid
                  ? "Non-cash overpaid"
                  : underpaid
                    ? "Still to collect"
                    : remaining < 0
                      ? "Change due"
                      : "Payments balanced"}
              </span>
              <span>{currency(Math.abs(remaining))}</span>
            </div>
          </div>

          {connectionIssue && (
            <div className="flex items-start gap-2 rounded-xl border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">
              <WifiOff className="mt-0.5 size-4 shrink-0" />
              <div className="flex-1">
                <p className="font-medium">Connection lost — this sale wasn&apos;t submitted</p>
                <p className="mt-0.5 text-xs text-destructive/90">
                  Your cart is untouched. Check your connection, then try again.
                </p>
              </div>
              <Button
                size="sm"
                variant="outline"
                className="gap-1.5 border-destructive/40 text-destructive hover:text-destructive"
                onClick={checkout}
                disabled={submitting}
              >
                <RefreshCcw className="size-3.5" /> Retry
              </Button>
            </div>
          )}

          <div className="flex gap-2">
            <Button
              variant="outline"
              className="h-11 gap-1.5"
              onClick={holdCurrentSale}
              disabled={lines.length === 0 || submitting || holding}
            >
              <PauseCircle className="size-4" /> {holding ? "Holding…" : "Hold"}
            </Button>
            <Button
              className="h-11 flex-1 text-base"
              onClick={checkout}
              disabled={lines.length === 0 || submitting}
            >
              <Receipt className="size-4" />{" "}
              {submitting
                ? "Completing sale…"
                : `Checkout ${lines.length > 0 ? currency(totals.total) : ""}`}
            </Button>
          </div>
        </section>

        {/* Live receipt preview */}
        <section className="card-surface p-4">
          <h2 className="mb-3 text-sm font-semibold">Receipt preview</h2>
          <ReceiptPreview
            sale={{
              id: "Draft",
              date: draftClock?.date ?? "…",
              time: draftClock?.time ?? "…",
              customerName,
              // create_sale() always attributes the receipt to the signed-in
              // user server-side — this is preview-only, so it can't be wrong.
              cashier: currentStaff?.name ?? "…",
              branch: branchName ?? "…",
              lines,
              saleDiscount,
              vatMode,
              vatRate: effectiveVatRate,
              payments,
              notes: note,
            }}
          />
        </section>
      </aside>

      <HeldSalesDialog
        open={heldSalesOpen}
        onOpenChange={setHeldSalesOpen}
        hasActiveCart={lines.length > 0}
        onResume={applyHeldSale}
      />

      <Dialog open={!!completed} onOpenChange={(open) => !open && setCompleted(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Sale completed</DialogTitle>
          </DialogHeader>
          {completed && <ReceiptPreview sale={completed} />}
          <div className="flex gap-2">
            <Button variant="outline" className="flex-1 gap-2" onClick={() => window.print()}>
              <Printer className="size-4" /> Print receipt
            </Button>
            <Button className="flex-1" onClick={() => setCompleted(null)}>
              New sale
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {completed && (
        <PrintDocument
          pageSize={settings.receiptPaper === "A4" ? "A4" : `${settings.receiptPaper} auto`}
          margin={settings.receiptPaper === "A4" ? "12mm" : "3mm"}
        >
          <PrintableReceipt sale={completed} settings={settings} />
        </PrintDocument>
      )}

      {/* xl:hidden matches the grid's own xl:grid-cols breakpoint above
          exactly — visible precisely when the layout is stacked (product
          grid above the cart, not beside it), gone the instant the two
          columns sit side by side and the cart is already always in view. */}
      {lines.length > 0 && (
        <MobileCartBar
          itemCount={lines.length}
          total={totals.total}
          remaining={remaining}
          nonCashOverpaid={nonCashOverpaid}
          underpaid={underpaid}
          onTap={scrollToCart}
        />
      )}
    </div>
  );
}

function MobileCartBar({
  itemCount,
  total,
  remaining,
  nonCashOverpaid,
  underpaid,
  onTap,
}: {
  itemCount: number;
  total: number;
  /** totals.total - totals.paid — negative when cash overpays (change due). */
  remaining: number;
  nonCashOverpaid: boolean;
  underpaid: boolean;
  onTap: () => void;
}) {
  // Same four states, same precedence as the desktop payment-summary line —
  // just carried as a bar tint (the bar's own bg-primary would swallow the
  // desktop text colors) plus the label + figure on the right.
  const status = nonCashOverpaid
    ? {
        label: "Non-cash overpaid",
        tone: "bg-destructive text-destructive-foreground",
        showFigure: true,
      }
    : underpaid
      ? { label: "Still to collect", tone: "bg-amber-500 text-amber-950", showFigure: true }
      : remaining < 0
        ? { label: "Change due", tone: "bg-primary text-primary-foreground", showFigure: true }
        : {
            label: "Payments balanced",
            tone: "bg-primary text-primary-foreground",
            showFigure: false,
          };
  const figure = currency(Math.abs(remaining));

  return (
    <button
      type="button"
      onClick={onTap}
      className={cn(
        "fixed inset-x-0 bottom-0 z-40 flex items-center justify-between gap-3 border-t border-border px-4 py-3 shadow-[0_-4px_12px_rgba(0,0,0,0.12)] xl:hidden",
        status.tone,
      )}
      aria-label={`View cart — ${itemCount} item${itemCount === 1 ? "" : "s"}, ${currency(total)}. ${status.label}${status.showFigure ? ` ${figure}` : ""}`}
    >
      <span className="flex min-w-0 items-center gap-2 text-sm font-medium">
        <ShoppingCart className="size-4 shrink-0" />
        <span className="truncate">
          {itemCount} item{itemCount === 1 ? "" : "s"} · {currency(total)}
        </span>
      </span>
      <span className="shrink-0 text-sm font-semibold">
        {status.label}
        {status.showFigure ? ` ${figure}` : ""}
      </span>
    </button>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between text-muted-foreground">
      <span>{label}</span>
      <span className="text-foreground">{value}</span>
    </div>
  );
}

function CartLine({
  line,
  vatMode,
  canOverride,
  onUpdate,
  onRemove,
}: {
  line: PosLine;
  vatMode: VatMode;
  /** True for an actual Manager, or an Attendant with a redeemed Manager
   * override ticket for this sale (Session 9) — either way, this line's
   * discount and VAT can be edited freely. */
  canOverride: boolean;
  onUpdate: (id: string, patch: Partial<PosLine>) => void;
  onRemove: (id: string) => void;
}) {
  // Decoupled from line.quantity while focused so the field can be cleared and
  // typed into instead of the incoming digit being appended to a stuck "1".
  const [quantityText, setQuantityText] = useState<string | null>(null);
  const gross = lineGross(line);
  const discShown = discountAmount(line.discount, gross, line.quantity);
  // The pre-clamp figure, so the helper line can flag when the clamp bit.
  const discRaw =
    line.discount.mode === "percent"
      ? (gross * line.discount.value) / 100
      : line.discount.mode === "amount_per_unit"
        ? line.discount.value * line.quantity
        : line.discount.value;
  const discCapped = discRaw - discShown > 0.005;

  return (
    <div className="space-y-2.5 px-4 py-3">
      <div className="grid grid-cols-[minmax(0,1fr)_auto] items-start gap-2">
        <div className="min-w-0">
          <p className="truncate text-sm font-medium">{line.name}</p>
          <p className="text-xs text-muted-foreground">
            {currency(line.unitPrice)} per {String(line.unit).toLowerCase()}
          </p>
        </div>
        <button
          type="button"
          onClick={() => onRemove(line.id)}
          className="rounded-md p-1 text-muted-foreground hover:text-destructive"
          aria-label={`Remove ${line.name}`}
        >
          <Trash2 className="size-4" />
        </button>
      </div>

      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-1">
          <Button
            variant="outline"
            size="icon"
            className="size-8"
            aria-label="Decrease quantity"
            onClick={() => onUpdate(line.id, { quantity: Math.max(1, line.quantity - 1) })}
          >
            <Minus className="size-3.5" />
          </Button>
          <Input
            value={quantityText ?? String(line.quantity)}
            onChange={(e) => {
              const raw = e.target.value;
              setQuantityText(raw);
              const n = Math.trunc(Number(raw));
              if (raw.trim() !== "" && Number.isFinite(n) && n >= 1) {
                onUpdate(line.id, { quantity: n });
              }
            }}
            onBlur={() => {
              if (quantityText !== null && quantityText.trim() === "") {
                onUpdate(line.id, { quantity: 1 });
              }
              setQuantityText(null);
            }}
            inputMode="numeric"
            className="h-8 w-14 text-center"
            aria-label="Quantity"
          />
          <Button
            variant="outline"
            size="icon"
            className="size-8"
            aria-label="Increase quantity"
            onClick={() => onUpdate(line.id, { quantity: line.quantity + 1 })}
          >
            <Plus className="size-3.5" />
          </Button>
        </div>
        <span className="text-sm font-semibold">{currency(lineNet(line))}</span>
      </div>

      <div className="flex items-center gap-2">
        {/* Per-item discounts need a Manager (or a redeemed override ticket)
            — there's no customer-attached discount concept at the line
            level (only the whole sale carries one), so unlike the
            whole-sale field there's no picker fallback for an unauthorized
            Attendant, just no control at all. create_sale() rejects any
            non-zero line discount_value without one, server-side. */}
        {canOverride ? (
          <>
            <Select
              value={line.discount.mode}
              onValueChange={(mode) =>
                onUpdate(line.id, {
                  discount: { ...line.discount, mode: mode as Discount["mode"] },
                })
              }
            >
              <SelectTrigger className="h-8 w-[132px] text-xs">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {/* "GHS off" is a flat amount off the whole line; "GHS off /
                    unit" multiplies by quantity. Kept as two clearly
                    different labels so they can't be mistaken for each
                    other — the helper line below spells out which is live. */}
                <SelectItem value="amount">GHS off</SelectItem>
                <SelectItem value="amount_per_unit">GHS off / unit</SelectItem>
                <SelectItem value="percent">% off</SelectItem>
              </SelectContent>
            </Select>
            <Input
              value={line.discount.value || ""}
              placeholder="0"
              onChange={(e) =>
                onUpdate(line.id, {
                  discount: { ...line.discount, value: Number(e.target.value) || 0 },
                })
              }
              className="h-8 w-20 text-xs"
              aria-label="Line discount"
            />
          </>
        ) : null}
        <label
          className={cn(
            "ml-auto flex items-center gap-2 text-xs",
            vatMode !== "per-item" && "opacity-50",
          )}
        >
          VAT
          <Switch
            checked={vatMode === "all" ? true : vatMode === "none" ? false : line.vat}
            disabled={vatMode !== "per-item" || !canOverride}
            onCheckedChange={(vat) => onUpdate(line.id, { vat })}
            aria-label="Apply VAT to this item"
          />
        </label>
      </div>
      {canOverride && discShown > 0 && (
        <p className="text-xs text-muted-foreground">
          {line.discount.mode === "amount_per_unit"
            ? `${currency(line.discount.value)} off each unit × ${line.quantity} ${String(
                line.unit,
              ).toLowerCase()}`
            : line.discount.mode === "percent"
              ? `${line.discount.value}% off the line`
              : `${currency(line.discount.value)} off the whole line`}
          {" — "}-{currency(discShown)} on {currency(gross)}
          {discCapped ? " (capped at the line total)" : ""}
        </p>
      )}
    </div>
  );
}
