import { useEffect, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { toast } from "sonner";

import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { canWriteFinancials, useAuth } from "@/data/auth-store";
import {
  listContractTemplates,
  updateContractTemplate,
  type ContractTemplate,
} from "@/data/contract-templates-store";
import { getErrorMessage } from "@/lib/utils";

// Dedicated page for the four contract_templates rows (20260924) — kept
// separate from Payroll Setup's reference lists since templates aren't
// payroll-specific. Editing a template never touches an already-Issued
// document; only a future generation picks up the change.
export const Route = createFileRoute("/employees/document-templates")({
  head: () => ({ meta: [{ title: "Document templates — TCS" }] }),
  component: DocumentTemplatesPage,
});

const MERGE_FIELDS = [
  "company_name",
  "company_address",
  "company_phone",
  "company_email",
  "issue_date",
  "employee_name",
  "position",
  "department",
  "employment_type",
  "start_date",
  "probation_end_date",
  "probation_duration_months",
  "contract_end_date",
  "basic_salary",
  "payment_method",
  "qualifications",
];

function DocumentTemplatesPage() {
  const { staff } = useAuth();
  const canWrite = canWriteFinancials(staff?.role);
  const [templates, setTemplates] = useState<ContractTemplate[]>([]);
  const [loading, setLoading] = useState(true);

  async function refresh() {
    try {
      setTemplates(await listContractTemplates());
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not load templates."));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    refresh();
  }, []);

  return (
    <>
      <PageHeader
        title="Document templates"
        description="The HTML behind Appointment Letters, Probation Letters, and Contracts. Editing one only affects documents generated after the change — already-issued PDFs are frozen."
      />

      <div className="mb-6 card-surface p-4 text-sm">
        <p className="font-medium">Merge fields</p>
        <p className="mt-1 text-muted-foreground">
          Use <code>{"{{field_name}}"}</code> anywhere in the HTML below. Every field is available
          to every template — categories differ only in which ones their prose actually uses.
        </p>
        <div className="mt-2 flex flex-wrap gap-1.5">
          {MERGE_FIELDS.map((f) => (
            <code key={f} className="rounded bg-muted px-1.5 py-0.5 text-xs">
              {`{{${f}}}`}
            </code>
          ))}
        </div>
      </div>

      {loading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : (
        <div className="space-y-6">
          {templates.map((t) => (
            <TemplateEditor key={t.id} template={t} canWrite={canWrite} onSaved={refresh} />
          ))}
        </div>
      )}
    </>
  );
}

function TemplateEditor({
  template,
  canWrite,
  onSaved,
}: {
  template: ContractTemplate;
  canWrite: boolean;
  onSaved: () => Promise<void>;
}) {
  const [html, setHtml] = useState(template.htmlBody);
  const [saving, setSaving] = useState(false);
  const dirty = html !== template.htmlBody;

  async function save() {
    setSaving(true);
    try {
      await updateContractTemplate(template.id, html);
      toast.success(`${template.category} template saved`);
      await onSaved();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not save that template."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="card-surface p-6">
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-sm font-semibold">{template.category}</h2>
        <p className="text-xs text-muted-foreground">
          {template.updatedByName
            ? `Last edited by ${template.updatedByName} · ${new Date(template.updatedAt).toLocaleString()}`
            : `Created ${new Date(template.updatedAt).toLocaleString()}`}
        </p>
      </div>
      <Textarea
        className="mt-3 h-64 font-mono text-xs"
        value={html}
        disabled={!canWrite}
        onChange={(e) => setHtml(e.target.value)}
      />
      {canWrite && (
        <div className="mt-3">
          <Button size="sm" disabled={!dirty || saving} onClick={save}>
            {saving ? "Saving…" : "Save changes"}
          </Button>
        </div>
      )}
    </section>
  );
}
