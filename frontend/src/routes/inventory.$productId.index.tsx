import { useState } from "react";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { ArrowLeft, MapPin, Pencil, Trash2, TrendingUp } from "lucide-react";
import { toast } from "sonner";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { ProductThumb } from "@/components/inventory/product-thumb";
import { StockBadge } from "@/components/inventory/stock-badge";
import { StockAdjustDialog } from "@/components/inventory/stock-adjust-dialog";
import { CostMissingBadge } from "@/components/inventory/cost-missing-badge";
import { PriceMissingBadge } from "@/components/inventory/price-missing-badge";
import { SyncStatus } from "@/components/sync-status";
import { useAuth } from "@/data/auth-store";
import {
  deleteProduct,
  effectiveThreshold,
  hasCost,
  hasPrice,
  reloadInventory,
  setProductThreshold,
  stockStatus,
  useInventory,
} from "@/data/inventory-store";
import { currency, currencyPrecise } from "@/data/dashboard";
import { cn, getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/inventory/$productId/")({
  head: () => ({
    meta: [
      { title: "Product details — TCS Inventory" },
      {
        name: "description",
        content:
          "Product pricing, stock on hand, low-stock threshold and full inventory movement history.",
      },
      { property: "og:title", content: "Product details — TCS Inventory" },
      {
        property: "og:description",
        content:
          "Pricing, stock on hand, manual corrections and inventory history for a TCS product.",
      },
    ],
  }),
  component: ProductDetail,
});

const dateFmt = (iso: string) =>
  new Date(iso).toLocaleDateString("en-GH", { day: "2-digit", month: "short", year: "numeric" });

const SINGULAR: Record<string, string> = {
  Litres: "litre",
  Boxes: "box",
  Pieces: "piece",
  Rolls: "roll",
  Bags: "bag",
  Metres: "metre",
  Sheets: "sheet",
  Buckets: "bucket",
};

const singular = (unit: string) => SINGULAR[unit] ?? unit.toLowerCase();

