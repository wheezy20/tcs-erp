import { useState } from "react";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { ArrowLeft } from "lucide-react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Form,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { useAuth } from "@/data/auth-store";
import { type Product } from "@/data/inventory";
import { updateProduct, useInventory } from "@/data/inventory-store";
import { useDocumentSettings } from "@/data/settings-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/inventory/$productId/edit")({
  head: () => ({
    meta: [
      { title: "Edit product — TCS Inventory" },
      {
        name: "description",
        content: "Update a product's name, description, category, unit, sizing and pricing.",
      },
    ],
  }),
  component: EditProductPage,
});

// Same shape as AddProductDialog's schema, minus opening stock (this form
// never touches stock.get()) and with name required rather than absent —
// name is only settable through this direct-edit path, never through
// import (see ProductUpdate in inventory-store.ts).
const schema = z.object({
  name: z.string().trim().min(2, "Product name is required").max(120),
  category: z.string().min(1, "Category is required"),
  unit: z.string().min(1, "Unit is required"),
  size: z.string().trim().max(60).optional(),
  // z.literal("") first, same reasoning as AddProductDialog: z.coerce.number()
  // alone would coerce a blank string to a confirmed 0 before "" gets a
  // chance to match.
  cost: z
    .union([z.literal(""), z.coerce.number().min(0, "Must be 0 or more").max(1_000_000)])
    .optional(),
  price: z
    .union([z.literal(""), z.coerce.number().min(0, "Must be 0 or more").max(1_000_000)])
    .optional(),
  threshold: z.union([z.coerce.number().int().min(0).max(1_000_000), z.literal("")]).optional(),
  description: z.string().trim().max(400).optional(),
});

type FormValues = z.input<typeof schema>;

function EditProductPage() {
  const { productId } = Route.useParams();
  const { products } = useInventory();
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

  // The same Manager-only restriction Delete already has on this product's
  // detail page — a UI-level gate on this specific direct-edit screen, not a
  // new database boundary: the underlying products RLS write policy stays
  // "any active staff except Accountant/Auditor" (can_write()), unchanged,
  // since Attendant's existing bulk-import update path already relies on
  // being able to write these same columns and nothing here should narrow
  // that. The route itself is what actually keeps an Attendant off this
  // screen (there's no separate "direct edit" RPC RLS could gate on), the
  // same relationship the /reports and /accounting route guards already
  // have to their own role restrictions.
  if (!isManager) {
    return (
      <div className="card-surface p-10 text-center">
        <p className="text-sm font-medium">Editing product details is restricted to Managers</p>
        <p className="mx-auto mt-1 max-w-sm text-sm text-muted-foreground">
          Ask a Manager if this product's name, pricing or category needs to change. Stock and
          thresholds can still be adjusted from the product page.
        </p>
        <Link
          to="/inventory/$productId"
          params={{ productId }}
          className="mt-3 inline-block text-sm text-primary hover:underline"
        >
          Back to {product.name}
        </Link>
      </div>
    );
  }

  return <EditProductForm key={product.id} product={product} />;
}

function EditProductForm({ product }: { product: Product }) {
  const navigate = useNavigate();
  const [saving, setSaving] = useState(false);
  const { inventory } = useDocumentSettings();
  const CATEGORIES = inventory.categories;
  const UNITS = inventory.units;

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: product.name,
      category: product.category,
      unit: product.unit,
      size: product.size,
      cost: product.cost === null ? "" : product.cost,
      price: product.price === null ? "" : product.price,
      threshold: product.threshold === null ? "" : product.threshold,
      description: product.description,
    },
  });

  const onSubmit = form.handleSubmit(async (raw) => {
    const values = schema.parse(raw);
    setSaving(true);
    try {
      await updateProduct(product.id, {
        name: values.name,
        description: values.description || "No description added yet.",
        category: values.category,
        unit: values.unit,
        size: values.size || "—",
        cost: values.cost === "" || values.cost === undefined ? null : values.cost,
        price: values.price === "" || values.price === undefined ? null : values.price,
        threshold:
          values.threshold === "" || values.threshold === undefined ? null : values.threshold,
      });
      toast.success(`${values.name} updated`);
      navigate({ to: "/inventory/$productId", params: { productId: product.id } });
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not update the product."));
    } finally {
      setSaving(false);
    }
  });

  return (
    <>
      <Link
        to="/inventory/$productId"
        params={{ productId: product.id }}
        className="mb-4 inline-flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="size-4" /> Back to {product.name}
      </Link>

      <div className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight md:text-3xl">Edit product</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          SKU {product.sku} · {product.stock.toLocaleString("en-GH")} {product.unit.toLowerCase()}{" "}
          in stock — SKU is system-generated and stock is changed only from Adjust stock, neither is
          editable here.
        </p>
      </div>

      <div className="card-surface max-w-2xl p-6">
        <Form {...form}>
          <form onSubmit={onSubmit} className="space-y-4">
            <FormField
              control={form.control}
              name="name"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Product name</FormLabel>
                  <FormControl>
                    <Input maxLength={120} {...field} />
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

            <div className="grid gap-4 sm:grid-cols-2">
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

            <div className="flex justify-end gap-2 pt-2">
              <Button type="button" variant="outline" disabled={saving} asChild>
                <Link to="/inventory/$productId" params={{ productId: product.id }}>
                  Cancel
                </Link>
              </Button>
              <Button type="submit" disabled={saving}>
                {saving ? "Saving…" : "Save changes"}
              </Button>
            </div>
          </form>
        </Form>
      </div>
    </>
  );
}
