import { supabase } from "@/lib/supabase";
import {
  interpretSubmitResponse,
  parsePublicOptions,
  type PublicOptions,
  type SubmitOutcome,
} from "@/modules/admissions/inquiry-form";

// The public Inquiry form's two calls (admissions slice 8). Neither needs a
// session: the options come from the one anon-executable function,
// get_public_admissions_options(), and the submit goes to the
// admissions-public Edge Function, which holds the only key that can call
// submit_inquiry. Nothing secret is sent from here: the request carries the
// form, the Turnstile token and no Authorization header.

/** Active grades, campuses with their accepted grades, active years and
 * whether intake is open. */
export async function getPublicAdmissionsOptions(): Promise<PublicOptions> {
  const { data, error } = await supabase.rpc("get_public_admissions_options");
  if (error) throw error;
  return parsePublicOptions(data);
}

function functionUrl(): string {
  return `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/admissions-public`;
}

export async function submitInquiry(
  turnstileToken: string,
  payload: Record<string, unknown>,
): Promise<SubmitOutcome> {
  let res: Response;
  try {
    res = await fetch(functionUrl(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "inquiry", turnstile_token: turnstileToken, payload }),
    });
  } catch {
    return interpretSubmitResponse(0, null);
  }
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  return interpretSubmitResponse(res.status, body);
}
