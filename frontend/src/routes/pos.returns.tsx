import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { ArrowLeftRight, CheckCircle2, Search, ShieldAlert, Undo2 } from "lucide-react";
import { toast } from "sonner";

import { ProductSearchSelect } from "@/components/product-search-select";
import { InlineAddCustomerDialog } from "@/components/sales/inline-add-customer-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { useAuth } from "@/data/auth-store";
import { addCustomer, type NewCustomer, useCustomers } from "@/data/customer-store";
import { currency } from "@/data/dashboard";
import { hasPrice, useInventory } from "@/data/inventory-store";
import {
  POS_BANK_METHODS,
  POS_METHODS,
  posTotals,
  round2,
  type PosLine,
  type PosMethod,
  type PosSale,
} from "@/data/pos";
import { createPosReturnBatch, type NewReturnBatch, usePosSales } from "@/data/pos-store";
import { BankAccountSelect, useActiveBankAccounts } from "@/components/banking/bank-account-select";
import { cn, getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/pos/returns")({
  component: PosReturnsPage,
});

type Refund = "Cash refund" | "Store credit";
/** Per-sale-line draft while the cashier builds the return. A line is "in
 * the return" iff it has an entry in `drafts`. */
type Draft = { qty: number; replacementId: string | null; replacementQty: number };

