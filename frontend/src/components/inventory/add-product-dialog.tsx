import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Plus } from "lucide-react";
import { toast } from "sonner";

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
import {
  Form,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useCurrentBranch } from "@/data/branch-store";
import { addProduct } from "@/data/inventory-store";
import { useDocumentSettings } from "@/data/settings-store";

const schema = z.object({
  name: z.string().trim().min(2, "Product name is required").max(120),
  category: z.string().min(1, "Category is required"),
  unit: z.string().min(1, "Unit is required"),
  size: z.string().trim().max(60).optional(),
  // z.literal("") must come first — z.union tries schemas in order, and
  // z.coerce.number() alone would coerce a blank string to 0 (Number("")
  // is 0, which passes .min(0)) before "" ever gets a chance to match,
  // silently turning "left blank" into "confirmed zero cost," exactly the
  // bug this field exists to avoid.
  cost: z
    .union([z.literal(""), z.coerce.number().min(0, "Must be 0 or more").max(1_000_000)])
    .optional(),
  // Same literal-first union shape as cost, for the same reason — and now
  // load-bearing beyond a report going stale: a blank price silently
  // coercing to a confirmed 0 here would mean the product could actually
  // be sold for free, not just misreport margin.
  price: z
    .union([z.literal(""), z.coerce.number().min(0, "Must be 0 or more").max(1_000_000)])
    .optional(),
  stock: z.coerce.number().int("Whole numbers only").min(0).max(1_000_000),
  threshold: z.union([z.coerce.number().int().min(0).max(1_000_000), z.literal("")]).optional(),
  description: z.string().trim().max(400).optional(),
});

type FormValues = z.input<typeof schema>;

export function AddProductDialog() {
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const { name: branchName } = useCurrentBranch();
  const { inventory } = useDocumentSettings();
  const CATEGORIES = inventory.categories;
  const UNITS = inventory.units;
  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: "",
      category: "Paint",
      unit: "Litres",
      size: "",
      cost: "",
      price: "",
      stock: "" as unknown as number,
      threshold: "",
      description: "",
    },
  });

  const onSubmit = form.handleSubmit(async (raw) => {
    const values = schema.parse(raw);
    setSaving(true);
    try {
      await addProduct({
        name: values.name,
        description: values.description || "No description added yet.",
        category: values.category,
        unit: values.unit,
        size: values.size || "—",
        cost: values.cost === "" || values.cost === undefined ? null : values.cost,
        price: values.price === "" || values.price === undefined ? null : values.price,
        stock: values.stock,
        threshold:
          values.threshold === "" || values.threshold === undefined ? null : values.threshold,
      });
      toast.success(`${values.name} added to inventory`);
      form.reset();
      setOpen(false);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Could not add the product.");
    } finally {
      setSaving(false);
    }
  });

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button className="gap-2">
          <Plus className="size-4" /> Add Product
        </Button>
      </DialogTrigger>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Add product</DialogTitle>
          <DialogDescription>
            New products are stocked at the {branchName ?? "…"}.
          </DialogDescription>
        </DialogHeader>

        <Form {...form}>
          <form onSubmit={onSubmit} className="space-y-4">
            <FormField
              control={form.control}
              name="name"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Product name</FormLabel>
                  <FormControl>
                    <Input placeholder="Dulux Weathershield 20L" maxLength={120} {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <div className="grid gap-4 sm:grid-cols-2">
              <FormField
                control={form.control}
                name="category"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Category</FormLabel>
                    <Select onValueChange={field.onChange} value={field.value}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {CATEGORIES.map((c) => (
                          <SelectItem key={c} value={c}>
                            {c}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="unit"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Unit of measure</FormLabel>
                    <Select onValueChange={field.onChange} value={field.value}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {UNITS.map((u) => (
                          <SelectItem key={u} value={u}>
                            {u}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            <FormField
              control={form.control}
              name="size"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Pack size (optional)</FormLabel>
                  <FormControl>
                    <Input placeholder="20L bucket · 4 pcs / box" maxLength={60} {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <div className="grid gap-4 sm:grid-cols-3">
              <FormField
                control={form.control}
                name="cost"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Cost price (optional)</FormLabel>
                    <FormControl>
                      <Input
                        type="number"
                        min={0}
                        step="0.01"
                        placeholder="Leave blank if unknown"
                        {...field}
                      />
                    </FormControl>
                    <FormDescription>
                      Leave blank if not yet known — margin and valuation figures will flag this
                      product as incomplete until it's set.
                    </FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="price"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Selling price (optional)</FormLabel>
                    <FormControl>
                      <Input
                        type="number"
                        min={0}
                        step="0.01"
                        placeholder="Leave blank if unknown"
                        {...field}
                      />
                    </FormControl>
                    <FormDescription>
                      Leave blank if not yet known — this product can&apos;t be added to a POS sale
                      or invoice until a price is set.
                    </FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="stock"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Opening stock</FormLabel>
                    <FormControl>
                      <Input type="number" min={0} step="1" placeholder="0" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            <FormField
              control={form.control}
              name="threshold"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Low-stock threshold (optional)</FormLabel>
                  <FormControl>
                    <Input
                      type="number"
                      min={0}
                      step="1"
                      placeholder="Use global default"
                      {...field}
                    />
                  </FormControl>
                  <FormDescription>
                    Leave empty to follow the global default threshold.
                  </FormDescription>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="description"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Description (optional)</FormLabel>
                  <FormControl>
                    <Textarea
                      rows={3}
                      maxLength={400}
                      placeholder="Finish, coverage, origin…"
                      {...field}
                    />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => setOpen(false)}
                disabled={saving}
              >
                Cancel
              </Button>
              <Button type="submit" disabled={saving}>
                {saving ? "Saving…" : "Save product"}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
