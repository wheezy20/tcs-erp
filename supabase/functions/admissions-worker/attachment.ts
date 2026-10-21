// The one file the worker attaches (slice 13, D-13k): the Admissions
// Overview and Fees PDF, uploaded once by Eyram to a private bucket. The
// bucket and path are constants here, never read from an outbox row, so
// no row can make the worker attach anything else.
//
//   readPdfGate  GET /object/authenticated/<bucket>/<path> with the service
//                role key, reading at most MAX_ATTACHMENT_BYTES (a larger
//                file is refused, not cut), 15 second timeout. Throws on a
//                missing file or any error.
//   pdfAttachment  checks the bytes start with %PDF- and encodes them as
//                base64 for Resend. Throws on anything else.
//
// A throw means the worker sends nothing for that email and retries it
// with error class config, so a missing file shows on the staff email
// health page instead of an email that says "attached" with nothing
// attached. No Deno globals and no npm imports, like handler.ts.

export const ATTACHMENT_BUCKET = "admissions-attachments";
export const PDF_GATE_PATH = "pdf-gate/admissions-overview-and-fees.pdf";
export const PDF_GATE_FILENAME = "TCS-Admissions-Overview-and-Fees.pdf";
export const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;
export const READ_TIMEOUT_MS = 15_000;

export type Attachment = { filename: string; content: string };

export function makePdfGateReader(
  fetchImpl: typeof fetch,
  supabaseUrl: string,
  serviceRoleKey: string,
): () => Promise<Uint8Array> {
  return async () => {
    const res = await fetchImpl(
      `${supabaseUrl}/storage/v1/object/authenticated/${ATTACHMENT_BUCKET}/${PDF_GATE_PATH}`,
      {
        method: "GET",
        headers: { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` },
        signal: AbortSignal.timeout(READ_TIMEOUT_MS),
      },
    );
    if (res.status !== 200 || !res.body) {
      await res.body?.cancel().catch(() => {});
      throw new Error(`read answered ${res.status}`);
    }
    const declared = res.headers.get("content-length");
    if (declared !== null && Number(declared) > MAX_ATTACHMENT_BYTES) {
      await res.body.cancel().catch(() => {});
      throw new Error("too large");
    }
    const reader = res.body.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_ATTACHMENT_BYTES) {
        await reader.cancel().catch(() => {});
        throw new Error("too large");
      }
      chunks.push(value);
    }
    const all = new Uint8Array(total);
    let off = 0;
    for (const c of chunks) {
      all.set(c, off);
      off += c.byteLength;
    }
    return all;
  };
}

/** The PDF as Resend wants it. Throws unless it is a PDF of at most
 * MAX_ATTACHMENT_BYTES. */
export function pdfAttachment(bytes: Uint8Array): Attachment {
  const sig = [0x25, 0x50, 0x44, 0x46, 0x2d]; // %PDF-
  if (bytes.length < sig.length || !sig.every((b, i) => bytes[i] === b))
    throw new Error("not a PDF");
  if (bytes.length > MAX_ATTACHMENT_BYTES) throw new Error("too large");
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return { filename: PDF_GATE_FILENAME, content: btoa(binary) };
}
