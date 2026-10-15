import { useRef } from "react";
import { Link } from "@tanstack/react-router";
import { Download } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { listDocuments } from "@/modules/admissions/data/application-detail";
import { downloadApplicationDocument } from "@/modules/admissions/data/documents";
import { getMatchFlag } from "@/modules/admissions/data/submission-check";
import { FEE_PROOF, FEE_PROOF_NOTE, feeProofFirst } from "@/modules/admissions/document-files";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import { DOCUMENT_TYPE_LABELS } from "@/modules/admissions/labels";
import { MATCH_OUTCOME_LABELS, differenceRows } from "@/modules/admissions/submission-check";
import { getErrorMessage } from "@/lib/utils";

// Submission check (admissions slice 9a): what staff verify on a public
// application before relying on it. The fee proof comes first, with the
// note to match it against the bank or mobile money record (D-9e). Then
// what the match found: an anonymous submission never changes a family's
// guardians or a child's record (D-9b), so anything different the parent
// sent is listed here for staff to act on. Files are downloaded, never
// opened inline. Shown only when there is something to check.

export function SubmissionCheckPanel({ applicationId }: { applicationId: string }) {
  const res = useLoad(
    async () => {
      const [docs, flag] = await Promise.all([
        listDocuments(applicationId),
        getMatchFlag(applicationId),
      ]);
      return { docs: feeProofFirst(docs.filter((d) => d.uploadedAt)), flag };
    },
    [applicationId],
    "Could not load the submission check.",
  );
  const opening = useRef(false);

  async function download(documentId: string) {
    if (opening.current) return;
    opening.current = true;
    try {
      await downloadApplicationDocument(documentId);
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not download the document."));
    } finally {
      opening.current = false;
    }
  }

  if (res.error) {
    return (
      <section className="card-surface p-6">
        <h2 className="text-sm font-semibold">Submission check</h2>
        <p className="mt-2 text-sm text-destructive">{res.error}</p>
      </section>
    );
  }
  if (!res.data) return null;
  const { docs, flag } = res.data;
  const hasFeeProof = docs.some((d) => d.documentType === FEE_PROOF);
  if (!flag && !hasFeeProof) return null;
  const rows = flag ? differenceRows(flag.differences, flag.gradeNames) : [];

  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">Submission check</h2>

      {docs.length > 0 && (
        <div className="mt-4 space-y-2">
          {docs.map((d) => (
            <div
              key={d.id}
              className="flex flex-wrap items-start justify-between gap-3 rounded-md border px-3 py-2 text-sm"
            >
              <div className="min-w-0">
                <div className="font-medium">
                  {d.documentType === FEE_PROOF
                    ? "Proof of payment of the application fee"
                    : (DOCUMENT_TYPE_LABELS[d.documentType] ?? d.documentType)}
                </div>
                {d.documentType === FEE_PROOF && (
                  <p className="mt-1 max-w-md text-xs text-muted-foreground">{FEE_PROOF_NOTE}</p>
                )}
              </div>
              <Button variant="ghost" size="sm" onClick={() => download(d.id)}>
                Download <Download className="size-3.5" />
              </Button>
            </div>
          ))}
        </div>
      )}

      <div className="mt-5">
        <h3 className="text-xs uppercase tracking-wide text-muted-foreground">Match</h3>
        {!flag ? (
          <p className="mt-1 text-sm">No existing family matched. A new family was created.</p>
        ) : (
          <div className="mt-1 space-y-3 text-sm">
            <p className="font-medium">{MATCH_OUTCOME_LABELS[flag.outcome] ?? flag.outcome}</p>
            <p className="text-muted-foreground">
              Matched by a guardian email.{" "}
              {flag.studentMatched
                ? "The child matched by name and date of birth."
                : "The child is new to this family."}
            </p>
            {flag.matchedApplicationId && (
              <p>
                Earlier application:{" "}
                {flag.matchedVisible ? (
                  <Link
                    to="/admissions/$applicationId"
                    params={{ applicationId: flag.matchedApplicationId }}
                    className="font-mono underline"
                  >
                    {flag.matchedReference ?? "open"}
                  </Link>
                ) : (
                  <span className="text-muted-foreground">not in your scope</span>
                )}
              </p>
            )}
            {rows.length > 0 ? (
              <div>
                <p className="text-muted-foreground">
                  The parent sent these details, which differ from the record. The record was not
                  changed; update it yourself if they are right.
                </p>
                <table className="mt-2 w-full text-left text-sm">
                  <thead className="text-xs text-muted-foreground">
                    <tr>
                      <th className="py-1 pr-3 font-normal">Who</th>
                      <th className="py-1 pr-3 font-normal">Field</th>
                      <th className="py-1 font-normal">Submitted</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((r, i) => (
                      <tr key={i} className="border-t align-top">
                        <td className="py-1 pr-3">{r.who}</td>
                        <td className="py-1 pr-3">{r.field}</td>
                        <td className="break-all py-1">{r.submitted}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : (
              <p className="text-muted-foreground">The submitted details match the record.</p>
            )}
          </div>
        )}
      </div>
    </section>
  );
}
