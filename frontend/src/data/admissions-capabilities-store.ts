import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";
import { getErrorMessage } from "@/lib/utils";

// Admissions access per staff member (20261005100000). The database is the
// authority: staff_admissions_capabilities is select-only, RLS returns every
// row to a Manager or Auditor and only the caller's own row to everyone else,
// and writes go through set_admissions_capabilities() (active Manager only),
// which also enforces who may hold what. No row means nothing granted.
// Deliberately separate from staff-store.ts, so a failure here (or a frontend
// deployed before the migration) can't take the Staff list down with it.

type CapabilityRow = Database["public"]["Tables"]["staff_admissions_capabilities"]["Row"];
type GradeRow = Database["public"]["Tables"]["admissions_grades"]["Row"];

export type GradeBand = "preschool" | "primary" | "jhs";
export const GRADE_BANDS: GradeBand[] = ["preschool", "primary", "jhs"];

export type AdmissionsCapabilities = {
  staffId: string;
  canDecide: boolean;
  canViewHealth: boolean;
  gradeBands: GradeBand[];
  allGrades: boolean;
};

function mapRow(row: CapabilityRow): AdmissionsCapabilities {
  return {
    staffId: row.staff_id,
    canDecide: row.can_decide,
    canViewHealth: row.can_view_health,
    gradeBands: row.grade_bands as GradeBand[],
    allGrades: row.all_grades,
  };
}

// ------------------------------------------------------------ capabilities

type State = {
  byStaffId: Map<string, AdmissionsCapabilities>;
  loading: boolean;
  error: string | null;
};

let state: State = { byStaffId: new Map(), loading: true, error: null };
let loadPromise: Promise<void> | null = null;
let generation = 0;
const listeners = new Set<() => void>();

function setState(next: State) {
  state = next;
  listeners.forEach((l) => l());
}

async function load(gen: number) {
  const { data, error } = await supabase.from("staff_admissions_capabilities").select("*");
  if (error) throw error;
  if (gen !== generation) return;
  setState({
    byStaffId: new Map(data.map((row) => [row.staff_id, mapRow(row)])),
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    const gen = generation;
    loadPromise = load(gen).catch((err) => {
      if (gen !== generation) return;
      loadPromise = null;
      setState({
        ...state,
        loading: false,
        error: getErrorMessage(err, "Could not load admissions access."),
      });
      throw err;
    });
  }
  return loadPromise;
}

export async function reloadAdmissionsCapabilities() {
  loadPromise = null;
  await ensureLoaded();
}

// What the caller may read depends on who is signed in, so when the signed-in
// user changes (a different user signs in, or everyone signs out) the previous
// user's copy is dropped. Supabase also emits SIGNED_IN when a tab regains
// focus with the same session, so the user id is compared, not the event.
// The generation counter discards a load that was started for the previous
// user and finishes late.
let watchingAuth = false;
let lastUserId: string | null | undefined;
function watchAuth() {
  if (watchingAuth) return;
  watchingAuth = true;
  supabase.auth.onAuthStateChange((_event, session) => {
    const userId = session?.user?.id ?? null;
    if (lastUserId === undefined) {
      lastUserId = userId;
      return;
    }
    if (userId === lastUserId) return;
    lastUserId = userId;
    generation += 1;
    loadPromise = null;
    setState({ byStaffId: new Map(), loading: true, error: null });
    if (listeners.size > 0) ensureLoaded().catch(() => {});
  });
}

function subscribe(listener: () => void) {
  watchAuth();
  listeners.add(listener);
  ensureLoaded().catch(() => {});
  return () => listeners.delete(listener);
}

function getSnapshot() {
  return state;
}

/** Rows the caller may read: all of them for a Manager or Auditor, otherwise
 * only the caller's own. A missing entry is "nothing granted" only for rows
 * the caller can see; see canSeeAllAdmissionsCapabilities(). */
export function useAdmissionsCapabilities() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

export async function setAdmissionsCapabilities(
  staffId: string,
  value: Omit<AdmissionsCapabilities, "staffId">,
): Promise<void> {
  const { error } = await supabase.rpc("set_admissions_capabilities", {
    p_staff_id: staffId,
    p_can_decide: value.canDecide,
    p_can_view_health: value.canViewHealth,
    p_grade_bands: value.gradeBands,
    p_all_grades: value.allGrades,
  });
  if (error) throw error;
  // The write is committed; a failed refresh shouldn't report it as failed.
  await reloadAdmissionsCapabilities().catch(() => {});
}

// ------------------------------------------------------------ grades

type GradesState = { grades: GradeRow[]; loading: boolean; error: string | null };

let gradesState: GradesState = { grades: [], loading: true, error: null };
const gradesListeners = new Set<() => void>();
let gradesPromise: Promise<void> | null = null;

function setGradesState(next: GradesState) {
  gradesState = next;
  gradesListeners.forEach((l) => l());
}

function ensureGradesLoaded() {
  if (!gradesPromise) {
    gradesPromise = (async () => {
      const { data, error } = await supabase
        .from("admissions_grades")
        .select("*")
        .order("position");
      if (error) throw error;
      setGradesState({ grades: data, loading: false, error: null });
    })().catch((err) => {
      gradesPromise = null;
      setGradesState({
        ...gradesState,
        loading: false,
        error: getErrorMessage(err, "Could not load admissions grades."),
      });
    });
  }
  return gradesPromise;
}

/** The admissions grade list (readable by Manager, Auditor and Admissions
 * Officer). Used for band labels, so they come from the same rows the
 * database resolves bands from. */
export function useAdmissionsGrades() {
  return useSyncExternalStore(
    (listener) => {
      gradesListeners.add(listener);
      ensureGradesLoaded();
      return () => gradesListeners.delete(listener);
    },
    () => gradesState,
    () => gradesState,
  );
}

/** "Pre Nursery – Kindergarten 2" for a band, from the grade rows. */
export function bandRangeLabel(grades: GradeRow[], band: GradeBand): string {
  const inBand = grades.filter((g) => g.band === band);
  if (inBand.length === 0) return "";
  return inBand.length === 1
    ? inBand[0].name
    : `${inBand[0].name} – ${inBand[inBand.length - 1].name}`;
}

export const BAND_LABELS: Record<GradeBand, string> = {
  preschool: "Preschool",
  primary: "Primary",
  jhs: "JHS",
};

/** One-line summary, e.g. "Decide · Health · Primary, JHS". */
export function summarizeCapabilities(caps: AdmissionsCapabilities | undefined): string {
  if (!caps) return "None";
  const parts: string[] = [];
  if (caps.canDecide) parts.push("Decide");
  if (caps.canViewHealth) parts.push("Health");
  if (caps.allGrades) parts.push("All grades");
  else if (caps.gradeBands.length > 0)
    parts.push(
      GRADE_BANDS.filter((b) => caps.gradeBands.includes(b))
        .map((b) => BAND_LABELS[b])
        .join(", "),
    );
  return parts.join(" · ");
}