function PosReturnsPage() {
  const { sales } = usePosSales();
  const { products } = useInventory();
  const { customers } = useCustomers();
  const { staff: currentStaff } = useAuth();
  const isManager = currentStaff?.role === "Manager";
  const { defaultId: defaultBankAccountId } = useActiveBankAccounts();

  const [query, setQuery] = useState("");
  const [saleId, setSaleId] = useState<string | null>(null);
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  const [refundChoice, setRefundChoice] = useState<Refund>("Store credit");
  const [topUpMethod, setTopUpMethod] = useState<Exclude<PosMethod, "Store Credit">>("Cash");
  const [topUpBankAccountId, setTopUpBankAccountId] = useState("");
  const [reason, setReason] = useState("");
  // Only relevant when the original sale has no customer_id (a Walk-in sale)
  // and some included line resolves to Store credit — the credit has to land
  // somewhere, so staff pick or create a customer right here rather than
  // being sent to the Customers page and losing the in-progress return.
  const [walkInCustomerId, setWalkInCustomerId] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // A voided sale never happened as far as the books are concerned — it
  // can't be returned against (the backend blocks it too).
  const returnableSales = useMemo(() => sales.filter((s) => !s.voidedAt), [sales]);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return returnableSales.slice(0, 5);
    return returnableSales.filter(
      (s) => s.id.toLowerCase().includes(q) || s.customerName.toLowerCase().includes(q),
    );
  }, [returnableSales, query]);

  const sale = returnableSales.find((s) => s.id === saleId) ?? null;

  // create_sale_return_batch() delegates each line to create_sale_return(),
  // which sums every prior return against a line's own returned_sale_line_id
  // and rejects anything that would push the total past what was sold —
  // that's the real, structural guarantee. This mirrors the same cap
  // client-side so a fully-returned line reads as already handled instead of
  // a still-submittable one the server would reject a moment later.
  const returnedByLine = useMemo(() => {
    const m = new Map<string, number>();
    for (const r of sale?.returns ?? []) {
      m.set(r.returnedSaleLineId, (m.get(r.returnedSaleLineId) ?? 0) + r.returned.quantity);
    }
    return m;
  }, [sale]);
  const remainingFor = (l: PosLine) => l.quantity - (returnedByLine.get(l.id) ?? 0);

  const effectiveRefundChoice: Refund = isManager ? refundChoice : "Store credit";

  // One computed row per included line: its value, difference, and the
  // resolution that difference + the shared refund choice imply. Same
  // per-line arithmetic the single-line flow always used, just mapped over
  // every checked line at once.
  const items = useMemo(() => {
    if (!sale) return [];
    return Object.entries(drafts).flatMap(([lineId, d]) => {
      const line = sale.lines.find((l) => l.id === lineId);
      if (!line) return [];
      const replacement = d.replacementId
        ? (products.find((p) => p.id === d.replacementId) ?? null)
        : null;
      const returnValue = line.unitPrice * d.qty;
      const replacementValue =
        replacement && hasPrice(replacement) ? replacement.price * d.replacementQty : 0;
      const difference = round2(replacementValue - returnValue);
      const resolution: NewReturnBatch["refundChoice"] | "Top-up collected" | "Even exchange" =
        !replacement
          ? effectiveRefundChoice
          : difference > 0.01
            ? "Top-up collected"
            : difference < -0.01
              ? effectiveRefundChoice
              : "Even exchange";
      return [
        {
          line,
          qty: d.qty,
          replacement,
          replacementQty: d.replacementQty,
          returnValue,
          replacementValue,
          difference,
          resolution,
          unpricedReplacement: !!replacement && !hasPrice(replacement),
        },
      ];
    });
  }, [sale, drafts, products, effectiveRefundChoice]);

  const totalBack = round2(items.reduce((s, it) => s + Math.max(0, -it.difference), 0));
  const totalTopUp = round2(items.reduce((s, it) => s + Math.max(0, it.difference), 0));
  const anyRefundLine = items.some((it) => !it.replacement || it.difference < -0.01);
  const anyTopUpLine = items.some((it) => it.difference > 0.01);
  const topUpNeedsBankAccount = anyTopUpLine && POS_BANK_METHODS.includes(topUpMethod);
  const effectiveTopUpBankAccountId = topUpBankAccountId || defaultBankAccountId;

  // The original sale is a Walk-in (no customer_id) and some line in this
  // return puts money back as Store credit — the only case that needs a
  // customer attached right here on the return screen. create_sale_return()
  // enforces this server-side too (rejects a Walk-in Store-credit return
  // with no customer), so a direct API call is blocked there as well.
  const needsWalkInCustomer =
    anyRefundLine && effectiveRefundChoice === "Store credit" && !!sale && !sale.customerId;

  const linesAvailable = (sale?.lines ?? []).filter((l) => remainingFor(l) > 0);
  const allFullyReturned = !!sale && linesAvailable.length === 0;

  const canSubmit =
    !submitting &&
    items.length > 0 &&
    !items.some((it) => it.unpricedReplacement) &&
    items.every((it) => it.qty >= 1 && it.qty <= remainingFor(it.line)) &&
    items.every((it) => !it.replacement || it.replacementQty >= 1) &&
    !(needsWalkInCustomer && !walkInCustomerId) &&
    !(topUpNeedsBankAccount && !effectiveTopUpBankAccountId);

  function selectSale(next: PosSale) {
    setSaleId(next.id);
    setDrafts({});
    setRefundChoice("Store credit");
    setTopUpMethod("Cash");
    setTopUpBankAccountId("");
    setReason("");
    setWalkInCustomerId(null);
  }

  function toggleLine(l: PosLine, on: boolean) {
    setDrafts((prev) => {
      const next = { ...prev };
      if (on) next[l.id] = { qty: 1, replacementId: null, replacementQty: 1 };
      else delete next[l.id];
      return next;
    });
  }
  function patchDraft(lineId: string, patch: Partial<Draft>) {
    setDrafts((prev) =>
      prev[lineId] ? { ...prev, [lineId]: { ...prev[lineId], ...patch } } : prev,
    );
  }

  async function onNewWalkInCustomer(input: NewCustomer) {
    const created = await addCustomer(input);
    setWalkInCustomerId(created.id);
  }

  async function submit() {
    if (!sale || items.length === 0) return;
    if (items.some((it) => it.unpricedReplacement)) {
      toast.error("A replacement has no selling price — add one in Inventory first.");
      return;
    }
    if (needsWalkInCustomer && !walkInCustomerId) {
      toast.error("Select or add a customer to issue store credit on this Walk-in sale.");
      return;
    }
    if (topUpNeedsBankAccount && !effectiveTopUpBankAccountId) {
      toast.error(`Pick the bank account this ${topUpMethod} top-up settled into.`);
      return;
    }
    const batch: NewReturnBatch = {
      lines: items.map((it) => ({
        returnedSaleLineId: it.line.id,
        returnedQuantity: it.qty,
        replacement: it.replacement
          ? { productId: it.replacement.id, quantity: it.replacementQty }
          : null,
      })),
      reason: reason.trim() || "No reason given",
      refundChoice: effectiveRefundChoice,
      paymentMethod: anyTopUpLine ? topUpMethod : null,
      bankAccountId: topUpNeedsBankAccount ? effectiveTopUpBankAccountId : null,
      customerId: needsWalkInCustomer ? walkInCustomerId : null,
    };
    try {
      setSubmitting(true);
      await createPosReturnBatch(sale.id, batch);
      toast.success(
        `Return recorded — ${items.length} item${items.length === 1 ? "" : "s"} on ${sale.id}`,
      );
      setSaleId(null);
      setDrafts({});
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not record the return."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,420px)_minmax(0,1fr)]">
      <section className="card-surface flex flex-col overflow-hidden">
        <div className="border-b border-border p-4">
          <h2 className="text-sm font-semibold">Find a past sale</h2>
          <div className="relative mt-3">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Receipt number or customer name…"
              className="h-10 pl-9"
              aria-label="Search past sales"
            />
          </div>
        </div>
        <ul className="divide-y divide-border">
          {results.map((s) => {
            const totals = posTotals(s);
            return (
              <li key={s.id}>
                <button
                  type="button"
                  onClick={() => selectSale(s)}
                  className={cn(
                    "grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-muted/50",
                    saleId === s.id && "bg-primary/5",
                  )}
                >
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium">{s.id}</p>
                    <p className="truncate text-xs text-muted-foreground">
                      {s.customerName} · {s.date} {s.time} · {s.lines.length} items
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="text-sm font-semibold">{currency(totals.total)}</p>
                    {s.returns.length > 0 && (
                      <Badge variant="outline" className="mt-1">
                        {s.returns.length} return{s.returns.length > 1 ? "s" : ""}
                      </Badge>
                    )}
                  </div>
                </button>
              </li>
            );
          })}
          {results.length === 0 && (
            <li className="px-4 py-10 text-center text-sm text-muted-foreground">
              No sale matches that search.
            </li>
          )}
        </ul>
      </section>

      {!sale ? (
        <section className="card-surface flex flex-col items-center justify-center gap-2 px-6 py-24 text-center">
          <ArrowLeftRight className="size-8 text-muted-foreground" />
          <p className="text-sm font-medium">Select a sale to start a return</p>
          <p className="max-w-sm text-sm text-muted-foreground">
            Look up the receipt, tick every item coming back, then swap them for other products or
            issue one refund for the lot.
          </p>
        </section>
      ) : (
        <section className="space-y-4">
          <div className="card-surface p-5">
            <div className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3">
              <div className="min-w-0">
                <h2 className="truncate text-lg font-semibold">Return against {sale.id}</h2>
                <p className="truncate text-sm text-muted-foreground">
                  {sale.customerName} · sold {sale.date} at {sale.time} by {sale.cashier}
                </p>
              </div>
              <Button variant="ghost" size="sm" onClick={() => setSaleId(null)}>
                Change sale
              </Button>
            </div>

            {allFullyReturned ? (
              <div className="mt-5 flex items-center gap-3 rounded-xl border border-border bg-muted/30 px-3 py-3 text-sm text-muted-foreground">
                <CheckCircle2 className="size-5 shrink-0" />
                Every line on this sale has already been returned in full — nothing left to process.
                Choose a different sale.
              </div>
            ) : (
              <div className="mt-5 space-y-3">
                <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  Items coming back
                </p>
                <ul className="divide-y divide-border rounded-xl border border-border">
                  {sale.lines.map((l) => {
                    const remaining = remainingFor(l);
                    const already = returnedByLine.get(l.id) ?? 0;
                    const draft = drafts[l.id];
                    const included = !!draft;
                    const it = items.find((x) => x.line.id === l.id);
                    return (
                      <li key={l.id} className="p-3">
                        <div className="flex items-start gap-3">
                          <Checkbox
                            checked={included}
                            disabled={remaining <= 0}
                            onCheckedChange={(v) => toggleLine(l, v === true)}
                            aria-label={`Return ${l.name}`}
                            className="mt-0.5"
                          />
                          <div className="min-w-0 flex-1">
                            <p className="text-sm font-medium">
                              {l.name}
                              {remaining <= 0 && (
                                <span className="ml-2 text-xs font-normal text-muted-foreground">
                                  · fully returned
                                </span>
                              )}
                            </p>
                            <p className="text-xs text-muted-foreground">
                              {l.quantity} {String(l.unit).toLowerCase()} sold @{" "}
                              {currency(l.unitPrice)}
                              {already > 0 && ` · ${already} already returned`}
                            </p>

                            {included && draft && (
                              <div className="mt-3 space-y-3">
                                <div className="flex flex-wrap items-center gap-3">
                                  <Label className="text-xs text-muted-foreground">Quantity</Label>
                                  <Input
                                    value={draft.qty}
                                    onChange={(e) =>
                                      patchDraft(l.id, {
                                        qty: Math.min(
                                          remaining,
                                          Math.max(1, Number(e.target.value) || 1),
                                        ),
                                      })
                                    }
                                    className="h-9 w-20"
                                    aria-label={`Return quantity for ${l.name}`}
                                  />
                                  <span className="text-xs text-muted-foreground">
                                    of {remaining} returnable · value{" "}
                                    <span className="font-medium text-foreground">
                                      {currency(l.unitPrice * draft.qty)}
                                    </span>
                                  </span>
                                </div>

                                <div className="space-y-2">
                                  <Label className="text-xs text-muted-foreground">
                                    Replacement (optional)
                                  </Label>
                                  <ProductSearchSelect
                                    products={products}
                                    value={draft.replacementId}
                                    onSelect={(p) => patchDraft(l.id, { replacementId: p.id })}
                                    optionLabel={(p) =>
                                      `${p.name} · ${hasPrice(p) ? currency(p.price) : "No price set"}`
                                    }
                                    isOptionDisabled={(p) => !hasPrice(p)}
                                    disabledHint="No price set — add one in Inventory to swap it in."
                                    placeholder="Search for a replacement product…"
                                  />
                                  <button
                                    type="button"
                                    onClick={() => patchDraft(l.id, { replacementId: null })}
                                    aria-pressed={!draft.replacementId}
                                    className={cn(
                                      "flex w-full items-center gap-2 rounded-xl border px-3 py-2 text-left text-sm transition-colors",
                                      !draft.replacementId
                                        ? "border-primary bg-primary/5 font-medium"
                                        : "border-border text-muted-foreground hover:border-primary/40",
                                    )}
                                  >
                                    <Undo2 className="size-4 shrink-0" />
                                    No replacement — refund only
                                  </button>
                                  {draft.replacementId && (
                                    <div className="flex items-center gap-3">
                                      <Label className="text-xs text-muted-foreground">
                                        Replacement qty
                                      </Label>
                                      <Input
                                        value={draft.replacementQty}
                                        onChange={(e) =>
                                          patchDraft(l.id, {
                                            replacementQty: Math.max(
                                              1,
                                              Number(e.target.value) || 1,
                                            ),
                                          })
                                        }
                                        className="h-9 w-20"
                                        aria-label={`Replacement quantity for ${l.name}`}
                                      />
                                      <span className="text-xs text-muted-foreground">
                                        value {currency(it?.replacementValue ?? 0)}
                                      </span>
                                    </div>
                                  )}
                                </div>

                                {it && (
                                  <p
                                    className={cn(
                                      "text-xs font-medium",
                                      it.difference < -0.01
                                        ? "text-amber-600 dark:text-amber-400"
                                        : "text-muted-foreground",
                                    )}
                                  >
                                    {it.resolution === "Top-up collected"
                                      ? `Top-up ${currency(it.difference)} to collect`
                                      : it.resolution === "Even exchange"
                                        ? "Even exchange — no money moves"
                                        : `${currency(Math.abs(it.difference))} back — ${it.resolution.toLowerCase()}`}
                                  </p>
                                )}
                              </div>
                            )}
                          </div>
                        </div>
                      </li>
                    );
                  })}
                </ul>
              </div>
            )}
          </div>

          {!allFullyReturned && items.length > 0 && (
            <div
              className={cn(
                "card-surface p-5",
                totalBack > 0 ? "border-amber-500/40" : "border-primary/40",
              )}
            >
              <h3 className="text-sm font-semibold">
                Settlement for {items.length} item{items.length === 1 ? "" : "s"}
              </h3>

              <div className="mt-4 space-y-2">
                <Label htmlFor="return-reason" className="text-xs text-muted-foreground">
                  Reason for the return (applies to every item)
                </Label>
                <Textarea
                  id="return-reason"
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="e.g. Wrong shade delivered to site"
                  rows={2}
                />
              </div>

              {totalTopUp > 0 && (
                <div className="mt-5 flex items-start gap-3">
                  <CheckCircle2 className="mt-0.5 size-5 shrink-0 text-primary" />
                  <div className="min-w-0 flex-1">
                    <p className="font-semibold">Top-up owed by customer</p>
                    <p className="text-sm text-muted-foreground">
                      Some replacements cost more than what came back. Collect the difference before
                      handing over the goods.
                    </p>
                    <p className="mt-2 text-2xl font-semibold">{currency(totalTopUp)}</p>
                    <div className="mt-3 max-w-[200px] space-y-1.5">
                      <Label className="text-xs text-muted-foreground">Collected via</Label>
                      <Select
                        value={topUpMethod}
                        onValueChange={(v) =>
                          setTopUpMethod(v as Exclude<PosMethod, "Store Credit">)
                        }
                      >
                        <SelectTrigger className="h-9">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {POS_METHODS.map((m) => (
                            <SelectItem key={m} value={m}>
                              {m}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    {POS_BANK_METHODS.includes(topUpMethod) && (
                      <div className="mt-3 max-w-[260px] space-y-1.5">
                        <Label className="text-xs text-muted-foreground">Into bank account</Label>
                        <BankAccountSelect
                          value={topUpBankAccountId || defaultBankAccountId}
                          onChange={setTopUpBankAccountId}
                          placeholder={`Which bank received this ${topUpMethod}?`}
                        />
                      </div>
                    )}
                  </div>
                </div>
              )}

              {totalBack > 0 && (
                <div className="mt-5 space-y-4">
                  <div className="flex items-start gap-3">
                    <ShieldAlert className="mt-0.5 size-5 shrink-0 text-amber-500" />
                    <div className="min-w-0">
                      <p className="font-semibold">Money going back to the customer</p>
                      <p className="mt-2 text-2xl font-semibold">
                        {currency(totalBack)} back to customer
                      </p>
                    </div>
                  </div>

                  {isManager ? (
                    <div className="grid gap-2 sm:grid-cols-2">
                      {(["Cash refund", "Store credit"] as Refund[]).map((choice) => (
                        <button
                          key={choice}
                          type="button"
                          onClick={() => setRefundChoice(choice)}
                          className={cn(
                            "rounded-xl border px-4 py-3 text-left text-sm transition-colors",
                            refundChoice === choice
                              ? "border-primary bg-primary/5"
                              : "border-border hover:border-primary/40",
                          )}
                        >
                          <span className="block font-medium">{choice}</span>
                          <span className="text-xs text-muted-foreground">
                            {choice === "Cash refund"
                              ? "Pay out from the till drawer"
                              : "Hold as credit on the customer account"}
                          </span>
                        </button>
                      ))}
                    </div>
                  ) : (
                    // Cash refund isn't just de-emphasized here — the option
                    // doesn't exist in this render at all for a non-Manager.
                    // create_sale_return() (per line, inside the batch) rejects
                    // it server-side too, so there's no path — this page, a
                    // different client, a raw API call — through which an
                    // Attendant can complete one.
                    <div className="rounded-xl border border-primary bg-primary/5 px-4 py-3 text-left text-sm">
                      <span className="block font-medium">Store credit</span>
                      <span className="text-xs text-muted-foreground">
                        Hold as credit on the customer account — completes immediately, no manager
                        needed. Cash refunds require a Manager to sign in and process them.
                      </span>
                    </div>
                  )}

                  {needsWalkInCustomer && (
                    <div className="space-y-2 rounded-xl border border-border p-3">
                      <Label className="text-xs text-muted-foreground">
                        This sale was Walk-in — select or add the customer to credit
                      </Label>
                      <div className="flex gap-2">
                        <Select
                          value={walkInCustomerId ?? ""}
                          onValueChange={(id) => setWalkInCustomerId(id)}
                        >
                          <SelectTrigger className="w-full">
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
                        <InlineAddCustomerDialog onAdd={onNewWalkInCustomer} />
                      </div>
                    </div>
                  )}
                </div>
              )}

              <Button className="mt-5 h-11 w-full" onClick={submit} disabled={!canSubmit}>
                {submitting
                  ? "Recording…"
                  : totalBack > 0
                    ? effectiveRefundChoice === "Cash refund"
                      ? `Complete cash refund (${currency(totalBack)})`
                      : `Complete store credit (${currency(totalBack)})`
                    : totalTopUp > 0
                      ? `Complete exchange (collect ${currency(totalTopUp)})`
                      : "Complete exchange"}
              </Button>
            </div>
          )}

          {sale.returns.length > 0 && (
            <div className="card-surface p-5">
              <h3 className="text-sm font-semibold">Return history for this sale</h3>
              <ReturnHistory returns={sale.returns} />
            </div>
          )}
        </section>
      )}
    </div>
  );
}

/** Groups the sale's returns by return_group_id so a multi-line return reads
 * as one customer event. Rows with no group id (single/legacy returns) each
 * render on their own. */
function ReturnHistory({ returns }: { returns: PosSale["returns"] }) {
  const groups = useMemo(() => {
    const byGroup = new Map<string, PosSale["returns"]>();
    for (const r of returns) {
      const key = r.returnGroupId ?? `solo:${r.id}`;
      const arr = byGroup.get(key) ?? [];
      arr.push(r);
      byGroup.set(key, arr);
    }
    return [...byGroup.values()];
  }, [returns]);

  return (
    <ul className="mt-3 space-y-3">
      {groups.map((rows) => {
        const first = rows[0];
        const net = rows.reduce((s, r) => s + r.difference, 0);
        return (
          <li
            key={first.returnGroupId ?? first.id}
            className="rounded-xl border border-border p-3 text-sm"
          >
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span className="font-medium">
                {rows.length > 1 ? `${rows.length} items` : first.id} · {first.date}
              </span>
              <Badge variant="outline">{first.resolution}</Badge>
            </div>
            <ul className="mt-1 space-y-0.5 text-muted-foreground">
              {rows.map((r) => (
                <li key={r.id}>
                  {r.returned.quantity} × {r.returned.name}
                  {r.replacement
                    ? ` → ${r.replacement.quantity} × ${r.replacement.name}`
                    : " → refund"}
                  {" · "}
                  {currency(Math.abs(r.difference))} {r.difference >= 0 ? "top-up" : "back"}
                </li>
              ))}
            </ul>
            {rows.length > 1 && (
              <p className="mt-1 text-xs text-muted-foreground">
                Net {currency(Math.abs(net))} {net >= 0 ? "collected" : "returned"} · {first.reason}
              </p>
            )}
            {rows.length === 1 && (
              <p className="mt-1 text-xs text-muted-foreground">{first.reason}</p>
            )}
          </li>
        );
      })}
    </ul>
  );
}
