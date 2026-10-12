import { useRef, useState } from "react";
import { ExternalLink } from "lucide-react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { StaffRole } from "@/data/auth-store";
import { listDocuments } from "@/modules/admissions/data/application-detail";
import { openApplicationDocument } from "@/modules/admissions/data/documents";
import { setDocumentStatus } from "@/modules/admissions/data/mutations";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import {
  DOCUMENT_STATUS_LABELS,
  DOCUMENT_STATUS_TONE,
  DOCUMENT_TYPE_LABELS,
  type DocumentStatus,
} from "@/modules/admissions/labels";
import { documentStatusTargets } from "@/modules/admissions/permissions";
import { getErrorMessage } from "@/lib/utils";

const dateTime = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });

export function DocumentsPanel({
  applicationId,
  role,
}: {
  applicationId: string;
  role: StaffRole | undefined;
}) {
  const docs = useLoad(
    () => listDocuments(applicationId),
    [applicationId],
    "Could not load documents.",
  );
  const [busyId, setBusyId] = useState<string | null>(null);
  // Guards against a double click signing two links at once.
  const opening = useRef<string | null>(null);

  async function view(documentId: string) {
    if (opening.current) return;
    opening.current = documentId;
    try {
      await openApplicationDocument(documentId);
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not open the document."));
    } finally {
      opening.current = null;
    }
  }

  async function changeStatus(documentId: string, status: string) {
    setBusyId(documentId);
    try {
      await setDocumentStatus(documentId, status);
      toast.success("Document status updated");
      await docs.reload();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not update the document."));
    } finally {
      setBusyId(null);
    }
  }

  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">Documents</h2>
      <p className="mt-1 text-sm text-muted-foreground">
        Stored privately. View opens a link that works for five minutes.
      </p>

      <div className="mt-5 space-y-2">
        {docs.error && <p className="text-sm text-destructive">{docs.error}</p>}
        {!docs.error && docs.loading && !docs.data && (
          <p className="text-sm text-muted-foreground">Loading…</p>
        )}
        {docs.data && docs.data.length === 0 && (
          <p className="text-sm text-muted-foreground">No documents on this application.</p>
        )}
        {docs.data?.map((doc) => {
          const targets = documentStatusTargets(role, doc.status);
          const status = doc.status as DocumentStatus;
          return (
            <div
              key={doc.id}
              className="flex flex-wrap items-center justify-between gap-3 rounded-md border px-3 py-2 text-sm"
            >
              <div className="min-w-0">
                <div className="font-medium">
                  {DOCUMENT_TYPE_LABELS[doc.documentType] ?? doc.documentType}
                </div>
                <div className="truncate text-xs text-muted-foreground">
                  {doc.uploadedAt
                    ? `Uploaded ${dateTime.format(new Date(doc.uploadedAt))}`
                    : "Required, not uploaded yet"}
                </div>
              </div>
              <div className="flex shrink-0 items-center gap-2">
                {targets.length > 0 ? (
                  <Select
                    value={doc.status}
                    disabled={busyId === doc.id}
                    onValueChange={(v) => v !== doc.status && changeStatus(doc.id, v)}
                  >
                    <SelectTrigger className="h-8 w-40" aria-label="Document status">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value={doc.status}>
                        {DOCUMENT_STATUS_LABELS[status] ?? doc.status}
                      </SelectItem>
                      {targets.map((t) => (
                        <SelectItem key={t} value={t}>
                          {DOCUMENT_STATUS_LABELS[t as DocumentStatus]}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                ) : (
                  <Badge variant={DOCUMENT_STATUS_TONE[status] ?? "outline"}>
                    {DOCUMENT_STATUS_LABELS[status] ?? doc.status}
                  </Badge>
                )}
                {doc.uploadedAt && (
                  <Button variant="ghost" size="sm" onClick={() => view(doc.id)}>
                    View <ExternalLink className="size-3.5" />
                  </Button>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}
