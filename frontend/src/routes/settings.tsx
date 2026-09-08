import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import {
  Bell,
  Building2,
  Clock3,
  FileText,
  ImageUp,
  Lock,
  Package,
  Palette,
  Percent,
  ReceiptText,
  Send,
  ShieldAlert,
  Store,
  Trash2,
  UserPlus,
  Users,
  type LucideIcon,
  Wallet,
} from "lucide-react";
import { toast } from "sonner";

import { PageHeader } from "@/components/page-header";
import { PrintableInvoice } from "@/components/print/printable-invoice";
import { PrintableReceipt } from "@/components/print/printable-receipt";
import { ListEditor } from "@/components/settings/list-editor";
import { useTheme } from "@/components/theme-provider";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
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
import { useAuth, type StaffRole } from "@/data/auth-store";
import { useCurrentBranch } from "@/data/branch-store";
import { setExpenseCategories, useExpenses } from "@/data/expenses-store";
import { setDefaultThreshold, useInventory } from "@/data/inventory-store";
import {
  updateNotificationSettings,
  useNotificationSettings,
} from "@/data/notification-settings-store";
import { usePosSales } from "@/data/pos-store";
import { useSales } from "@/data/sales-store";
import {
  updateSessionTimeoutMinutes,
  useSessionTimeoutMinutes,
} from "@/data/session-timeout-store";
import {
  inviteStaff,
  resendInvite,
  setStaffActive,
  setStaffRole,
  useStaff,
} from "@/data/staff-store";
import { updateWhtRate, useWhtRate } from "@/data/wht-settings-store";
import {
  DATE_FORMATS,
  DEFAULT_ACCENT,
  INVOICE_PAPERS,
  PAPER_WIDTH_MM,
  RECEIPT_PAPERS,
  TIMEZONES,
  updateAppearance,
  updateCompany,
  updateInventorySettings,
  updateLocalisation,
  updateSalesSettings,
  updateSettings,
  updateTax,
  useDocumentSettings,
  type DateFormat,
  type DefaultVatMode,
  type InvoicePaper,
  type ReceiptPaper,
} from "@/data/settings-store";
import { cn, getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/settings")({
  head: () => ({
    meta: [
      { title: "Settings — TCS" },
      {
        name: "description",
        content:
          "Company profile, tax and VAT defaults, inventory and sales defaults, localisation, appearance and document settings for TCS.",
      },
      { property: "og:title", content: "Settings — TCS" },
      {
        property: "og:description",
        content: "Control company details, VAT, units, currency, theme and printed documents.",
      },
    ],
  }),
  component: SettingsPage,
});

type SectionId =
  | "company"
  | "documents"
  | "tax"
  | "inventory"
  | "expenses"
  | "sales"
  | "localisation"
  | "appearance"
  | "notifications"
  | "security"
  | "users"
  | "roles"
  | "branches";

const SECTIONS: { id: SectionId; label: string; icon: LucideIcon; group: string }[] = [
  { id: "company", label: "Company profile", icon: Building2, group: "Business" },
  { id: "documents", label: "Documents", icon: FileText, group: "Business" },
  { id: "tax", label: "Tax & VAT", icon: Percent, group: "Business" },
  { id: "inventory", label: "Inventory defaults", icon: Package, group: "Operations" },
  { id: "expenses", label: "Expense categories", icon: Wallet, group: "Operations" },
  { id: "sales", label: "Sales defaults", icon: ReceiptText, group: "Operations" },
  { id: "localisation", label: "Localisation", icon: Clock3, group: "Operations" },
  { id: "appearance", label: "Appearance", icon: Palette, group: "Preferences" },
  { id: "notifications", label: "Notifications", icon: Bell, group: "Preferences" },
  { id: "security", label: "Security", icon: ShieldAlert, group: "Security" },
  { id: "users", label: "Staff", icon: Users, group: "Team" },
  { id: "roles", label: "Roles & permissions", icon: Lock, group: "Coming soon" },
  { id: "branches", label: "Branches", icon: Store, group: "Coming soon" },
];

