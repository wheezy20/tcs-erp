// Pure helpers for how staff get application files (admissions slice 9a).
// No Supabase, no React. Files come from strangers, so staff always
// download them through a signed URL that forces a download (attachment
// disposition); nothing is ever opened inline in the app's own tab or a
// new one.

export const FEE_PROOF = "application_fee_proof";

/** The note staff see next to the fee proof (D-9e). */
export const FEE_PROOF_NOTE =
  "Match this proof of payment (bank deposit slip, GIP confirmation or mobile money receipt) against the bank or mobile money record before treating the application fee as paid.";

/** A file name built only from database values: the application reference
 * (or "application"), the document type, and the stored extension. */
export function documentDownloadName(
  reference: string | null | undefined,
  documentType: string,
  storagePath: string,
): string {
  const ext = /\.(pdf|jpg|jpeg|png)$/i.exec(storagePath)?.[1]?.toLowerCase() ?? "bin";
  const ref =
    reference && /^(APP|INQ)-[0-9]{4}-[0-9]{4,}$/.test(reference) ? reference : "application";
  const type = /^[a-z_]+$/.test(documentType) ? documentType : "document";
  return `${ref}-${type}.${ext}`;
}

/** The options for createSignedUrl: always a forced download. */
export function signedDownloadOptions(fileName: string): { download: string } {
  return { download: fileName };
}

/** Fee proof first, then the rest in their existing order. */
export function feeProofFirst<T extends { documentType: string }>(docs: T[]): T[] {
  return [
    ...docs.filter((d) => d.documentType === FEE_PROOF),
    ...docs.filter((d) => d.documentType !== FEE_PROOF),
  ];
}
