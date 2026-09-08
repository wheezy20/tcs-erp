import { useMemo } from "react";

import { useBankAccounts } from "@/data/bank-accounts-store";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

/**
 * Shared bank-account picker for every place a Card / Bank Transfer /
 * Cheque / Bank settlement is recorded (POS, invoicing, expenses,
 * sale-return top-ups, supplier payments). Since the
 * multi-bank-account-posting migration each of those methods routes to a
 * specific bank account's own ledger sub-account, chosen per transaction.
 *
 * `defaultId` is the sensible-default rule: prefill only when there is
 * exactly one active bank account (no real choice to make). With more than
 * one, `defaultId` is "" so the caller must not silently guess — the field
 * stays empty until a person picks.
 */
export function useActiveBankAccounts() {
  const { accounts, loading } = useBankAccounts();
  const active = useMemo(() => accounts.filter((a) => a.active), [accounts]);
  const defaultId = active.length === 1 ? active[0].id : "";
  return { active, defaultId, loading };
}

export function BankAccountSelect({
  value,
  onChange,
  id,
  disabled = false,
  placeholder = "Select the bank account…",
}: {
  value: string;
  onChange: (id: string) => void;
  id?: string;
  disabled?: boolean;
  placeholder?: string;
}) {
  const { active } = useActiveBankAccounts();

  return (
    <Select value={value} onValueChange={onChange} disabled={disabled}>
      <SelectTrigger id={id}>
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent>
        {active.map((account) => (
          <SelectItem key={account.id} value={account.id}>
            {account.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
