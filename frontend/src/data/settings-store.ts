import { useSyncExternalStore } from "react";

import { CATEGORIES, DEFAULT_THRESHOLD, UNITS } from "@/data/inventory";

export type ReceiptPaper = "58mm" | "80mm" | "A4";
export type InvoicePaper = "A4" | "A5" | "Letter";
export type DefaultVatMode = "per-item" | "all";
export type DateFormat = "DD/MM/YYYY" | "MM/DD/YYYY" | "YYYY-MM-DD" | "D MMM YYYY";

export type CompanyDetails = {
  name: string;
  tradingName: string;
  address: string;
  postalAddress: string;
  phone: string;
  email: string;
  website: string;
  vatNumber: string;
  registrationNumber: string;
};

export type TaxSettings = {
  vatRate: number;
  defaultVatMode: DefaultVatMode;
  vatNote: string;
};

export type InventorySettings = {
  units: string[];
  categories: string[];
};

export type SalesSettings = {
  paymentTermsDays: number;
  invoicePrefix: string;
  nextInvoiceNumber: number;
  receiptPrefix: string;
  nextReceiptNumber: number;
  requireCustomerOnPos: boolean;
};

export type LocalisationSettings = {
  currencyCode: string;
  currencySymbol: string;
  decimals: number;
  dateFormat: DateFormat;
  timezone: string;
};

export type AppearanceSettings = {
  accent: string;
};

export type DocumentSettings = {
  receiptPaper: ReceiptPaper;
  invoicePaper: InvoicePaper;
  company: CompanyDetails;
  logoDataUrl: string | null;
  showVatNumber: boolean;
  tax: TaxSettings;
  inventory: InventorySettings;
  sales: SalesSettings;
  localisation: LocalisationSettings;
  appearance: AppearanceSettings;
};

export const RECEIPT_PAPERS: ReceiptPaper[] = ["58mm", "80mm", "A4"];
export const INVOICE_PAPERS: InvoicePaper[] = ["A4", "A5", "Letter"];
export const DATE_FORMATS: DateFormat[] = ["DD/MM/YYYY", "MM/DD/YYYY", "YYYY-MM-DD", "D MMM YYYY"];
export const TIMEZONES = [
  "GMT (Africa/Accra)",
  "WAT (Africa/Lagos)",
  "CAT (Africa/Harare)",
  "EAT (Africa/Nairobi)",
  "UTC",
];
// TCS brand deep teal (sampled from frontend/brand/ artwork). AccentSync
// applies this inline on document.documentElement, which is what actually
// drives --primary/--accent/--ring/--sidebar-*/--chart-1 at runtime — the
// styles.css defaults are only a pre-hydration/no-JS fallback, so this is
// the value that has to change for a re-theme to be visible at all. Was an
// unrelated indigo placeholder (#00029B).
export const DEFAULT_ACCENT = "#005e61";

/** Printable widths in millimetres. */
export const PAPER_WIDTH_MM: Record<ReceiptPaper | InvoicePaper, number> = {
  "58mm": 58,
  "80mm": 80,
  A4: 210,
  A5: 148,
  Letter: 216,
};

export const PAPER_HEIGHT_MM: Record<InvoicePaper, number> = {
  A4: 297,
  A5: 210,
  Letter: 279,
};

const defaultSettings: DocumentSettings = {
  receiptPaper: "80mm",
  invoicePaper: "A4",
  company: {
    name: "Treasures Christian School",
    tradingName: "TCS",
    address: "12 Spintex Road, Accra, Ghana",
    postalAddress: "P.O. Box CT 4482, Cantonments, Accra",
    phone: "+233 30 279 1100",
    email: "info@treasureschristianschool.com",
    website: "www.treasureschristianschool.com",
    vatNumber: "GHA-VAT-0455129",
    registrationNumber: "CS-118220 2018",
  },
  logoDataUrl: null,
  showVatNumber: true,
  tax: {
    vatRate: 20,
    defaultVatMode: "per-item",
    vatNote: "VAT charged at the standard rate on taxable items.",
  },
  inventory: {
    // "Unconfirmed" is a real, selectable unit, not a null/blank state — a
    // deliberate placeholder for stock received before its actual unit of
    // measure is known, so a product never has to sit un-creatable (or with
    // a guessed-wrong unit) while that gets sorted out. Manager-editable
    // like every other entry here; the Inventory page surfaces a count of
    // products still on it so it doesn't quietly get forgotten.
    units: [...new Set([...UNITS, "Inches", "Tins", "Unconfirmed"])],
    categories: [...CATEGORIES],
  },
  sales: {
    paymentTermsDays: 30,
    invoicePrefix: "INV-",
    nextInvoiceNumber: 2430,
    receiptPrefix: "RCP-",
    nextReceiptNumber: 1084,
    requireCustomerOnPos: false,
  },
  localisation: {
    currencyCode: "GHS",
    currencySymbol: "GH₵",
    decimals: 2,
    dateFormat: "DD/MM/YYYY",
    timezone: "GMT (Africa/Accra)",
  },
  appearance: {
    accent: DEFAULT_ACCENT,
  },
};

