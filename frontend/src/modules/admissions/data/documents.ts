import { supabase } from "@/lib/supabase";

/** How long a document link works (D-4h). */
export const DOCUMENT_URL_SECONDS = 300;

/** Opens one document in a new tab through a freshly signed link. The link
 * is created on click and lives only in this function: never in React
 * state, a store, a cache, the DOM or a log. The storage path is re-read by
 * document id, so visibility is re-checked by RLS on every click.
 *
 * The tab is opened synchronously, before any await, so a popup blocker
 * treats it as part of the click; its opener is cleared before it's sent
 * anywhere. */
export async function openApplicationDocument(documentId: string): Promise<void> {
  const tab = window.open("", "_blank");
  if (!tab) throw new Error("Your browser blocked the new tab. Allow pop-ups for this site.");
  tab.opener = null;
  try {
    const { data, error } = await supabase
      .from("application_documents")
      .select("storage_path")
      .eq("id", documentId)
      .maybeSingle();
    if (error) throw error;
    if (!data?.storage_path) throw new Error("No file has been uploaded for this document.");
    const { data: signed, error: signError } = await supabase.storage
      .from("admissions-documents")
      .createSignedUrl(data.storage_path, DOCUMENT_URL_SECONDS);
    if (signError) throw signError;
    tab.location.replace(signed.signedUrl);
  } catch (err) {
    tab.close();
    throw err;
  }
}
