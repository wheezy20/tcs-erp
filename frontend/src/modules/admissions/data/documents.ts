import { supabase } from "@/lib/supabase";
import { documentDownloadName, signedDownloadOptions } from "@/modules/admissions/document-files";

/** How long a document link works (D-4h). */
export const DOCUMENT_URL_SECONDS = 300;

/** Downloads one document through a freshly signed link that forces a
 * download (attachment disposition, slice 9a): the file is never shown
 * inline, in this tab or another. The link is created on click and lives
 * only in this function: never in React state, a store, a cache, the DOM
 * after the click, or a log. The storage path is re-read by document id,
 * so visibility is re-checked by RLS on every click. */
export async function downloadApplicationDocument(documentId: string): Promise<void> {
  const { data, error } = await supabase
    .from("application_documents")
    .select("storage_path, document_type, application:applications(application_reference)")
    .eq("id", documentId)
    .maybeSingle();
  if (error) throw error;
  if (!data?.storage_path) throw new Error("No file has been uploaded for this document.");
  const name = documentDownloadName(
    data.application?.application_reference,
    data.document_type,
    data.storage_path,
  );
  const { data: signed, error: signError } = await supabase.storage
    .from("admissions-documents")
    .createSignedUrl(data.storage_path, DOCUMENT_URL_SECONDS, signedDownloadOptions(name));
  if (signError) throw signError;
  const a = document.createElement("a");
  a.href = signed.signedUrl;
  a.download = name;
  a.rel = "noopener noreferrer";
  document.body.appendChild(a);
  a.click();
  a.remove();
}
