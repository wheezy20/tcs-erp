import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  activeProviders,
  usePaymentProviders,
  type PaymentKind,
} from "@/data/payment-providers-store";

/** The fields a Manager can amend on a pending pay config before approving
 * it (see `AdjustPayFields` below) — basic salary + the same three
 * payment-destination fields a propose dialog already collects. Kept as
 * strings (not `number`) so the salary input behaves like every other
 * salary `<Input type="number">` in this codebase (free typing, parsed on
 * submit). */
export type PayOverride = {
  basicSalary: string;
  paymentMethod: PaymentKind;
  bank: string;
  accountNo: string;
};

export function payOverrideFrom(cfg: {
  basicSalary: number;
  paymentMethod: PaymentKind;
  bank: string | null;
  accountNo: string | null;
}): PayOverride {
  return {
    basicSalary: String(cfg.basicSalary),
    paymentMethod: cfg.paymentMethod,
    bank: cfg.bank ?? "",
    accountNo: cfg.accountNo ?? "",
  };
}

const NONE = "__none__";

/** Provider picker backed by the school-editable `payment_providers`
 * reference list, filtered to the given payment method. A value that
 * isn't in the active list (a legacy free-text entry) stays selectable so
 * an old config still round-trips. */
export function PaymentProviderSelect({
  method,
  value,
  onChange,
  disabled,
}: {
  method: PaymentKind;
  value: string;
  onChange: (v: string) => void;
  disabled?: boolean;
}) {
  const { providers } = usePaymentProviders();
  const active = activeProviders(providers, method);
  const legacy = value && !active.some((p) => p.name === value) ? value : null;

  return (
    <Select
      value={value || NONE}
      onValueChange={(v) => onChange(v === NONE ? "" : v)}
      disabled={disabled}
    >
      <SelectTrigger>
        <SelectValue placeholder={method === "Mobile Money" ? "Select network" : "Select bank"} />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={NONE}>— none —</SelectItem>
        {legacy && <SelectItem value={legacy}>{legacy} (not in list)</SelectItem>}
        {active.map((p) => (
          <SelectItem key={p.id} value={p.name}>
            {p.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

/** The three fields that describe where net pay is sent: method, provider
 * (bank or network) and the account / wallet number. Renders as three
 * grid cells so it drops into a `grid-cols-2` layout. */
export function PaymentDestinationFields({
  method,
  provider,
  number,
  onMethod,
  onProvider,
  onNumber,
  disabled,
}: {
  method: PaymentKind;
  provider: string;
  number: string;
  onMethod: (v: PaymentKind) => void;
  onProvider: (v: string) => void;
  onNumber: (v: string) => void;
  disabled?: boolean;
}) {
  return (
    <>
      <div className="space-y-1.5">
        <Label>Payment method</Label>
        <Select
          value={method}
          onValueChange={(v) => onMethod(v as PaymentKind)}
          disabled={disabled}
        >
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="Bank">Bank</SelectItem>
            <SelectItem value="Mobile Money">Mobile Money</SelectItem>
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-1.5">
        <Label>{method === "Mobile Money" ? "Network" : "Bank"}</Label>
        <PaymentProviderSelect
          method={method}
          value={provider}
          onChange={onProvider}
          disabled={disabled}
        />
      </div>
      <div className="space-y-1.5">
        <Label>{method === "Mobile Money" ? "Mobile money number" : "Account number"}</Label>
        <Input value={number} disabled={disabled} onChange={(e) => onNumber(e.target.value)} />
      </div>
    </>
  );
}

/** Basic salary + `PaymentDestinationFields`, pre-filled from a proposed
 * pay config and fully controlled — the parent (a pending-approval detail
 * view) owns `value`/`onChange` and decides at Approve-click time whether
 * to send these as an override or not. Changing the payment method resets
 * the provider field, same behavior as the propose dialogs. */
export function AdjustPayFields({
  value,
  onChange,
}: {
  value: PayOverride;
  onChange: (next: PayOverride) => void;
}) {
  return (
    <div className="grid grid-cols-2 gap-3">
      <div className="space-y-1.5">
        <Label>Basic salary</Label>
        <Input
          type="number"
          min="0"
          step="0.01"
          value={value.basicSalary}
          onChange={(e) => onChange({ ...value, basicSalary: e.target.value })}
        />
      </div>
      <div />
      <PaymentDestinationFields
        method={value.paymentMethod}
        provider={value.bank}
        number={value.accountNo}
        onMethod={(m) => onChange({ ...value, paymentMethod: m, bank: "" })}
        onProvider={(b) => onChange({ ...value, bank: b })}
        onNumber={(n) => onChange({ ...value, accountNo: n })}
      />
    </div>
  );
}
