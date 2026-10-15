import { supabase } from "@/lib/supabase";
import {
  interpretApplicationResponse,
  type ApplicationOutcome,
  type UploadedFile,
} from "@/modules/admissions/application-form";

// The plain public Application form's calls (admissions slice 9a). None
// needs a session. Everything goes to the admissions-public Edge Function,
// which holds the only key that can call the upload and submit RPCs; the
// one exception is the file itself, which goes straight to Storage with
// the single-use, single-path upload token the function signed. Nothing
// secret is sent from here.

const BUCKET = "admissions-documents";

function functionUrl(): string {
  return `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/admissions-public`;
}

type Answer = { status: number; body: unknown };

async function call(body: unknown): Promise<Answer> {
  try {
    const res = await fetch(functionUrl(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    let parsed: unknown = null;
    try {
      parsed = await res.json();
    } catch {
      parsed = null;
    }
    return { status: res.status, body: parsed };
  } catch {
    return { status: 0, body: null };
  }
}

function errorOf(a: Answer, fallback: string): string {
  const b = a.body as { error?: unknown } | null;
  return b && typeof b.error === "string" && b.error.trim() !== "" ? b.error : fallback;
}

export type SessionResult =
  { ok: true; sessionToken: string } | { ok: false; closed: boolean; message: string };

/** One Turnstile solve (action "upload") opens the upload session. */
export async function openUploadSession(
  turnstileToken: string,
  fallback: string,
): Promise<SessionResult> {
  const a = await call({ action: "upload_session", turnstile_token: turnstileToken });
  const b = a.body as { session_token?: unknown } | null;
  if (a.status === 200 && b && typeof b.session_token === "string") {
    return { ok: true, sessionToken: b.session_token };
  }
  return { ok: false, closed: a.status === 409, message: errorOf(a, fallback) };
}

/** Reserves a path for one file, then uploads the file to exactly that
 * path. Resolves with what submit needs, or throws with a message for the
 * parent. */
export async function uploadDocument(
  sessionToken: string,
  documentType: string,
  file: File,
  extension: string,
  contentType: string,
  fallback: string,
): Promise<UploadedFile> {
  const a = await call({
    action: "upload_url",
    payload: {
      session_token: sessionToken,
      document_type: documentType,
      extension,
      size: file.size,
    },
  });
  const b = a.body as { reservation_id?: unknown; path?: unknown; upload_token?: unknown } | null;
  if (
    a.status !== 200 ||
    !b ||
    typeof b.reservation_id !== "string" ||
    typeof b.path !== "string" ||
    typeof b.upload_token !== "string"
  ) {
    throw new Error(errorOf(a, fallback));
  }
  const { error } = await supabase.storage
    .from(BUCKET)
    .uploadToSignedUrl(b.path, b.upload_token, file, { contentType, upsert: false });
  if (error) {
    throw new Error(
      "That file couldn't be uploaded. Check it is a PDF, JPG or PNG of 10 MB or less.",
    );
  }
  return { reservationId: b.reservation_id, path: b.path, fileName: file.name };
}

/** The final submit: a second Turnstile solve (action "application"). */
export async function submitApplication(
  turnstileToken: string,
  sessionToken: string,
  payload: Record<string, unknown>,
): Promise<ApplicationOutcome> {
  const a = await call({
    action: "application",
    turnstile_token: turnstileToken,
    session_token: sessionToken,
    payload,
  });
  return interpretApplicationResponse(a.status, a.body);
}