function ProductDetail() {
  const { productId } = Route.useParams();
  const { products, defaultThreshold, lastSyncedAt } = useInventory();
  const product = products.find((p) => p.id === productId);
  const { staff: currentStaff } = useAuth();
  const isManager = currentStaff?.role === "Manager";

  if (!product) {
    return (
      <div className="card-surface p-10 text-center">
        <p className="text-sm font-medium">This product no longer exists</p>
        <Link to="/inventory" className="mt-3 inline-block text-sm text-primary hover:underline">
          Back to inventory
        </Link>
      </div>
    );
  }

  const status = stockStatus(product, defaultThreshold);
  const margin = hasCost(product) && hasPrice(product) ? product.price - product.cost : null;
  const marginPct =
    margin !== null && hasPrice(product) && product.price > 0
      ? Math.round((margin / product.price) * 100)
      : 0;

  return (
    <>
      <Link
        to="/inventory"
        className="mb-4 inline-flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="size-4" /> Back to inventory
      </Link>

      <SyncStatus lastSyncedAt={lastSyncedAt} onRefresh={reloadInventory} className="mb-3" />

      <div className="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div className="flex items-start gap-4">
          <ProductThumb
            category={product.category}
            className="size-14 rounded-2xl"
            iconClassName="size-6"
          />
          <div>
            <h1 className="text-2xl font-semibold tracking-tight md:text-3xl">{product.name}</h1>
            <p className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-muted-foreground">
              <span>{product.sku}</span>
              <span>·</span>
              <span>{product.category}</span>
              <span>·</span>
              <span>
                {product.unit} ({product.size})
              </span>
            </p>
            <p className="mt-2 inline-flex items-center gap-1.5 rounded-lg bg-muted px-2 py-1 text-xs text-muted-foreground">
              <MapPin className="size-3.5" /> {product.branch}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {isManager && (
            <Button variant="outline" className="gap-2" asChild>
              <Link to="/inventory/$productId/edit" params={{ productId: product.id }}>
                <Pencil className="size-4" /> Edit
              </Link>
            </Button>
          )}
          {isManager && <DeleteProductDialog productId={product.id} productName={product.name} />}
          <StockAdjustDialog product={product} />
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="card-surface p-5 lg:col-span-2">
          <h2 className="text-base font-semibold">Description</h2>
          <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
            {product.description}
          </p>

          <div className="mt-5 grid gap-4 sm:grid-cols-3">
            <Metric
              label="Cost price"
              value={hasCost(product) ? currencyPrecise(product.cost) : <CostMissingBadge />}
              hint={hasCost(product) ? `per ${singular(product.unit)}` : "Not yet recorded"}
            />
            <Metric
              label="Selling price"
              value={hasPrice(product) ? currencyPrecise(product.price) : <PriceMissingBadge />}
              hint={
                hasPrice(product)
                  ? `per ${singular(product.unit)}`
                  : "Can't be sold or invoiced until set"
              }
            />
            <Metric
              label="Margin"
              value={margin !== null ? currency(margin) : "—"}
              hint={
                margin !== null
                  ? `${marginPct}% of selling price`
                  : "Needs a cost price to calculate"
              }
              icon={<TrendingUp className="size-4 text-primary" />}
            />
          </div>
        </div>

        <div className="card-surface p-5">
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="text-sm text-muted-foreground">Quantity in stock</p>
              <p
                className={cn(
                  "mt-2 text-3xl font-semibold tracking-tight",
                  status === "Out of stock" && "text-destructive",
                  status === "Low stock" && "text-amber-600 dark:text-amber-400",
                )}
              >
                {product.stock.toLocaleString("en-GH")}
                <span className="ml-1 text-base font-medium text-muted-foreground">
                  {product.unit.toLowerCase()}
                </span>
              </p>
            </div>
            <StockBadge status={status} />
          </div>
          <p className="mt-2 text-xs text-muted-foreground">
            Low-stock threshold: {effectiveThreshold(product, defaultThreshold)}{" "}
            {product.threshold === null ? "(global default)" : "(product override)"}
          </p>

          <ThresholdOverride
            productId={product.id}
            threshold={product.threshold}
            defaultThreshold={defaultThreshold}
          />
        </div>
      </div>

      <div className="card-surface mt-6 overflow-hidden">
        <div className="border-b p-5">
          <h2 className="text-base font-semibold">Inventory history</h2>
          <p className="text-sm text-muted-foreground">
            Sales, purchases, returns and manual corrections
          </p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
              <tr>
                <th className="px-5 py-3 font-medium">Date</th>
                <th className="px-5 py-3 font-medium">Type</th>
                <th className="px-5 py-3 font-medium">Reason / reference</th>
                <th className="px-5 py-3 font-medium">By</th>
                <th className="px-5 py-3 text-right font-medium">Change</th>
                <th className="px-5 py-3 text-right font-medium">Balance</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {product.history.map((m) => (
                <tr key={m.id} className="hover:bg-muted/40">
                  <td className="px-5 py-3 text-muted-foreground">{dateFmt(m.date)}</td>
                  <td className="px-5 py-3">
                    <span className="inline-flex rounded-lg bg-muted px-2 py-0.5 text-xs font-medium">
                      {m.type}
                    </span>
                  </td>
                  <td className="px-5 py-3">{m.reason}</td>
                  <td className="px-5 py-3 text-muted-foreground">{m.user}</td>
                  <td
                    className={cn(
                      "px-5 py-3 text-right font-medium tabular-nums",
                      m.change < 0 ? "text-destructive" : "text-primary",
                    )}
                  >
                    {m.change > 0 ? "+" : ""}
                    {m.change.toLocaleString("en-GH")}
                  </td>
                  <td className="px-5 py-3 text-right tabular-nums text-muted-foreground">
                    {m.balance.toLocaleString("en-GH")}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}

function DeleteProductDialog({
  productId,
  productName,
}: {
  productId: string;
  productName: string;
}) {
  const navigate = useNavigate();
  const [deleting, setDeleting] = useState(false);

  async function confirmDelete() {
    setDeleting(true);
    try {
      await deleteProduct(productId);
      toast.success(`${productName} deleted`);
      navigate({ to: "/inventory" });
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not delete the product."));
    } finally {
      setDeleting(false);
    }
  }

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="outline" className="gap-2 text-destructive hover:text-destructive">
          <Trash2 className="size-4" /> Delete
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Delete “{productName}”?</AlertDialogTitle>
          <AlertDialogDescription>
            This permanently removes the product. It only succeeds if the product has no stock
            movements, sale lines, invoice lines, purchase order lines, or return/exchange records —
            anything with real transaction history is blocked from deletion, with the specific
            reason shown. This can't be undone.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={deleting}>Cancel</AlertDialogCancel>
          <AlertDialogAction
            className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            disabled={deleting}
            onClick={(e) => {
              e.preventDefault();
              void confirmDelete();
            }}
          >
            {deleting ? "Deleting…" : "Delete product"}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

function ThresholdOverride({
  productId,
  threshold,
  defaultThreshold,
}: {
  productId: string;
  threshold: number | null;
  defaultThreshold: number;
}) {
  const [value, setValue] = useState(String(threshold ?? defaultThreshold));
  const [saving, setSaving] = useState(false);

  return (
    <div className="mt-5 rounded-2xl border bg-muted/40 p-4">
      <div className="flex items-center justify-between gap-3">
        <Label htmlFor="override-toggle" className="text-sm font-medium">
          Override global threshold
        </Label>
        <Switch
          id="override-toggle"
          checked={threshold !== null}
          disabled={saving}
          onCheckedChange={async (checked) => {
            setSaving(true);
            try {
              if (checked) {
                await setProductThreshold(productId, Number(value) || defaultThreshold);
              } else {
                await setProductThreshold(productId, null);
                toast.success("Now following the global default threshold");
              }
            } catch (err) {
              toast.error(err instanceof Error ? err.message : "Could not update the threshold.");
            } finally {
              setSaving(false);
            }
          }}
        />
      </div>
      {threshold !== null && (
        <div className="mt-3 flex items-end gap-2">
          <div className="flex-1 space-y-1.5">
            <Label htmlFor="override-value" className="text-xs text-muted-foreground">
              Alert when stock is at or below
            </Label>
            <Input
              id="override-value"
              type="number"
              min={0}
              step={1}
              value={value}
              onChange={(e) => setValue(e.target.value)}
              className="h-9"
            />
          </div>
          <Button
            size="sm"
            variant="secondary"
            disabled={saving}
            onClick={async () => {
              const n = Number(value);
              if (!Number.isInteger(n) || n < 0 || n > 100000) {
                toast.error("Enter a whole number between 0 and 100,000");
                return;
              }
              setSaving(true);
              try {
                await setProductThreshold(productId, n);
                toast.success(`Threshold set to ${n}`);
              } catch (err) {
                toast.error(err instanceof Error ? err.message : "Could not update the threshold.");
              } finally {
                setSaving(false);
              }
            }}
          >
            Save
          </Button>
        </div>
      )}
    </div>
  );
}

function Metric({
  label,
  value,
  hint,
  icon,
}: {
  label: string;
  value: React.ReactNode;
  hint: string;
  icon?: React.ReactNode;
}) {
  return (
    <div className="rounded-2xl border bg-muted/40 p-4">
      <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
        {icon}
        {label}
      </p>
      <p className="mt-1.5 text-lg font-semibold tracking-tight tabular-nums">{value}</p>
      <p className="text-xs text-muted-foreground">{hint}</p>
    </div>
  );
}
