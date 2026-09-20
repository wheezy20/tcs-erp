import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";
import type { DocumentKind } from "@/data/generated-documents-store";

// contract_templates (20260924100000): one editable HTML body per
// document kind, Manager/Accountant write, Auditor read. Editing a
// template never touches an already-Issued document — that's a frozen,
// already-rendered PDF in storage by then; only a future generation
// picks up the change.

export type TemplateCategory = DocumentKind;

export type ContractTemplate = {
  id: string;
  category: TemplateCategory;
  htmlBody: string;
  updatedByName: string | null;
  updatedAt: string;
};

type Row = Database["public"]["Tables"]["contract_templates"]["Row"] & {
  updater: { name: string } | null;
};

function mapRow(row: Row): ContractTemplate {
  return {
    id: row.id,
    category: row.category as TemplateCategory,
    htmlBody: row.html_body,
    updatedByName: row.updater?.name ?? null,
    updatedAt: row.updated_at,
  };
}

export async function listContractTemplates(): Promise<ContractTemplate[]> {
  const { data, error } = await supabase
    .from("contract_templates")
    .select("*, updater:staff!contract_templates_updated_by_fkey(name)")
    .order("category");
  if (error) throw error;
  return (data as unknown as Row[]).map(mapRow);
}

export async function updateContractTemplate(id: string, htmlBody: string): Promise<void> {
  const { error } = await supabase
    .from("contract_templates")
    .update({ html_body: htmlBody })
    .eq("id", id);
  if (error) throw error;
}
