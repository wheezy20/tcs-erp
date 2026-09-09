import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

const NONE = "__none__";

/** A picker backed by a school-editable reference list (positions,
 * departments). A stored value not in the active list still round-trips,
 * flagged "(not in list)". */
export function RefListSelect({
  options,
  value,
  onChange,
  placeholder,
  disabled,
}: {
  options: string[];
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  disabled?: boolean;
}) {
  const legacy = value && !options.includes(value) ? value : null;
  return (
    <Select
      value={value || NONE}
      onValueChange={(v) => onChange(v === NONE ? "" : v)}
      disabled={disabled}
    >
      <SelectTrigger>
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={NONE}>— none —</SelectItem>
        {legacy && <SelectItem value={legacy}>{legacy} (not in list)</SelectItem>}
        {options.map((o) => (
          <SelectItem key={o} value={o}>
            {o}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