function SettingsPage() {
  const [section, setSection] = useState<SectionId>("company");
  const { name: branchName } = useCurrentBranch();
  const groups = [...new Set(SECTIONS.map((s) => s.group))];

  return (
    <>
      <PageHeader
        title="Settings"
        description="Business profile, defaults and preferences across TCS."
      />

      <div className="grid gap-6 lg:grid-cols-[220px_minmax(0,1fr)]">
        <nav aria-label="Settings sections" className="lg:sticky lg:top-24 lg:self-start">
          <div className="card-surface space-y-4 p-3">
            {groups.map((group) => (
              <div key={group}>
                <p className="px-3 pb-1.5 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  {group}
                </p>
                <div className="space-y-0.5">
                  {SECTIONS.filter((s) => s.group === group).map((s) => (
                    <button
                      key={s.id}
                      type="button"
                      onClick={() => setSection(s.id)}
                      aria-current={section === s.id ? "page" : undefined}
                      className={cn(
                        "flex w-full items-center gap-2.5 rounded-xl px-3 py-2 text-left text-sm font-medium transition-colors",
                        section === s.id
                          ? "bg-primary/10 text-foreground"
                          : "text-muted-foreground hover:bg-muted/60 hover:text-foreground",
                      )}
                    >
                      <s.icon className="size-4 shrink-0" />
                      <span className="truncate">{s.label}</span>
                    </button>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </nav>

        <div className="min-w-0">
          {section === "company" && <CompanySection />}
          {section === "documents" && <DocumentsSection />}
          {section === "tax" && <TaxSection />}
          {section === "inventory" && <InventorySection />}
          {section === "expenses" && <ExpensesSection />}
          {section === "sales" && <SalesSection />}
          {section === "localisation" && <LocalisationSection />}
          {section === "appearance" && <AppearanceSection />}
          {section === "notifications" && <NotificationsSection />}
          {section === "security" && <SecuritySection />}
          {section === "users" && <StaffSection />}
          {section === "roles" && (
            <ComingSoon
              title="Roles & permissions"
              icon={Lock}
              note="Attendant, Manager and Accountant/Auditor roles exist and are enforced by database policy (see Staff) — a screen for fine-tuning individual permissions per role isn't built yet."
            />
          )}
          {section === "branches" && (
            <ComingSoon
              title="Branches"
              icon={Store}
              note={`TCS runs from ${branchName ?? "…"} only, so there is nothing to switch between yet.`}
            />
          )}
        </div>
      </div>
    </>
  );
}

/* ---------------------------------------------------------------- sections */

function CompanySection() {
  const settings = useDocumentSettings();
  const fileRef = useRef<HTMLInputElement>(null);

  function onLogoChange(file?: File | null) {
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      toast.error("Please choose an image file");
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      updateSettings({ logoDataUrl: String(reader.result) });
      toast.success("Logo updated");
    };
    reader.readAsDataURL(file);
  }

  return (
    <Card title="Company profile" description="Used across the app and on every printed document.">
      <div className="grid gap-5 sm:grid-cols-2">
        <Field
          label="Business name"
          value={settings.company.name}
          onChange={(name) => updateCompany({ name })}
        />
        <Field
          label="Trading name"
          value={settings.company.tradingName}
          onChange={(tradingName) => updateCompany({ tradingName })}
        />
        <Field
          label="Physical address"
          value={settings.company.address}
          onChange={(address) => updateCompany({ address })}
        />
        <Field
          label="Postal address"
          value={settings.company.postalAddress}
          onChange={(postalAddress) => updateCompany({ postalAddress })}
        />
        <Field
          label="Phone"
          value={settings.company.phone}
          onChange={(phone) => updateCompany({ phone })}
        />
        <Field
          label="Email"
          value={settings.company.email}
          onChange={(email) => updateCompany({ email })}
        />
        <Field
          label="Website"
          value={settings.company.website}
          onChange={(website) => updateCompany({ website })}
        />
        <Field
          label="VAT registration number"
          value={settings.company.vatNumber}
          onChange={(vatNumber) => updateCompany({ vatNumber })}
        />
        <div className="sm:col-span-2">
          <Field
            label="Business registration number"
            value={settings.company.registrationNumber}
            onChange={(registrationNumber) => updateCompany({ registrationNumber })}
          />
        </div>
      </div>

      <div className="mt-6 flex flex-wrap items-center gap-4 rounded-2xl border p-4">
        <div className="flex size-20 shrink-0 items-center justify-center overflow-hidden rounded-xl border bg-muted/40">
          {settings.logoDataUrl ? (
            <img
              src={settings.logoDataUrl}
              alt="Company logo preview"
              className="size-full object-contain"
            />
          ) : (
            <ImageUp className="size-6 text-muted-foreground" />
          )}
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium">Logo</p>
          <p className="text-sm text-muted-foreground">
            PNG or JPG. Shown here and on invoices and receipts.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            className="hidden"
            onChange={(e) => onLogoChange(e.target.files?.[0])}
          />
          <Button variant="outline" onClick={() => fileRef.current?.click()}>
            Upload logo
          </Button>
          {settings.logoDataUrl && (
            <Button
              variant="ghost"
              size="icon"
              aria-label="Remove logo"
              onClick={() => updateSettings({ logoDataUrl: null })}
            >
              <Trash2 className="size-4" />
            </Button>
          )}
        </div>
      </div>
    </Card>
  );
}

function DocumentsSection() {
  const settings = useDocumentSettings();
  const { invoices, customers } = useSales();
  const { sales } = usePosSales();
  const fileRef = useRef<HTMLInputElement>(null);

  const sampleInvoice = invoices[0];
  const sampleCustomer = sampleInvoice
    ? (customers.find((c) => c.id === sampleInvoice.customerId) ?? null)
    : null;
  const sampleSale = sales[0];

  function onLogoChange(file?: File | null) {
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      toast.error("Please choose an image file");
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      updateSettings({ logoDataUrl: String(reader.result) });
      toast.success("Logo updated");
    };
    reader.readAsDataURL(file);
  }

  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,380px)]">
      <div className="space-y-6">
        <section className="card-surface p-6">
          <h2 className="text-sm font-semibold">Documents</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Paper sizes used when printing receipts and invoices.
          </p>
          <div className="mt-5 grid gap-5 sm:grid-cols-2">
            <div className="space-y-2">
              <Label>Receipt paper size</Label>
              <Select
                value={settings.receiptPaper}
                onValueChange={(v) => updateSettings({ receiptPaper: v as ReceiptPaper })}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {RECEIPT_PAPERS.map((p) => (
                    <SelectItem key={p} value={p}>
                      {p === "A4" ? "A4 (210mm)" : `${p} thermal`}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Invoice paper size</Label>
              <Select
                value={settings.invoicePaper}
                onValueChange={(v) => updateSettings({ invoicePaper: v as InvoicePaper })}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {INVOICE_PAPERS.map((p) => (
                    <SelectItem key={p} value={p}>
                      {p} ({PAPER_WIDTH_MM[p]}mm wide)
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
        </section>

        <section className="card-surface p-6">
          <h2 className="text-sm font-semibold">Company details</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Shown at the top of every printed invoice and receipt.
          </p>
          <div className="mt-5 grid gap-5 sm:grid-cols-2">
            <Field
              label="Business name"
              value={settings.company.name}
              onChange={(name) => updateCompany({ name })}
            />
            <Field
              label="Phone"
              value={settings.company.phone}
              onChange={(phone) => updateCompany({ phone })}
            />
            <Field
              label="Email"
              value={settings.company.email}
              onChange={(email) => updateCompany({ email })}
            />
            <Field
              label="VAT number"
              value={settings.company.vatNumber}
              onChange={(vatNumber) => updateCompany({ vatNumber })}
            />
            <div className="sm:col-span-2">
              <Field
                label="Address"
                value={settings.company.address}
                onChange={(address) => updateCompany({ address })}
              />
            </div>
          </div>

          <div className="mt-6 flex flex-wrap items-center justify-between gap-4 rounded-2xl border p-4">
            <div>
              <p className="text-sm font-medium">Show VAT number on documents</p>
              <p className="text-sm text-muted-foreground">
                Hide it if you are not printing VAT-registered documents.
              </p>
            </div>
            <Switch
              checked={settings.showVatNumber}
              onCheckedChange={(showVatNumber) => updateSettings({ showVatNumber })}
            />
          </div>

          <div className="mt-4 flex flex-wrap items-center gap-4 rounded-2xl border p-4">
            <div className="flex size-16 shrink-0 items-center justify-center overflow-hidden rounded-xl border bg-muted/40">
              {settings.logoDataUrl ? (
                <img
                  src={settings.logoDataUrl}
                  alt="Company logo"
                  className="size-full object-contain"
                />
              ) : (
                <ImageUp className="size-6 text-muted-foreground" />
              )}
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-sm font-medium">Logo</p>
              <p className="text-sm text-muted-foreground">
                PNG or JPG. Appears on invoices and receipts.
              </p>
            </div>
            <div className="flex items-center gap-2">
              <input
                ref={fileRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => onLogoChange(e.target.files?.[0])}
              />
              <Button variant="outline" onClick={() => fileRef.current?.click()}>
                Upload logo
              </Button>
              {settings.logoDataUrl && (
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label="Remove logo"
                  onClick={() => updateSettings({ logoDataUrl: null })}
                >
                  <Trash2 className="size-4" />
                </Button>
              )}
            </div>
          </div>
        </section>
      </div>

      <aside className="space-y-6">
        <section className="card-surface p-5">
          <h2 className="text-sm font-semibold">Receipt preview</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            {settings.receiptPaper === "A4" ? "A4 sheet" : `${settings.receiptPaper} thermal roll`}
          </p>
          <div className="mt-4 overflow-hidden rounded-2xl border bg-white p-3">
            <div className="origin-top-left" style={{ transform: "scale(0.95)" }}>
              {sampleSale && <PrintableReceipt sale={sampleSale} settings={settings} />}
            </div>
          </div>
        </section>

        <section className="card-surface p-5">
          <h2 className="text-sm font-semibold">Invoice preview</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            {settings.invoicePaper} · {PAPER_WIDTH_MM[settings.invoicePaper]}mm wide
          </p>
          <div className="mt-4 overflow-hidden rounded-2xl border bg-white p-3">
            <div
              className="origin-top-left"
              style={{
                transform: "scale(0.46)",
                width: `${100 / 0.46}%`,
                height: `${PAPER_WIDTH_MM[settings.invoicePaper] * 1.6}px`,
              }}
            >
              {sampleInvoice && (
                <PrintableInvoice
                  invoice={sampleInvoice}
                  customer={sampleCustomer}
                  settings={settings}
                />
              )}
            </div>
          </div>
        </section>
      </aside>
    </div>
  );
}

function TaxSection() {
  const { tax } = useDocumentSettings();
  const { whtRate, loading: whtLoading } = useWhtRate();
  const { staff } = useAuth();
  const isManager = staff?.role === "Manager";
  const [whtInput, setWhtInput] = useState<string | null>(null);
  const [whtSaving, setWhtSaving] = useState(false);

  const displayedWhtRate = whtInput ?? String(whtRate ?? "");

  async function saveWhtRate(raw: string) {
    const value = Number(raw);
    if (!Number.isFinite(value) || value < 0) {
      toast.error("Enter a WHT rate of 0 or more.");
      setWhtInput(null);
      return;
    }
    setWhtSaving(true);
    try {
      await updateWhtRate(value);
      setWhtInput(null);
    } catch (err) {
      toast.error("Could not update the WHT rate", {
        description: getErrorMessage(err, "Something went wrong."),
      });
    } finally {
      setWhtSaving(false);
    }
  }

  return (
    <div className="space-y-6">
      <Card title="Tax & VAT" description="Defaults applied to new invoices and POS sales.">
        <div className="grid gap-5 sm:grid-cols-2">
          <div className="space-y-2">
            <Label>Default VAT rate (%)</Label>
            <Input
              type="number"
              min={0}
              max={100}
              step="0.5"
              value={tax.vatRate}
              onChange={(e) => updateTax({ vatRate: Number(e.target.value) || 0 })}
            />
          </div>
          <div className="space-y-2">
            <Label>VAT applied by default</Label>
            <Select
              value={tax.defaultVatMode}
              onValueChange={(v) => updateTax({ defaultVatMode: v as DefaultVatMode })}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="per-item">Per item</SelectItem>
                <SelectItem value="all">Whole sale</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2 sm:col-span-2">
            <Label>VAT description on documents</Label>
            <Textarea
              rows={3}
              maxLength={200}
              value={tax.vatNote}
              onChange={(e) => updateTax({ vatNote: e.target.value })}
            />
            <p className="text-sm text-muted-foreground">
              Printed under the totals on invoices and receipts.
            </p>
          </div>
        </div>
      </Card>

      <Card
        title="Withholding Tax (WHT)"
        description="Applied when the WHT toggle is used on a new invoice — Attendant and Manager can both use the toggle, only a Manager can change the rate here."
      >
        <div className="max-w-xs space-y-2">
          <Label htmlFor="wht-rate">WHT rate (%)</Label>
          <Input
            id="wht-rate"
            type="number"
            min={0}
            step="0.1"
            value={displayedWhtRate}
            disabled={!isManager || whtLoading || whtSaving}
            onChange={(e) => setWhtInput(e.target.value)}
            onBlur={(e) => {
              if (whtInput !== null && e.target.value !== String(whtRate ?? "")) {
                saveWhtRate(e.target.value);
              } else {
                setWhtInput(null);
              }
            }}
          />
          <p className="text-xs text-muted-foreground">
            Calculated against the taxable subtotal (post-discount, pre-VAT). This rate and
            calculation base are this build's best-effort default — confirm both with an accountant
            before using WHT against real transactions.
          </p>
        </div>
      </Card>
    </div>
  );
}

function InventorySection() {
  const { defaultThreshold } = useInventory();
  const { inventory } = useDocumentSettings();

  return (
    <div className="space-y-6">
      <Card
        title="Stock alerts"
        description="Applies to every product without its own threshold override."
      >
        <div className="max-w-xs space-y-2">
          <Label>Global low stock threshold</Label>
          <Input
            type="number"
            min={0}
            value={defaultThreshold}
            onChange={(e) => setDefaultThreshold(Math.max(0, Number(e.target.value) || 0))}
          />
        </div>
      </Card>

      <Card title="Product lists" description="Options offered when adding or importing products.">
        <div className="grid gap-8 lg:grid-cols-2">
          <ListEditor
            label="Units of measure"
            description="Shown in the unit selector on the product form."
            items={inventory.units}
            placeholder="e.g. Cartons"
            onChange={(units) => updateInventorySettings({ units })}
          />
          <ListEditor
            label="Categories"
            description="Used for filtering across Inventory and POS."
            items={inventory.categories}
            placeholder="e.g. Plumbing"
            onChange={(categories) => updateInventorySettings({ categories })}
          />
        </div>
      </Card>
    </div>
  );
}

function ExpensesSection() {
  const { categories } = useExpenses();

  return (
    <Card
      title="Expense categories"
      description="Options offered when recording an expense, and used for filtering the Expenses list."
    >
      <div className="max-w-xl">
        <ListEditor
          label="Categories"
          description="Removing a category leaves existing expenses untouched."
          items={categories}
          placeholder="e.g. Security"
          onChange={(next) => {
            setExpenseCategories(next).catch((err) => {
              toast.error("Could not update expense categories", {
                description: err instanceof Error ? err.message : String(err),
              });
            });
          }}
        />
      </div>
    </Card>
  );
}

function SalesSection() {
  const { sales } = useDocumentSettings();

  return (
    <Card title="Sales defaults" description="Numbering and defaults for invoices and POS sales.">
      <div className="grid gap-5 sm:grid-cols-2">
        <div className="space-y-2">
          <Label>Default payment terms (days)</Label>
          <Input
            type="number"
            min={0}
            max={365}
            value={sales.paymentTermsDays}
            onChange={(e) =>
              updateSalesSettings({ paymentTermsDays: Math.max(0, Number(e.target.value) || 0) })
            }
          />
        </div>
        <div />
        <div className="space-y-2">
          <Label>Invoice number format</Label>
          <Input
            value={sales.invoicePrefix}
            maxLength={10}
            onChange={(e) => updateSalesSettings({ invoicePrefix: e.target.value })}
          />
        </div>
        <div className="space-y-2">
          <Label>Next invoice number</Label>
          <Input
            type="number"
            min={1}
            value={sales.nextInvoiceNumber}
            onChange={(e) =>
              updateSalesSettings({ nextInvoiceNumber: Math.max(1, Number(e.target.value) || 1) })
            }
          />
          <p className="text-sm text-muted-foreground">
            Next invoice: {sales.invoicePrefix}
            {sales.nextInvoiceNumber}
          </p>
        </div>
        <div className="space-y-2">
          <Label>Receipt number format</Label>
          <Input
            value={sales.receiptPrefix}
            maxLength={10}
            onChange={(e) => updateSalesSettings({ receiptPrefix: e.target.value })}
          />
        </div>
        <div className="space-y-2">
          <Label>Next receipt number</Label>
          <Input
            type="number"
            min={1}
            value={sales.nextReceiptNumber}
            onChange={(e) =>
              updateSalesSettings({ nextReceiptNumber: Math.max(1, Number(e.target.value) || 1) })
            }
          />
          <p className="text-sm text-muted-foreground">
            Next receipt: {sales.receiptPrefix}
            {sales.nextReceiptNumber}
          </p>
        </div>
      </div>

      <ToggleRow
        className="mt-6"
        title="Require a customer on POS sales"
        description="When off, cashiers can complete a sale as a walk-in customer."
        checked={sales.requireCustomerOnPos}
        onChange={(requireCustomerOnPos) => updateSalesSettings({ requireCustomerOnPos })}
      />
    </Card>
  );
}

function LocalisationSection() {
  const { localisation } = useDocumentSettings();

  return (
    <Card title="Localisation" description="Currency, dates and timezone used across TCS.">
      <div className="grid gap-5 sm:grid-cols-2">
        <div className="space-y-2">
          <Label>Currency</Label>
          <Input
            value={localisation.currencyCode}
            maxLength={5}
            onChange={(e) => updateLocalisation({ currencyCode: e.target.value.toUpperCase() })}
          />
        </div>
        <div className="space-y-2">
          <Label>Currency symbol</Label>
          <Input
            value={localisation.currencySymbol}
            maxLength={5}
            onChange={(e) => updateLocalisation({ currencySymbol: e.target.value })}
          />
        </div>
        <div className="space-y-2">
          <Label>Decimal places</Label>
          <Select
            value={String(localisation.decimals)}
            onValueChange={(v) => updateLocalisation({ decimals: Number(v) })}
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {[0, 2, 3].map((d) => (
                <SelectItem key={d} value={String(d)}>
                  {d}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-2">
          <Label>Date format</Label>
          <Select
            value={localisation.dateFormat}
            onValueChange={(v) => updateLocalisation({ dateFormat: v as DateFormat })}
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {DATE_FORMATS.map((f) => (
                <SelectItem key={f} value={f}>
                  {f}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-2 sm:col-span-2">
          <Label>Timezone</Label>
          <Select
            value={localisation.timezone}
            onValueChange={(timezone) => updateLocalisation({ timezone })}
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {TIMEZONES.map((tz) => (
                <SelectItem key={tz} value={tz}>
                  {tz}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      <p className="mt-5 rounded-2xl border bg-muted/30 p-4 text-sm text-muted-foreground">
        Amounts display as{" "}
        <span className="font-medium text-foreground">
          {localisation.currencySymbol}
          {(12345.6789).toFixed(localisation.decimals)}
        </span>{" "}
        across the dashboard, inventory, invoices and POS.
      </p>
    </Card>
  );
}

function AppearanceSection() {
  const { appearance } = useDocumentSettings();
  const { theme, toggleTheme } = useTheme();

  return (
    <Card title="Appearance" description="Theme and accent colour for the whole app.">
      <ToggleRow
        title="Dark theme"
        description="Switch between the light and dark interface."
        checked={theme === "dark"}
        onChange={() => toggleTheme()}
      />

      <div className="mt-4 flex flex-wrap items-center justify-between gap-4 rounded-2xl border p-4">
        <div className="min-w-0">
          <p className="text-sm font-medium">Accent colour</p>
          <p className="text-sm text-muted-foreground">
            Used for primary buttons, charts and highlights.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <input
            type="color"
            aria-label="Accent colour"
            value={appearance.accent}
            onChange={(e) => updateAppearance({ accent: e.target.value })}
            className="size-10 cursor-pointer rounded-lg border bg-transparent p-1"
          />
          <Input
            value={appearance.accent}
            maxLength={7}
            className="w-28 font-mono uppercase"
            onChange={(e) => updateAppearance({ accent: e.target.value })}
          />
          <Button variant="outline" onClick={() => updateAppearance({ accent: DEFAULT_ACCENT })}>
            Reset
          </Button>
        </div>
      </div>
    </Card>
  );
}

function NotificationsSection() {
  const { settings, loading } = useNotificationSettings();
  const { staff } = useAuth();
  const isManager = staff?.role === "Manager";

  function onChange(patch: Parameters<typeof updateNotificationSettings>[0]) {
    updateNotificationSettings(patch).catch((err) => {
      toast.error("Could not update notification settings", {
        description: getErrorMessage(err, "Something went wrong."),
      });
    });
  }

  return (
    <Card
      title="Notifications"
      description={
        isManager
          ? "Alerts delivered in-app via the bell icon, to every active Manager."
          : "Alerts delivered in-app via the bell icon, to every active Manager. Only a Manager can change these."
      }
    >
      <div className="space-y-4">
        <ToggleRow
          title="Low stock alerts"
          description="Notify when a product drops to or below its threshold."
          checked={settings?.lowStockAlerts ?? false}
          onChange={(lowStockAlerts) => onChange({ lowStockAlerts })}
          disabled={!isManager || loading}
        />
        <ToggleRow
          title="Overdue invoice alerts"
          description="Notify when an invoice passes its due date with a balance."
          checked={settings?.overdueInvoiceAlerts ?? false}
          onChange={(overdueInvoiceAlerts) => onChange({ overdueInvoiceAlerts })}
          disabled={!isManager || loading}
        />
        <ToggleRow
          title="Daily sales summary"
          description="A recap of sales, VAT, discounts and cash variance, sent when the day is closed."
          checked={settings?.dailySalesSummary ?? false}
          onChange={(dailySalesSummary) => onChange({ dailySalesSummary })}
          disabled={!isManager || loading}
        />
      </div>
    </Card>
  );
}

function SecuritySection() {
  const { sessionTimeoutMinutes, loading } = useSessionTimeoutMinutes();
  const { staff } = useAuth();
  const isManager = staff?.role === "Manager";
  const [input, setInput] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const displayedValue = input ?? String(sessionTimeoutMinutes ?? "");

  async function save(raw: string) {
    const value = Math.trunc(Number(raw));
    if (!Number.isFinite(value) || value <= 0 || value > 480) {
      toast.error("Enter a timeout between 1 and 480 minutes.");
      setInput(null);
      return;
    }
    setSaving(true);
    try {
      await updateSessionTimeoutMinutes(value);
      setInput(null);
    } catch (err) {
      toast.error("Could not update the session timeout", {
        description: getErrorMessage(err, "Something went wrong."),
      });
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card
      title="Session"
      description="Applies to every signed-in staff member, on every device, regardless of role."
    >
      <div className="max-w-xs space-y-2">
        <Label htmlFor="session-timeout">Sign out after inactivity (minutes)</Label>
        <Input
          id="session-timeout"
          type="number"
          min={1}
          max={480}
          step="1"
          value={displayedValue}
          disabled={!isManager || loading || saving}
          onChange={(e) => setInput(e.target.value)}
          onBlur={(e) => {
            if (input !== null && e.target.value !== String(sessionTimeoutMinutes ?? "")) {
              save(e.target.value);
            } else {
              setInput(null);
            }
          }}
        />
        <p className="text-xs text-muted-foreground">
          {isManager
            ? "With no mouse, keyboard, touch or scroll activity for this long, a staff member is signed out completely and has to enter their password again."
            : "Only a Manager can change this. With no activity for this long, you'll be signed out completely and asked for your password again."}
        </p>
      </div>
    </Card>
  );
}

const STAFF_ROLES: StaffRole[] = ["Attendant", "Manager", "Accountant/Auditor"];

function StaffSection() {
  const { staff: roster, pendingIds, loading } = useStaff();
  const { staff: currentStaff } = useAuth();
  const isManager = currentStaff?.role === "Manager";
  const [resendingId, setResendingId] = useState<string | null>(null);

  function onRoleChange(id: string, role: StaffRole) {
    setStaffRole(id, role).catch((err) => {
      toast.error("Could not update role", {
        description: err instanceof Error ? err.message : String(err),
      });
    });
  }

  function onActiveChange(id: string, active: boolean) {
    setStaffActive(id, active).catch((err) => {
      toast.error("Could not update status", {
        description: err instanceof Error ? err.message : String(err),
      });
    });
  }

  async function onResend(id: string, email: string) {
    setResendingId(id);
    try {
      await resendInvite(id);
      toast.success(`Invite resent to ${email}`);
    } catch (err) {
      toast.error("Could not resend invite", {
        description: getErrorMessage(err, "Could not resend invite."),
      });
    } finally {
      setResendingId(null);
    }
  }

  return (
    <Card
      title="Staff"
      description="Everyone with a TCS login. Role and active status are enforced by the database — only a Manager can actually change them, this screen just calls the same update. Protected accounts can't be changed or deleted by anyone, including a Manager, at any layer."
      actions={isManager ? <InviteStaffDialog /> : undefined}
    >
      {loading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left text-xs uppercase tracking-wide text-muted-foreground">
                <th className="pb-2 pr-4 font-medium">Name</th>
                <th className="pb-2 pr-4 font-medium">Email</th>
                <th className="pb-2 pr-4 font-medium">Role</th>
                <th className="pb-2 pr-4 font-medium">Active</th>
                {isManager && <th className="pb-2 pr-4 font-medium">Status</th>}
              </tr>
            </thead>
            <tbody>
              {roster.map((member) => {
                const locked = member.protected || !isManager;
                const pending = pendingIds.has(member.id);
                return (
                  <tr key={member.id} className="border-b last:border-0">
                    <td className="py-3 pr-4 font-medium">
                      {member.name}
                      {member.id === currentStaff?.id && (
                        <Badge variant="secondary" className="ml-2">
                          You
                        </Badge>
                      )}
                      {member.protected && (
                        <Badge variant="outline" className="ml-2 gap-1">
                          <Lock className="size-3" /> Protected
                        </Badge>
                      )}
                    </td>
                    <td className="py-3 pr-4 text-muted-foreground">{member.email}</td>
                    <td className="py-3 pr-4">
                      {locked ? (
                        <Badge variant="outline">{member.role}</Badge>
                      ) : (
                        <Select
                          value={member.role}
                          onValueChange={(v) => onRoleChange(member.id, v as StaffRole)}
                        >
                          <SelectTrigger className="w-48">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            {STAFF_ROLES.map((role) => (
                              <SelectItem key={role} value={role}>
                                {role}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      )}
                    </td>
                    <td className="py-3 pr-4">
                      {locked ? (
                        <Badge variant={member.active ? "secondary" : "outline"}>
                          {member.active ? "Active" : "Inactive"}
                        </Badge>
                      ) : (
                        <Switch
                          checked={member.active}
                          onCheckedChange={(checked) => onActiveChange(member.id, checked)}
                        />
                      )}
                    </td>
                    {isManager && (
                      <td className="py-3 pr-4">
                        {pending ? (
                          <div className="flex items-center gap-2">
                            <Badge variant="outline" className="gap-1">
                              <Clock3 className="size-3" /> Pending
                            </Badge>
                            <Button
                              variant="ghost"
                              size="sm"
                              className="h-7 gap-1.5 px-2 text-xs"
                              disabled={resendingId === member.id}
                              onClick={() => onResend(member.id, member.email)}
                            >
                              <Send className="size-3" />
                              {resendingId === member.id ? "Sending…" : "Resend invite"}
                            </Button>
                          </div>
                        ) : (
                          <span className="text-muted-foreground">—</span>
                        )}
                      </td>
                    )}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
      {!isManager && (
        <p className="mt-4 text-sm text-muted-foreground">
          Only a Manager can change roles or deactivate staff.
        </p>
      )}
    </Card>
  );
}

function InviteStaffDialog() {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<StaffRole>("Attendant");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async () => {
    if (!name.trim() || !email.trim()) {
      setError("Name and email are both required.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await inviteStaff(email.trim(), name.trim(), role);
      toast.success(`Invite sent to ${email.trim()}`);
      setName("");
      setEmail("");
      setRole("Attendant");
      setOpen(false);
    } catch (err) {
      setError(getErrorMessage(err, "Could not send the invite."));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (next) setError(null);
      }}
    >
      <DialogTrigger asChild>
        <Button className="gap-2">
          <UserPlus className="size-4" /> Invite staff
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Invite a staff member</DialogTitle>
          <DialogDescription>
            Sends a real invite email through Supabase Auth. They click the link, set their own
            password, and land in the app already assigned to the role you pick here — no separate
            activation step.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="invite-name">Name</Label>
            <Input
              id="invite-name"
              maxLength={80}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="invite-email">Email</Label>
            <Input
              id="invite-email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label>Role</Label>
            <Select value={role} onValueChange={(v) => setRole(v as StaffRole)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {STAFF_ROLES.map((r) => (
                  <SelectItem key={r} value={r}>
                    {r}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          {error ? <p className="text-sm font-medium text-destructive">{error}</p> : null}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={saving}>
            {saving ? "Sending…" : "Send invite"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ComingSoon({
  title,
  note,
  icon: Icon,
}: {
  title: string;
  note: string;
  icon: LucideIcon;
}) {
  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">{title}</h2>
      <div className="mt-4 flex flex-col items-center justify-center rounded-2xl border border-dashed px-6 py-14 text-center">
        <div className="flex size-12 items-center justify-center rounded-2xl bg-muted">
          <Icon className="size-5 text-muted-foreground" />
        </div>
        <p className="mt-4 text-sm font-semibold">Coming soon</p>
        <p className="mt-1 max-w-sm text-sm text-muted-foreground">{note}</p>
      </div>
    </section>
  );
}

/* ----------------------------------------------------------------- pieces */

function Card({
  title,
  description,
  actions,
  children,
}: {
  title: string;
  description: string;
  actions?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="card-surface p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-sm font-semibold">{title}</h2>
          <p className="mt-1 text-sm text-muted-foreground">{description}</p>
        </div>
        {actions}
      </div>
      <div className="mt-5">{children}</div>
    </section>
  );
}

function ToggleRow({
  title,
  description,
  checked,
  onChange,
  className,
  disabled,
}: {
  title: string;
  description: string;
  checked: boolean;
  onChange: (value: boolean) => void;
  className?: string;
  disabled?: boolean;
}) {
  return (
    <div
      className={cn(
        "flex flex-wrap items-center justify-between gap-4 rounded-2xl border p-4",
        className,
      )}
    >
      <div className="min-w-0">
        <p className="text-sm font-medium">{title}</p>
        <p className="text-sm text-muted-foreground">{description}</p>
      </div>
      <Switch checked={checked} onCheckedChange={onChange} disabled={disabled} />
    </div>
  );
}

function Field({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <Input value={value} onChange={(e) => onChange(e.target.value)} />
    </div>
  );
}
