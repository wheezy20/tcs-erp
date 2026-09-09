import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { BookOpen, Pencil, Plus } from "lucide-react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { canWriteFinancials, useAuth } from "@/data/auth-store";
import { getErrorMessage } from "@/lib/utils";
import {
  ACCOUNT_CATEGORIES,
  createAccount,
  updateAccount,
  useAccounts,
  type Account,
  type AccountCategory,
} from "@/data/accounts-store";

export const Route = createFileRoute("/accounting/")({
  component: AccountingPage,
});

function AccountingPage() {
  const { staff: currentStaff } = useAuth();
  const canWrite = canWriteFinancials(currentStaff?.role);
  const { accounts, loading } = useAccounts();
  const [search, setSearch] = useState("");
  const [editing, setEditing] = useState<Account | null>(null);

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  const term = search.trim().toLowerCase();
  const filtered = term
    ? accounts.filter(
        (a) => a.code.toLowerCase().includes(term) || a.name.toLowerCase().includes(term),
      )
    : accounts;

  return (
    <>
      <div className="flex justify-end">{canWrite && <AddAccountDialog />}</div>

      <div className="mt-4 space-y-6">
        <Input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by code or name…"
          className="max-w-sm"
        />

        {ACCOUNT_CATEGORIES.map((category) => {
          const rows = filtered.filter((a) => a.category === category);
          if (rows.length === 0) return null;
          return (
            <CategoryTable
              key={category}
              category={category}
              accounts={rows}
              canWrite={canWrite}
              onEdit={setEditing}
            />
          );
        })}

        {filtered.length === 0 && (
          <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
            <BookOpen className="size-8 text-muted-foreground" />
            <p className="text-sm font-medium">No accounts match "{search}"</p>
          </div>
        )}
      </div>

      {editing && <EditAccountDialog account={editing} onClose={() => setEditing(null)} />}
    </>
  );
}

