import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { activeBanks, useBanks } from "@/data/banks-store";

const NONE = "__none__";

/** Bank picker backed by the school-editable `banks` reference list. A
 * value that isn't in the active list (a legacy free-text entry) stays
 * selectable so an old config still round-trips. */
export function BankSelect({
  value,
  onChange,
  disabled,
}: {
  value: string;
  onChange: (v: string) => void;
  disabled?: boolean;
}) {
  const { banks } = useBanks();
  const active = activeBanks(banks);
  const legacy = value && !active.some((b) => b.name === value) ? value : null;

  return (
    <Select
      value={value || NONE}
      onValueChange={(v) => onChange(v === NONE ? "" : v)}
      disabled={disabled}
    >
      <SelectTrigger>
        <SelectValue placeholder="Select bank" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={NONE}>— none —</SelectItem>
        {legacy && <SelectItem value={legacy}>{legacy} (not in list)</SelectItem>}
        {active.map((b) => (
          <SelectItem key={b.id} value={b.name}>
            {b.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
