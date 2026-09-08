import { useState } from "react";
import { Plus, X } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export function ListEditor({
  label,
  description,
  items,
  placeholder,
  onChange,
}: {
  label: string;
  description?: string;
  items: string[];
  placeholder: string;
  onChange: (items: string[]) => void;
}) {
  const [draft, setDraft] = useState("");

  function add() {
    const value = draft.trim();
    if (!value) return;
    if (items.some((i) => i.toLowerCase() === value.toLowerCase())) {
      toast.error(`"${value}" is already on the list`);
      return;
    }
    onChange([...items, value]);
    setDraft("");
  }

  return (
    <div className="space-y-3">
      <div>
        <Label>{label}</Label>
        {description && <p className="mt-1 text-sm text-muted-foreground">{description}</p>}
      </div>

      <div className="flex flex-wrap gap-2">
        {items.map((item) => (
          <span
            key={item}
            className="inline-flex items-center gap-1.5 rounded-full border bg-muted/40 py-1 pl-3 pr-1.5 text-sm"
          >
            {item}
            <button
              type="button"
              aria-label={`Remove ${item}`}
              className="rounded-full p-0.5 text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive"
              onClick={() => onChange(items.filter((i) => i !== item))}
            >
              <X className="size-3.5" />
            </button>
          </span>
        ))}
        {items.length === 0 && (
          <p className="text-sm text-muted-foreground">Nothing on this list yet.</p>
        )}
      </div>

      <div className="flex gap-2">
        <Input
          value={draft}
          placeholder={placeholder}
          maxLength={30}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              add();
            }
          }}
        />
        <Button type="button" variant="outline" onClick={add}>
          <Plus className="size-4" />
          Add
        </Button>
      </div>
    </div>
  );
}
