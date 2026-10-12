import { useAuth } from "@/data/auth-store";
import { useAdmissionsCapabilities } from "@/data/admissions-capabilities-store";
import type { OwnCapabilities } from "@/modules/admissions/permissions";

/** The signed-in user's role and own admissions capabilities, for deciding
 * which controls to show. The database re-checks everything. */
export function useAdmissionsAccess() {
  const { staff } = useAuth();
  const { byStaffId, loading } = useAdmissionsCapabilities();
  const own = staff ? byStaffId.get(staff.id) : undefined;
  const caps: OwnCapabilities | undefined = own
    ? { gradeBands: own.gradeBands, allGrades: own.allGrades }
    : undefined;
  return {
    staffId: staff?.id ?? null,
    role: staff?.role,
    caps,
    capsLoading: loading,
  };
}
