import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ACCOUNT_CATEGORIES, type Account } from "@/data/accounts-store";

export function AccountPicker({
  accounts,
  value,
  onChange,
  includeInactive = false,
  placeholder = "Select account…",
}: {
  accounts: Account[];
  value: string;
  onChange: (id: string) => void;
  includeInactive?: boolean;
  placeholder?: string;
}) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger>
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent>
        {ACCOUNT_CATEGORIES.map((category) => {
          const rows = accounts.filter(
            (a) => a.category === category && (includeInactive || a.active),
          );
          if (rows.length === 0) return null;
          return (
            <SelectGroup key={category}>
              <SelectLabel>{category}</SelectLabel>
              {rows.map((a) => (
                <SelectItem key={a.id} value={a.id}>
                  {a.code} — {a.name}
                  {!a.active ? " (inactive)" : ""}
                </SelectItem>
              ))}
            </SelectGroup>
          );
        })}
      </SelectContent>
    </Select>
  );
}