export const DEFAULT_LOW_STOCK_THRESHOLD = DEFAULT_THRESHOLD;

const STORAGE_KEY = "tcs.document-settings";

let state: DocumentSettings = defaultSettings;
let hydrated = false;

const listeners = new Set<() => void>();

function emit() {
  listeners.forEach((l) => l());
}

function hydrate() {
  if (hydrated || typeof window === "undefined") return;
  hydrated = true;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw) as Partial<DocumentSettings>;
      state = {
        ...defaultSettings,
        ...parsed,
        company: { ...defaultSettings.company, ...(parsed.company ?? {}) },
        tax: { ...defaultSettings.tax, ...(parsed.tax ?? {}) },
        inventory: { ...defaultSettings.inventory, ...(parsed.inventory ?? {}) },
        sales: { ...defaultSettings.sales, ...(parsed.sales ?? {}) },
        localisation: { ...defaultSettings.localisation, ...(parsed.localisation ?? {}) },
        appearance: { ...defaultSettings.appearance, ...(parsed.appearance ?? {}) },
      };
    }
  } catch {
    /* ignore malformed storage */
  }
}

function persist() {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch {
    /* storage may be unavailable */
  }
}

function subscribe(listener: () => void) {
  hydrate();
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function getSnapshot() {
  hydrate();
  return state;
}

function getServerSnapshot() {
  return defaultSettings;
}

export function useDocumentSettings() {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

/** Non-reactive read, for formatters that run outside React. */
export function getSettings() {
  hydrate();
  return state;
}

export function updateSettings(patch: Partial<DocumentSettings>) {
  state = { ...state, ...patch };
  persist();
  emit();
}

export function updateCompany(patch: Partial<CompanyDetails>) {
  state = { ...state, company: { ...state.company, ...patch } };
  persist();
  emit();
}

export function updateTax(patch: Partial<TaxSettings>) {
  state = { ...state, tax: { ...state.tax, ...patch } };
  persist();
  emit();
}

export function updateInventorySettings(patch: Partial<InventorySettings>) {
  state = { ...state, inventory: { ...state.inventory, ...patch } };
  persist();
  emit();
}

export function updateSalesSettings(patch: Partial<SalesSettings>) {
  state = { ...state, sales: { ...state.sales, ...patch } };
  persist();
  emit();
}

export function updateLocalisation(patch: Partial<LocalisationSettings>) {
  state = { ...state, localisation: { ...state.localisation, ...patch } };
  persist();
  emit();
}

export function updateAppearance(patch: Partial<AppearanceSettings>) {
  state = { ...state, appearance: { ...state.appearance, ...patch } };
  persist();
  emit();
}

export function resetSettings() {
  state = defaultSettings;
  persist();
  emit();
}

/** Formats a date string (YYYY-MM-DD) with the configured date format. */
export function formatDate(value: string, format = getSettings().localisation.dateFormat) {
  const [y, m, d] = value.slice(0, 10).split("-");
  if (!y || !m || !d) return value;
  const months = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];
  switch (format) {
    case "MM/DD/YYYY":
      return `${m}/${d}/${y}`;
    case "YYYY-MM-DD":
      return `${y}-${m}-${d}`;
    case "D MMM YYYY":
      return `${Number(d)} ${months[Number(m) - 1] ?? m} ${y}`;
    default:
      return `${d}/${m}/${y}`;
  }
}