function CategoryTable({
  category,
  accounts,
  canWrite,
  onEdit,
}: {
  category: AccountCategory;
  accounts: Account[];
  canWrite: boolean;
  onEdit: (account: Account) => void;
}) {
  return (
    <div>
      <h3 className="mb-2 text-sm font-semibold text-muted-foreground">{category}</h3>
      <div className="card-surface overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
              <tr>
                <th className="px-5 py-3 font-medium">Code</th>
                <th className="px-5 py-3 font-medium">Name</th>
                <th className="px-5 py-3 font-medium">Subtype</th>
                <th className="px-5 py-3 font-medium">Normal balance</th>
                <th className="px-5 py-3 font-medium">Status</th>
                {canWrite && <th className="px-5 py-3 font-medium">&nbsp;</th>}
              </tr>
            </thead>
            <tbody className="divide-y">
              {accounts.map((a) => (
                <tr key={a.id} className="hover:bg-muted/40">
                  <td className="px-5 py-3 font-mono tabular-nums">{a.code}</td>
                  <td className="px-5 py-3">
                    <div className="font-medium">{a.name}</div>
                    {a.description && (
                      <div className="text-xs text-muted-foreground">{a.description}</div>
                    )}
                  </td>
                  <td className="px-5 py-3 text-muted-foreground">{a.subtype}</td>
                  <td className="px-5 py-3 capitalize">{a.normalBalance}</td>
                  <td className="px-5 py-3">
                    <Badge variant={a.active ? "default" : "secondary"}>
                      {a.active ? "Active" : "Inactive"}
                    </Badge>
                  </td>
                  {canWrite && (
                    <td className="px-5 py-3 text-right">
                      <Button variant="ghost" size="sm" className="gap-1" onClick={() => onEdit(a)}>
                        <Pencil className="size-3.5" /> Edit
                      </Button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

function AddAccountDialog() {
  const [open, setOpen] = useState(false);
  const [code, setCode] = useState("");
  const [name, setName] = useState("");
  const [category, setCategory] = useState<AccountCategory>("Assets");
  const [subtype, setSubtype] = useState("");
  const [description, setDescription] = useState("");
  const [submitting, setSubmitting] = useState(false);

  function reset() {
    setCode("");
    setName("");
    setCategory("Assets");
    setSubtype("");
    setDescription("");
  }

  async function submit() {
    if (!code.trim() || !name.trim() || !subtype.trim()) {
      toast.error("Code, name and subtype are required.");
      return;
    }
    setSubmitting(true);
    try {
      const created = await createAccount({ code, name, category, subtype, description });
      toast.success(`Account ${created.code} — ${created.name} created`);
      reset();
      setOpen(false);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not create the account."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (!next) reset();
      }}
    >
      <DialogTrigger asChild>
        <Button className="gap-2">
          <Plus className="size-4" /> New account
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>New account</DialogTitle>
          <DialogDescription>
            Add an account to the chart. Structure only for now.
          </DialogDescription>
        </DialogHeader>
        <AccountFields
          code={code}
          setCode={setCode}
          name={name}
          setName={setName}
          category={category}
          setCategory={setCategory}
          subtype={subtype}
          setSubtype={setSubtype}
          description={description}
          setDescription={setDescription}
          codeEditable
        />
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Creating…" : "Create account"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function EditAccountDialog({ account, onClose }: { account: Account; onClose: () => void }) {
  const [name, setName] = useState(account.name);
  const [category, setCategory] = useState<AccountCategory>(account.category);
  const [subtype, setSubtype] = useState(account.subtype);
  const [description, setDescription] = useState(account.description);
  const [active, setActive] = useState(account.active);
  const [submitting, setSubmitting] = useState(false);

  async function submit() {
    if (!name.trim() || !subtype.trim()) {
      toast.error("Name and subtype are required.");
      return;
    }
    setSubmitting(true);
    try {
      await updateAccount(account.id, { name, category, subtype, description, active });
      toast.success(`Account ${account.code} updated`);
      onClose();
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not update the account."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>
            Edit {account.code} — {account.name}
          </DialogTitle>
          <DialogDescription>The code itself can't be changed once created.</DialogDescription>
        </DialogHeader>
        <AccountFields
          code={account.code}
          setCode={() => {}}
          name={name}
          setName={setName}
          category={category}
          setCategory={setCategory}
          subtype={subtype}
          setSubtype={setSubtype}
          description={description}
          setDescription={setDescription}
          codeEditable={false}
        />
        <div className="flex items-center justify-between rounded-lg border px-3 py-2">
          <div>
            <p className="text-sm font-medium">Active</p>
            <p className="text-xs text-muted-foreground">
              Inactive accounts stay in the chart for history.
            </p>
          </div>
          <Switch checked={active} onCheckedChange={setActive} />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Saving…" : "Save changes"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function AccountFields({
  code,
  setCode,
  name,
  setName,
  category,
  setCategory,
  subtype,
  setSubtype,
  description,
  setDescription,
  codeEditable,
}: {
  code: string;
  setCode: (v: string) => void;
  name: string;
  setName: (v: string) => void;
  category: AccountCategory;
  setCategory: (v: AccountCategory) => void;
  subtype: string;
  setSubtype: (v: string) => void;
  description: string;
  setDescription: (v: string) => void;
  codeEditable: boolean;
}) {
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-3">
        <div className="space-y-1.5">
          <Label htmlFor="account-code">Code</Label>
          <Input
            id="account-code"
            value={code}
            onChange={(e) => setCode(e.target.value)}
            placeholder="e.g. 1000"
            disabled={!codeEditable}
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="account-category">Category</Label>
          <Select value={category} onValueChange={(v) => setCategory(v as AccountCategory)}>
            <SelectTrigger id="account-category">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {ACCOUNT_CATEGORIES.map((c) => (
                <SelectItem key={c} value={c}>
                  {c}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="account-name">Name</Label>
        <Input id="account-name" value={name} onChange={(e) => setName(e.target.value)} />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="account-subtype">Subtype</Label>
        <Input
          id="account-subtype"
          value={subtype}
          onChange={(e) => setSubtype(e.target.value)}
          placeholder="e.g. Current Asset"
        />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="account-description">Description (optional)</Label>
        <Textarea
          id="account-description"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          rows={2}
        />
      </div>
    </div>
  );
}
