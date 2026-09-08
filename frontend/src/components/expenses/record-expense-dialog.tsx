import { useEffect, useRef, useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { ImagePlus, Plus, X } from "lucide-react";
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
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { EXPENSE_METHODS, type ExpenseMethod } from "@/data/expenses";
import { createExpense, useExpenses } from "@/data/expenses-store";
import { TODAY } from "@/data/dashboard";
import { BankAccountSelect, useActiveBankAccounts } from "@/components/banking/bank-account-select";

const MAX_RECEIPT_BYTES = 3 * 1024 * 1024;

const schema = z
  .object({
    date: z.string().min(1, "Pick a date"),
    category: z.string().min(1, "Choose a category"),
    amount: z.coerce.number().positive("Enter an amount greater than zero").max(1_000_000),
    method: z.enum(["Cash", "Mobile Money", "Bank"]),
    bankAccountId: z.string().optional(),
    description: z.string().trim().min(3, "Add a short description").max(160),
    reference: z.string().trim().max(60).optional(),
  })
  .refine((v) => v.method !== "Bank" || !!v.bankAccountId, {
    message: "Pick the bank account this expense was paid from",
    path: ["bankAccountId"],
  });

type FormValues = z.input<typeof schema>;

export function RecordExpenseDialog() {
  const [open, setOpen] = useState(false);
  const [receiptPreview, setReceiptPreview] = useState<string | null>(null);
  const [receiptFile, setReceiptFile] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const { categories } = useExpenses();
  const { defaultId: defaultBankAccountId } = useActiveBankAccounts();

  const form = useForm<FormValues>({
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    resolver: zodResolver(schema) as any,
    defaultValues: {
      date: TODAY(),
      category: categories[0] ?? "Miscellaneous",
      amount: "" as unknown as number,
      method: "Cash",
      bankAccountId: "",
      description: "",
      reference: "",
    },
  });

  const method = form.watch("method");
  const bankAccountId = form.watch("bankAccountId");
  // Prefill only when there's exactly one active bank account (no real
  // choice); otherwise the field stays empty and the person must pick.
  useEffect(() => {
    if (method === "Bank" && !bankAccountId && defaultBankAccountId) {
      form.setValue("bankAccountId", defaultBankAccountId);
    }
  }, [method, bankAccountId, defaultBankAccountId, form]);

  function pickReceipt(file: File | undefined) {
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      toast.error("Receipt must be an image file");
      return;
    }
    if (file.size > MAX_RECEIPT_BYTES) {
      toast.error("Receipt image is too large", { description: "Keep it under 3 MB." });
      return;
    }
    setReceiptFile(file);
    const reader = new FileReader();
    reader.onload = () => setReceiptPreview(String(reader.result));
    reader.readAsDataURL(file);
  }

  const onSubmit = async (values: FormValues) => {
    const parsed = schema.parse(values);
    setSaving(true);
    try {
      const created = await createExpense({
        date: parsed.date,
        category: parsed.category,
        description: parsed.description,
        amount: parsed.amount,
        method: parsed.method as ExpenseMethod,
        reference: parsed.reference || undefined,
        bankAccountId: parsed.method === "Bank" ? parsed.bankAccountId : null,
        receiptFile,
      });
      toast.success(`${created.id} recorded`, {
        description: `${created.category} · ${created.description}`,
      });
      form.reset({
        date: TODAY(),
        category: categories[0] ?? "Miscellaneous",
        amount: "" as unknown as number,
        method: "Cash",
        bankAccountId: "",
        description: "",
        reference: "",
      });
      setReceiptPreview(null);
      setReceiptFile(null);
      if (fileRef.current) fileRef.current.value = "";
      setOpen(false);
    } catch (err) {
      toast.error("Could not record the expense", {
        description: err instanceof Error ? err.message : String(err),
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button className="gap-2">
          <Plus className="size-4" /> Record Expense
        </Button>
      </DialogTrigger>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Record expense</DialogTitle>
          <DialogDescription>
            Money leaving the till or the bank. Cash expenses reduce cash on hand on the dashboard.
          </DialogDescription>
        </DialogHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <FormField
                control={form.control}
                name="date"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Date</FormLabel>
                    <FormControl>
                      <Input type="date" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="amount"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Amount</FormLabel>
                    <FormControl>
                      <Input type="number" min={0} step="0.01" placeholder="0.00" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="category"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Category</FormLabel>
                    <Select value={field.value} onValueChange={field.onChange}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Select category" />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {categories.map((c) => (
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
                name="method"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Payment method</FormLabel>
                    <Select value={field.value} onValueChange={field.onChange}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {EXPENSE_METHODS.map((m) => (
                          <SelectItem key={m} value={m}>
                            {m}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            {method === "Bank" && (
              <FormField
                control={form.control}
                name="bankAccountId"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Bank account</FormLabel>
                    <BankAccountSelect
                      value={field.value ?? ""}
                      onChange={field.onChange}
                      placeholder="Which bank account was this paid from?"
                    />
                    <FormMessage />
                  </FormItem>
                )}
              />
            )}

            <FormField
              control={form.control}
              name="description"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Description</FormLabel>
                  <FormControl>
                    <Textarea rows={2} placeholder="What was this for?" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="reference"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Reference (optional)</FormLabel>
                  <FormControl>
                    <Input placeholder="MoMo / transfer reference" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <div className="space-y-2">
              <Label>Receipt image (optional)</Label>
              {receiptPreview ? (
                <div className="flex items-center gap-3 rounded-xl border p-3">
                  <img
                    src={receiptPreview}
                    alt="Receipt preview"
                    className="size-16 rounded-lg border object-cover"
                  />
                  <p className="flex-1 text-sm text-muted-foreground">Receipt attached</p>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    aria-label="Remove receipt"
                    onClick={() => {
                      setReceiptPreview(null);
                      setReceiptFile(null);
                      if (fileRef.current) fileRef.current.value = "";
                    }}
                  >
                    <X className="size-4" />
                  </Button>
                </div>
              ) : (
                <Button
                  type="button"
                  variant="outline"
                  className="w-full gap-2"
                  onClick={() => fileRef.current?.click()}
                >
                  <ImagePlus className="size-4" /> Attach receipt photo
                </Button>
              )}
              <input
                ref={fileRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => pickReceipt(e.target.files?.[0])}
              />
            </div>

            <DialogFooter>
              <Button
                type="button"
                variant="ghost"
                onClick={() => setOpen(false)}
                disabled={saving}
              >
                Cancel
              </Button>
              <Button type="submit" disabled={saving}>
                {saving ? "Saving…" : "Save expense"}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
