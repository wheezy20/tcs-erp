import { useEffect, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowLeft, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import {
  AdjustPayFields,
  PaymentDestinationFields,
  payOverrideFrom,
  type PayOverride,
} from "@/components/employees/payment-fields";
import { RefListSelect } from "@/components/employees/ref-list-select";
import { RejectButton } from "@/components/employees/reject-reason-dialog";
import { actionLabel, summarizeAuditEntry, useEmployeeAuditHistory } from "@/data/audit-history";
import { canWriteFinancials, useAuth } from "@/data/auth-store";
import { currency } from "@/data/dashboard";
import {
  approveEmployee,
  approvePayConfig,
  configHistoryFor,
  currentConfigFor,
  pendingConfigFor,
  proposePayConfigChange,
  rejectEmployee,
  rejectPayConfig,
  setEmployeeStatus,
  setPayConfigExemptions,
  setStandingAllowances,
  standingAllowancesFor,
  updateEmployeeProfile,
  useEmployees,
  withdrawPayConfigProposal,
  type Employee,
  type EmploymentType,
  type PayConfig,
  type PaymentMethod,
} from "@/data/employees-store";
import {
  deleteEmployeeDocument,
  listEmployeeDocuments,
  uploadEmployeeDocument,
  DOCUMENT_TYPES,
  type DocumentType,
  type EmployeeDocument,
} from "@/data/employee-documents-store";
import { activeNames, useDepartments, usePositions } from "@/data/org-lists-store";
import { usePayroll, type AllowanceType } from "@/data/payroll-store";
import { useStaff } from "@/data/staff-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/employees/$employeeId")({
  head: () => ({ meta: [{ title: "Employee — TCS" }] }),
  component: EmployeeProfilePage,
});

const firstOfNextMonth = () => {
  const d = new Date();
  return `${new Date(Date.UTC(d.getFullYear(), d.getMonth() + 1, 1)).toISOString().slice(0, 7)}-01`;
};

function EmployeeProfilePage() {
  const { employeeId } = Route.useParams();
  const { staff: currentStaff } = useAuth();
  const canWrite = canWriteFinancials(currentStaff?.role);
  const isManager = currentStaff?.role === "Manager";
  const { employees, configs, allowances, loading } = useEmployees();
  const { allowanceTypes } = usePayroll();
  const { staff: roster } = useStaff();

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  const emp = employees.find((e) => e.id === employeeId);
  if (!emp) {
    return (
      <>
        <BackLink />
        <PageHeader title="Employee not found" description={`No record matches ${employeeId}.`} />
      </>
    );
  }

  const current = currentConfigFor(configs, emp.id);
  const pending = pendingConfigFor(configs, emp.id);
  const history = configHistoryFor(configs, emp.id);
  const standing = standingAllowancesFor(allowances, emp.id);
  const login = roster.find((s) => s.employeeId === emp.id);
  const staffName = (id: string | null) =>
    id ? (roster.find((s) => s.id === id)?.name ?? "Unknown") : null;

  return (
    <>
      <BackLink />
      <PageHeader
        title={emp.name}
        description={[emp.position, emp.department].filter(Boolean).join(" · ") || "No placement"}
      />

      <div className="mb-6 flex flex-wrap items-center gap-2">
        <Badge
          variant={
            emp.status === "Active"
              ? "secondary"
              : emp.status === "Rejected"
                ? "destructive"
                : "outline"
          }
        >
          {emp.status}
        </Badge>
        {login && <Badge variant="outline">Login: {login.email}</Badge>}
      </div>

      {emp.status === "Rejected" && (
        <div className="mb-6 rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm">
          <span className="font-semibold text-destructive">This record was rejected</span>
          {emp.rejectionReason ? ` — ${emp.rejectionReason}` : ""}. It can't be paid or edited.
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <ProfileForm key={emp.id} emp={emp} canWrite={canWrite && emp.status !== "Rejected"} />

          <HrDetailsSection
            key={`hr-${emp.id}`}
            emp={emp}
            canWrite={canWrite && emp.status !== "Rejected"}
          />

          <DocumentsSection
            key={`docs-${emp.id}`}
            employeeId={emp.id}
            canWrite={canWrite && emp.status !== "Rejected"}
          />

          <PayConfigSection
            emp={emp}
            current={current}
            pending={pending}
            canWrite={canWrite}
            isManager={isManager}
            staffName={staffName}
          />

          {emp.status === "Active" && (
            <StandingAllowancesSection
              employeeId={emp.id}
              allowanceTypes={allowanceTypes}
              standing={standing}
              canWrite={canWrite}
            />
          )}

          {history.length > 0 && <HistoryTable rows={history} />}

          <HistorySection
            employeeId={emp.id}
            configIds={configs.filter((c) => c.employeeId === emp.id).map((c) => c.id)}
          />
        </div>

        <div className="space-y-6">
          <StatusCard emp={emp} pending={pending} canWrite={canWrite} isManager={isManager} />
          <section className="card-surface p-6">
            <h2 className="text-sm font-semibold">Linked login</h2>
            {login ? (
              <p className="mt-3 text-sm">
                <Link
                  to="/staff/$staffId"
                  params={{ staffId: login.id }}
                  className="font-medium text-primary hover:underline"
                >
                  {login.name}
                </Link>{" "}
                · {login.role}
              </p>
            ) : (
              <p className="mt-3 text-sm text-muted-foreground">
                No ERP login. This person is paid but can't sign in.
              </p>
            )}
          </section>
        </div>
      </div>
    </>
  );
}

/* --------------------------------------------------------- profile form */

function ProfileForm({ emp, canWrite }: { emp: Employee; canWrite: boolean }) {
  const { items: positions } = usePositions();
  const { items: departments } = useDepartments();
  const [phone, setPhone] = useState(emp.phone ?? "");
  const [position, setPosition] = useState(emp.position ?? "");
  const [department, setDepartment] = useState(emp.department ?? "");
  const [saving, setSaving] = useState(false);

  const dirty =
    phone !== (emp.phone ?? "") ||
    position !== (emp.position ?? "") ||
    department !== (emp.department ?? "");

  async function save() {
    setSaving(true);
    try {
      await updateEmployeeProfile(emp.id, { phone, position, department });
      toast.success("Profile updated");
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not save."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">Contact &amp; placement</h2>
      <p className="mt-1 text-sm text-muted-foreground">
        {canWrite ? "Direct edit — no approval needed." : "Read-only for your role."}
      </p>
      <div className="mt-5 grid gap-5 sm:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor="e-phone">Phone</Label>
          <Input
            id="e-phone"
            value={phone}
            disabled={!canWrite}
            maxLength={40}
            onChange={(e) => setPhone(e.target.value)}
          />
        </div>
        <div />
        <div className="space-y-2">
          <Label>Position</Label>
          <RefListSelect
            options={activeNames(positions)}
            value={position}
            onChange={setPosition}
            placeholder="Select position"
            disabled={!canWrite}
          />
        </div>
        <div className="space-y-2">
          <Label>Department</Label>
          <RefListSelect
            options={activeNames(departments)}
            value={department}
            onChange={setDepartment}
            placeholder="Select department"
            disabled={!canWrite}
          />
        </div>
      </div>
      {canWrite && (
        <div className="mt-6">
          <Button onClick={save} disabled={!dirty || saving}>
            {saving ? "Saving…" : "Save changes"}
          </Button>
        </div>
      )}
    </section>
  );
}

const EMPLOYMENT_TYPES: EmploymentType[] = [
  "Full-Time",
  "Part-Time",
  "Contract",
  "Volunteer",
  "Intern",
];

/** A separate card/save from ProfileForm's phone/position/department —
 * this one saves independently via updateEmployeeProfile()'s optional
 * trailing HR-details params, which leave phone/position/department
 * exactly as they are (the RPC always re-sets them to their current
 * value here, never touching what ProfileForm owns). No approval gate,
 * same as ProfileForm — every field is a plain current-state fact. Bank
 * details and salary are deliberately not here — those stay in
 * PayConfigSection below, approval-gated. */
function HrDetailsSection({ emp, canWrite }: { emp: Employee; canWrite: boolean }) {
  const [dateOfBirth, setDateOfBirth] = useState(emp.dateOfBirth ?? "");
  const [gender, setGender] = useState(emp.gender ?? "");
  const [preferredName, setPreferredName] = useState(emp.preferredName ?? "");
  const [nationalId, setNationalId] = useState(emp.nationalId ?? "");
  const [personalEmail, setPersonalEmail] = useState(emp.personalEmail ?? "");
  const [schoolEmail, setSchoolEmail] = useState(emp.schoolEmail ?? "");
  const [employmentType, setEmploymentType] = useState(emp.employmentType ?? "");
  const [startDate, setStartDate] = useState(emp.startDate ?? "");
  const [probationEndDate, setProbationEndDate] = useState(emp.probationEndDate ?? "");
  const [contractEndDate, setContractEndDate] = useState(emp.contractEndDate ?? "");
  const [emergencyContactName, setEmergencyContactName] = useState(emp.emergencyContactName ?? "");
  const [emergencyContactPhone, setEmergencyContactPhone] = useState(
    emp.emergencyContactPhone ?? "",
  );
  const [residentialAddress, setResidentialAddress] = useState(emp.residentialAddress ?? "");
  const [qualifications, setQualifications] = useState(emp.qualifications ?? "");
  const [ssnitNumber, setSsnitNumber] = useState(emp.ssnitNumber ?? "");
  const [tinNumber, setTinNumber] = useState(emp.tinNumber ?? "");
  const [churchDenomination, setChurchDenomination] = useState(emp.churchDenomination ?? "");
  const [saving, setSaving] = useState(false);

  const current = {
    dateOfBirth,
    gender,
    preferredName,
    nationalId,
    personalEmail,
    schoolEmail,
    employmentType,
    startDate,
    probationEndDate,
    contractEndDate,
    emergencyContactName,
    emergencyContactPhone,
    residentialAddress,
    qualifications,
    ssnitNumber,
    tinNumber,
    churchDenomination,
  };
  const original = {
    dateOfBirth: emp.dateOfBirth ?? "",
    gender: emp.gender ?? "",
    preferredName: emp.preferredName ?? "",
    nationalId: emp.nationalId ?? "",
    personalEmail: emp.personalEmail ?? "",
    schoolEmail: emp.schoolEmail ?? "",
    employmentType: emp.employmentType ?? "",
    startDate: emp.startDate ?? "",
    probationEndDate: emp.probationEndDate ?? "",
    contractEndDate: emp.contractEndDate ?? "",
    emergencyContactName: emp.emergencyContactName ?? "",
    emergencyContactPhone: emp.emergencyContactPhone ?? "",
    residentialAddress: emp.residentialAddress ?? "",
    qualifications: emp.qualifications ?? "",
    ssnitNumber: emp.ssnitNumber ?? "",
    tinNumber: emp.tinNumber ?? "",
    churchDenomination: emp.churchDenomination ?? "",
  };
  const dirty = Object.keys(current).some(
    (k) => current[k as keyof typeof current] !== original[k as keyof typeof original],
  );

  async function save() {
    setSaving(true);
    try {
      await updateEmployeeProfile(
        emp.id,
        { phone: emp.phone ?? "", position: emp.position ?? "", department: emp.department ?? "" },
        {
          dateOfBirth: dateOfBirth || undefined,
          gender,
          preferredName,
          nationalId,
          personalEmail,
          schoolEmail,
          employmentType: (employmentType || undefined) as EmploymentType | undefined,
          startDate: startDate || undefined,
          probationEndDate: probationEndDate || undefined,
          contractEndDate: contractEndDate || undefined,
          emergencyContactName,
          emergencyContactPhone,
          residentialAddress,
          qualifications,
          ssnitNumber,
          tinNumber,
          churchDenomination,
        },
      );
      toast.success("HR details updated");
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not save."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">HR details</h2>
      <p className="mt-1 text-sm text-muted-foreground">
        {canWrite ? "Direct edit — no approval needed." : "Read-only for your role."}
      </p>

      <div className="mt-5 grid gap-5 sm:grid-cols-2">
        <div className="space-y-2">
          <Label>Preferred name</Label>
          <Input
            value={preferredName}
            disabled={!canWrite}
            onChange={(e) => setPreferredName(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>Gender</Label>
          <Input value={gender} disabled={!canWrite} onChange={(e) => setGender(e.target.value)} />
        </div>
        <div className="space-y-2">
          <Label>Date of birth</Label>
          <Input
            type="date"
            value={dateOfBirth}
            disabled={!canWrite}
            onChange={(e) => setDateOfBirth(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>National ID number</Label>
          <Input
            value={nationalId}
            disabled={!canWrite}
            onChange={(e) => setNationalId(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>Personal email</Label>
          <Input
            type="email"
            value={personalEmail}
            disabled={!canWrite}
            onChange={(e) => setPersonalEmail(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>School email</Label>
          <Input
            type="email"
            value={schoolEmail}
            disabled={!canWrite}
            onChange={(e) => setSchoolEmail(e.target.value)}
          />
        </div>

        <div className="space-y-2">
          <Label>Employment type</Label>
          <Select
            value={employmentType || undefined}
            onValueChange={setEmploymentType}
            disabled={!canWrite}
          >
            <SelectTrigger>
              <SelectValue placeholder="Select employment type" />
            </SelectTrigger>
            <SelectContent>
              {EMPLOYMENT_TYPES.map((t) => (
                <SelectItem key={t} value={t}>
                  {t}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div />
        <div className="space-y-2">
          <Label>Start date</Label>
          <Input
            type="date"
            value={startDate}
            disabled={!canWrite}
            onChange={(e) => setStartDate(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>Probation end date</Label>
          <Input
            type="date"
            value={probationEndDate}
            disabled={!canWrite}
            onChange={(e) => setProbationEndDate(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>Contract end date</Label>
          <Input
            type="date"
            value={contractEndDate}
            disabled={!canWrite}
            onChange={(e) => setContractEndDate(e.target.value)}
          />
        </div>
        <div />

        <div className="space-y-2">
          <Label>Emergency contact name</Label>
          <Input
            value={emergencyContactName}
            disabled={!canWrite}
            onChange={(e) => setEmergencyContactName(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>Emergency contact phone</Label>
          <Input
            value={emergencyContactPhone}
            disabled={!canWrite}
            onChange={(e) => setEmergencyContactPhone(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>SSNIT number</Label>
          <Input
            value={ssnitNumber}
            disabled={!canWrite}
            onChange={(e) => setSsnitNumber(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>TIN number</Label>
          <Input
            value={tinNumber}
            disabled={!canWrite}
            onChange={(e) => setTinNumber(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>Church / denomination</Label>
          <Input
            value={churchDenomination}
            disabled={!canWrite}
            onChange={(e) => setChurchDenomination(e.target.value)}
          />
        </div>
        <div />

        <div className="space-y-2 sm:col-span-2">
          <Label>Residential address</Label>
          <Textarea
            value={residentialAddress}
            disabled={!canWrite}
            rows={2}
            onChange={(e) => setResidentialAddress(e.target.value)}
          />
        </div>
        <div className="space-y-2 sm:col-span-2">
          <Label>Qualifications</Label>
          <Textarea
            value={qualifications}
            disabled={!canWrite}
            rows={2}
            onChange={(e) => setQualifications(e.target.value)}
          />
        </div>
      </div>

      {canWrite && (
        <div className="mt-6">
          <Button onClick={save} disabled={!dirty || saving}>
            {saving ? "Saving…" : "Save changes"}
          </Button>
        </div>
      )}
    </section>
  );
}

function DocumentsSection({ employeeId, canWrite }: { employeeId: string; canWrite: boolean }) {
  const [docs, setDocs] = useState<EmployeeDocument[]>([]);
  const [loading, setLoading] = useState(true);
  const [documentType, setDocumentType] = useState<DocumentType>(DOCUMENT_TYPES[0]);
  const [file, setFile] = useState<File | null>(null);
  const [notes, setNotes] = useState("");
  const [uploading, setUploading] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  async function refresh() {
    try {
      setDocs(await listEmployeeDocuments(employeeId));
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not load documents."));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [employeeId]);

  async function upload() {
    if (!file) return;
    setUploading(true);
    try {
      await uploadEmployeeDocument(employeeId, documentType, file, notes);
      setFile(null);
      setNotes("");
      toast.success("Document uploaded");
      await refresh();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not upload document."));
    } finally {
      setUploading(false);
    }
  }

  async function remove(doc: EmployeeDocument) {
    setDeletingId(doc.id);
    try {
      await deleteEmployeeDocument(doc);
      toast.success("Document deleted");
      await refresh();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not delete document."));
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">Documents</h2>
      <p className="mt-1 text-sm text-muted-foreground">
        National ID, certificates, photo. Stored privately — links below are time-limited signed
        URLs, never a public link.
      </p>

      {canWrite && (
        <div className="mt-5 grid gap-3 sm:grid-cols-[160px_1fr_1fr_auto] sm:items-end">
          <div className="space-y-2">
            <Label>Type</Label>
            <Select value={documentType} onValueChange={(v) => setDocumentType(v as DocumentType)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {DOCUMENT_TYPES.map((t) => (
                  <SelectItem key={t} value={t}>
                    {t}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>File</Label>
            <Input
              type="file"
              accept="image/jpeg,image/png,image/webp,application/pdf"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            />
          </div>
          <div className="space-y-2">
            <Label>Notes (optional)</Label>
            <Input value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>
          <Button onClick={upload} disabled={!file || uploading}>
            {uploading ? "Uploading…" : "Upload"}
          </Button>
        </div>
      )}

      <div className="mt-5 space-y-2">
        {loading && <p className="text-sm text-muted-foreground">Loading…</p>}
        {!loading && docs.length === 0 && (
          <p className="text-sm text-muted-foreground">No documents uploaded yet.</p>
        )}
        {docs.map((doc) => (
          <div
            key={doc.id}
            className="flex items-center justify-between gap-3 rounded-md border px-3 py-2 text-sm"
          >
            <div className="min-w-0">
              <div className="font-medium">{doc.documentType}</div>
              <div className="truncate text-xs text-muted-foreground">
                {new Date(doc.uploadedAt).toLocaleString()}
                {doc.uploadedByName ? ` · ${doc.uploadedByName}` : ""}
                {doc.notes ? ` · ${doc.notes}` : ""}
              </div>
            </div>
            <div className="flex shrink-0 items-center gap-2">
              {doc.signedUrl && (
                <a
                  href={doc.signedUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-primary underline underline-offset-2"
                >
                  View
                </a>
              )}
              {canWrite && (
                <Button
                  variant="ghost"
                  size="icon"
                  disabled={deletingId === doc.id}
                  onClick={() => remove(doc)}
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              )}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

/* ------------------------------------------------------ pay config */

function PayConfigSection({
  emp,
  current,
  pending,
  canWrite,
  isManager,
  staffName,
}: {
  emp: Employee;
  current: PayConfig | undefined;
  pending: PayConfig | undefined;
  canWrite: boolean;
  isManager: boolean;
  staffName: (id: string | null) => string | null;
}) {
  const [busy, setBusy] = useState(false);
  const [showPropose, setShowPropose] = useState(false);
  const [adjusting, setAdjusting] = useState(false);
  const [override, setOverride] = useState<PayOverride | null>(null);

  async function toggleExemption(next: { ssnit: boolean; tier2: boolean; paye: boolean }) {
    setBusy(true);
    try {
      await setPayConfigExemptions(emp.id, next.ssnit, next.tier2, next.paye);
      toast.success("Exemptions updated");
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not update exemptions."));
    } finally {
      setBusy(false);
    }
  }

  async function act(fn: () => Promise<void>, ok: string) {
    setBusy(true);
    try {
      await fn();
      toast.success(ok);
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not complete that."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="card-surface p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-sm font-semibold">Pay configuration</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Basic salary and bank details need Manager approval. Exemption flags are direct.
          </p>
        </div>
        {canWrite && emp.status === "Active" && !pending && (
          <Button size="sm" variant="outline" onClick={() => setShowPropose(true)}>
            Propose salary / bank change
          </Button>
        )}
      </div>

      {!current ? (
        emp.status === "Pending Approval" && pending ? (
          <div className="mt-4 rounded-lg border p-3 text-sm">
            <p className="font-medium">Proposed pay (part of this record)</p>
            <div className="mt-2 grid gap-x-6 gap-y-1 sm:grid-cols-2">
              <span>
                Basic salary: <strong>{currency(pending.basicSalary)}</strong>
              </span>
              <span>Effective from: {pending.effectiveFrom}</span>
              <span>Payment method: {pending.paymentMethod}</span>
              <span>
                {pending.paymentMethod === "Mobile Money" ? "Network" : "Bank"}:{" "}
                {pending.bank ?? "—"}
              </span>
              <span>
                {pending.paymentMethod === "Mobile Money" ? "Wallet number" : "Account"}:{" "}
                {pending.accountNo ?? "—"}
              </span>
            </div>
            <p className="mt-2 text-xs text-muted-foreground">
              Approved together with the employee record — one Approve / Reject, on the status card.
            </p>
          </div>
        ) : (
          <p className="mt-4 text-sm text-muted-foreground">
            No approved pay config yet.
            {emp.status === "Pending Approval"
              ? " It will be set when this record is approved."
              : ""}
          </p>
        )
      ) : (
        <dl className="mt-4 grid gap-x-6 gap-y-3 sm:grid-cols-2">
          <Field label="Basic salary" value={currency(current.basicSalary)} />
          <Field label="Effective from" value={current.effectiveFrom} />
          <Field label="Payment method" value={current.paymentMethod} />
          <div />
          <Field
            label={current.paymentMethod === "Mobile Money" ? "Mobile money network" : "Bank"}
            value={current.bank ?? "—"}
          />
          <Field
            label={current.paymentMethod === "Mobile Money" ? "Wallet number" : "Account number"}
            value={current.accountNo ?? "—"}
          />
        </dl>
      )}

      {current && (
        <div className="mt-4 rounded-lg border p-3">
          <p className="text-sm font-medium">Statutory deductions</p>
          <p className="mb-2 text-xs text-muted-foreground">
            Turn off for exempt staff (National Service etc.). Direct — no approval.
          </p>
          <ExemptRow
            label="Pays SSNIT (0.5% employee + 13% employer)"
            checked={current.paysSsnit}
            disabled={!canWrite || busy}
            onChange={(v) =>
              toggleExemption({ ssnit: v, tier2: current.paysTier2, paye: current.paysPaye })
            }
          />
          <ExemptRow
            label="Pays Tier 2 (5% employee)"
            checked={current.paysTier2}
            disabled={!canWrite || busy}
            onChange={(v) =>
              toggleExemption({ ssnit: current.paysSsnit, tier2: v, paye: current.paysPaye })
            }
          />
          <ExemptRow
            label="Pays PAYE (graduated)"
            checked={current.paysPaye}
            disabled={!canWrite || busy}
            onChange={(v) =>
              toggleExemption({ ssnit: current.paysSsnit, tier2: current.paysTier2, paye: v })
            }
          />
        </div>
      )}

      {pending && emp.status === "Active" && (
        <div className="mt-4 rounded-lg border border-amber-500/40 bg-amber-50/50 p-3 dark:bg-amber-950/20">
          <p className="text-sm font-medium text-amber-700 dark:text-amber-400">
            Pending salary / bank change
          </p>
          <p className="mt-1 text-xs text-muted-foreground">
            Proposed by {staffName(pending.proposedById) ?? "—"} · effective {pending.effectiveFrom}
            . The current config is unchanged until this is approved.
          </p>
          <div className="mt-2 grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
            <span>
              Basic salary: <strong>{currency(pending.basicSalary)}</strong>
              {current ? ` (was ${currency(current.basicSalary)})` : ""}
            </span>
            <span>
              {pending.paymentMethod === "Mobile Money" ? "Mobile Money" : "Bank"}:{" "}
              <strong>{pending.bank ?? "—"}</strong>
              {pending.accountNo ? ` · ${pending.accountNo}` : ""}
              {current && current.paymentMethod !== pending.paymentMethod
                ? ` (was ${current.paymentMethod})`
                : ""}
            </span>
          </div>
          {isManager && (
            <div className="mt-3">
              {!adjusting ? (
                <Button
                  type="button"
                  size="sm"
                  variant="ghost"
                  className="px-0"
                  onClick={() => {
                    setOverride(payOverrideFrom(pending));
                    setAdjusting(true);
                  }}
                >
                  Adjust before approving
                </Button>
              ) : (
                <div className="space-y-2 rounded-lg border p-3">
                  <div className="flex items-center justify-between">
                    <p className="text-xs font-medium text-muted-foreground">
                      Adjusting the proposed values — recorded as an amendment, separate from what
                      was proposed.
                    </p>
                    <Button
                      type="button"
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        setAdjusting(false);
                        setOverride(null);
                      }}
                    >
                      Cancel
                    </Button>
                  </div>
                  {override && <AdjustPayFields value={override} onChange={setOverride} />}
                </div>
              )}
            </div>
          )}
          <div className="mt-3 flex flex-wrap gap-2">
            {isManager && (
              <>
                <Button
                  size="sm"
                  disabled={busy}
                  onClick={() =>
                    act(
                      () =>
                        approvePayConfig(
                          pending.id,
                          adjusting && override
                            ? {
                                basicSalary: Number(override.basicSalary) || 0,
                                paymentMethod: override.paymentMethod,
                                bank: override.bank,
                                accountNo: override.accountNo,
                              }
                            : undefined,
                        ),
                      "Pay change approved",
                    )
                  }
                >
                  Approve
                </Button>
                <RejectButton
                  title="Reject this pay change"
                  onReject={(reason) => rejectPayConfig(pending.id, reason)}
                  successMessage="Pay change rejected"
                />
              </>
            )}
            {canWrite && (
              <Button
                size="sm"
                variant="ghost"
                disabled={busy}
                onClick={() =>
                  act(() => withdrawPayConfigProposal(pending.id), "Proposal withdrawn")
                }
              >
                Withdraw
              </Button>
            )}
          </div>
        </div>
      )}

      {showPropose && current && (
        <ProposeChangeDialog
          employeeId={emp.id}
          current={current}
          onClose={() => setShowPropose(false)}
        />
      )}
    </section>
  );
}

function ExemptRow({
  label,
  checked,
  disabled,
  onChange,
}: {
  label: string;
  checked: boolean;
  disabled: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <label className="flex items-center justify-between py-1 text-sm">
      <span>{label}</span>
      <Switch checked={checked} disabled={disabled} onCheckedChange={onChange} />
    </label>
  );
}

function ProposeChangeDialog({
  employeeId,
  current,
  onClose,
}: {
  employeeId: string;
  current: PayConfig;
  onClose: () => void;
}) {
  const [basicSalary, setBasicSalary] = useState(String(current.basicSalary));
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>(current.paymentMethod);
  const [bank, setBank] = useState(current.bank ?? "");
  const [accountNo, setAccountNo] = useState(current.accountNo ?? "");
  const [effectiveFrom, setEffectiveFrom] = useState(firstOfNextMonth());
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    if (!basicSalary || Number(basicSalary) < 0) {
      setError("Enter a basic salary.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await proposePayConfigChange({
        employeeId,
        effectiveFrom,
        basicSalary: Number(basicSalary),
        paymentMethod,
        bank,
        accountNo,
        paysSsnit: current.paysSsnit,
        paysTier2: current.paysTier2,
        paysPaye: current.paysPaye,
      });
      toast.success("Change proposed — waiting for Manager approval");
      onClose();
    } catch (err) {
      setError(getErrorMessage(err, "Could not propose the change."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open onOpenChange={(next) => !next && !saving && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Propose a salary / bank change</DialogTitle>
          <DialogDescription>
            A Manager approves this before it takes effect. The current config keeps paying until
            then. The effective date must be a future month with no posted payslip.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Basic salary (monthly)</Label>
              <Input
                type="number"
                min="0"
                step="0.01"
                value={basicSalary}
                onChange={(e) => setBasicSalary(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Effective from</Label>
              <Input
                type="date"
                value={effectiveFrom}
                onChange={(e) => setEffectiveFrom(e.target.value)}
              />
            </div>
            <PaymentDestinationFields
              method={paymentMethod}
              provider={bank}
              number={accountNo}
              onMethod={(m) => {
                setPaymentMethod(m);
                if (m !== current.paymentMethod) setBank("");
                else setBank(current.bank ?? "");
              }}
              onProvider={setBank}
              onNumber={setAccountNo}
            />
          </div>
          {error && <p className="text-sm font-medium text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={saving}>
            {saving ? "Submitting…" : "Submit for approval"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/* --------------------------------------------------- standing allowances */

type Row = { key: string; allowanceTypeId: string; amount: string };

function StandingAllowancesSection({
  employeeId,
  allowanceTypes,
  standing,
  canWrite,
}: {
  employeeId: string;
  allowanceTypes: AllowanceType[];
  standing: { allowanceTypeId: string; defaultAmount: number }[];
  canWrite: boolean;
}) {
  const [rows, setRows] = useState<Row[]>(() =>
    standing.map((s, i) => ({
      key: `s${i}`,
      allowanceTypeId: s.allowanceTypeId,
      amount: String(s.defaultAmount),
    })),
  );
  const [saving, setSaving] = useState(false);

  const used = new Set(rows.map((r) => r.allowanceTypeId));
  const addable = allowanceTypes.filter((t) => !used.has(t.id));

  async function save() {
    setSaving(true);
    try {
      await setStandingAllowances(
        employeeId,
        rows
          .filter((r) => r.allowanceTypeId)
          .map((r) => ({
            allowanceTypeId: r.allowanceTypeId,
            defaultAmount: Number(r.amount) || 0,
          })),
        new Date().toISOString().slice(0, 10),
      );
      toast.success("Standing allowances saved");
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not save allowances."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">Standing monthly allowances</h2>
      <p className="mt-1 text-sm text-muted-foreground">
        Pre-fill each payslip; still editable per month. Direct — no approval.
      </p>
      <div className="mt-4 space-y-2">
        {rows.length === 0 && <p className="text-xs text-muted-foreground">None.</p>}
        {rows.map((row) => {
          const type = allowanceTypes.find((t) => t.id === row.allowanceTypeId);
          return (
            <div key={row.key} className="flex items-center gap-2">
              <span className="flex-1 text-sm">{type?.name ?? "—"}</span>
              <Input
                type="number"
                min="0"
                step="0.01"
                className="w-32"
                disabled={!canWrite}
                value={row.amount}
                onChange={(e) =>
                  setRows((rs) =>
                    rs.map((r) => (r.key === row.key ? { ...r, amount: e.target.value } : r)),
                  )
                }
              />
              {canWrite && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setRows((rs) => rs.filter((r) => r.key !== row.key))}
                >
                  <Trash2 className="size-3.5" />
                </Button>
              )}
            </div>
          );
        })}
      </div>
      {canWrite && (
        <div className="mt-4 flex items-center gap-3">
          {addable.length > 0 && (
            <Select
              value=""
              onValueChange={(v) =>
                setRows((rs) => [...rs, { key: `n${Date.now()}`, allowanceTypeId: v, amount: "0" }])
              }
            >
              <SelectTrigger className="h-9 w-44 text-sm">
                <SelectValue placeholder="Add allowance" />
              </SelectTrigger>
              <SelectContent>
                {addable.map((t) => (
                  <SelectItem key={t.id} value={t.id}>
                    {t.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
          <Button size="sm" onClick={save} disabled={saving}>
            {saving ? "Saving…" : "Save allowances"}
          </Button>
        </div>
      )}
    </section>
  );
}

/* --------------------------------------------------------- history + status */

function HistoryTable({ rows }: { rows: PayConfig[] }) {
  return (
    <section className="card-surface overflow-hidden">
      <p className="border-b p-4 text-sm font-semibold">Pay config history</p>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
            <tr>
              <th className="px-5 py-2 font-medium">Effective</th>
              <th className="px-5 py-2 text-right font-medium">Basic salary</th>
              <th className="px-5 py-2 font-medium">Paid to</th>
            </tr>
          </thead>
          <tbody className="divide-y">
            {rows.map((r) => (
              <tr key={r.id}>
                <td className="px-5 py-2 tabular-nums text-muted-foreground">
                  {r.effectiveFrom} → {r.effectiveTo ?? "open"}
                </td>
                <td className="px-5 py-2 text-right tabular-nums">{currency(r.basicSalary)}</td>
                <td className="px-5 py-2 text-muted-foreground">
                  {r.bank ?? "—"}
                  {r.accountNo ? ` · ${r.accountNo}` : ""}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

/** Full audit trail for this employee — profile status changes plus every
 * pay-config event (proposed/approved/amended/rejected/exemptions), newest
 * first. `configIds` covers every `employee_pay_config` row ever proposed
 * for this employee (any approval_status — a rejected or superseded
 * proposal is still part of the history), since a pay-config audit row's
 * `entity_id` is the config row's id, not the employee's. RLS on
 * `audit_log` already restricts reads to Manager/Accountant/Auditor, same
 * as `employees`/`employee_pay_config` — an Attendant would see this page
 * with no data at all, not just this section, so no extra role gate here. */
function HistorySection({ employeeId, configIds }: { employeeId: string; configIds: string[] }) {
  const { entries, loading, error } = useEmployeeAuditHistory(employeeId, configIds);
  const { staff: roster } = useStaff();
  const staffName = (id: string) => roster.find((s) => s.id === id)?.name ?? "Unknown";

  return (
    <section className="card-surface overflow-hidden">
      <p className="border-b p-4 text-sm font-semibold">History</p>
      {loading && <p className="p-4 text-sm text-muted-foreground">Loading…</p>}
      {error && <p className="p-4 text-sm text-destructive">Could not load history: {error}</p>}
      {!loading && !error && entries.length === 0 && (
        <p className="p-4 text-sm text-muted-foreground">No recorded activity yet.</p>
      )}
      {!loading && !error && entries.length > 0 && (
        <ul className="divide-y">
          {entries.map((entry) => {
            const lines = summarizeAuditEntry(entry);
            return (
              <li key={entry.id} className="p-4 text-sm">
                <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                  <span className="font-medium">{actionLabel(entry.action)}</span>
                  <span className="text-xs text-muted-foreground">
                    {staffName(entry.actorId)} · {entry.occurredAt.slice(0, 16).replace("T", " ")}
                  </span>
                </div>
                {lines.length > 0 && (
                  <ul className="mt-1 space-y-0.5 text-muted-foreground">
                    {lines.map((line, i) => (
                      <li key={i}>{line}</li>
                    ))}
                  </ul>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

function StatusCard({
  emp,
  pending,
  canWrite,
  isManager,
}: {
  emp: Employee;
  pending: PayConfig | undefined;
  canWrite: boolean;
  isManager: boolean;
}) {
  const [busy, setBusy] = useState(false);
  const [adjusting, setAdjusting] = useState(false);
  const [override, setOverride] = useState<PayOverride | null>(null);

  async function act(fn: () => Promise<void>, ok: string) {
    setBusy(true);
    try {
      await fn();
      toast.success(ok);
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not complete that."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">Employment status</h2>
      <p className="mt-2 text-lg font-semibold">{emp.status}</p>

      <div className="mt-4 flex flex-col gap-2">
        {emp.status === "Pending Approval" && isManager && (
          <>
            {pending &&
              (!adjusting ? (
                <Button
                  type="button"
                  size="sm"
                  variant="ghost"
                  className="justify-start px-0"
                  onClick={() => {
                    setOverride(payOverrideFrom(pending));
                    setAdjusting(true);
                  }}
                >
                  Adjust bundled pay before approving
                </Button>
              ) : (
                <div className="space-y-2 rounded-lg border p-3">
                  <div className="flex items-center justify-between">
                    <p className="text-xs font-medium text-muted-foreground">
                      Adjusting the proposed pay — recorded as an amendment.
                    </p>
                    <Button
                      type="button"
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        setAdjusting(false);
                        setOverride(null);
                      }}
                    >
                      Cancel
                    </Button>
                  </div>
                  {override && <AdjustPayFields value={override} onChange={setOverride} />}
                </div>
              ))}
            <Button
              disabled={busy}
              onClick={() =>
                act(
                  () =>
                    approveEmployee(
                      emp.id,
                      adjusting && override
                        ? {
                            basicSalary: Number(override.basicSalary) || 0,
                            paymentMethod: override.paymentMethod,
                            bank: override.bank,
                            accountNo: override.accountNo,
                          }
                        : undefined,
                    ),
                  `${emp.name} approved`,
                )
              }
            >
              Approve record
            </Button>
            <RejectButton
              title={`Reject ${emp.name}'s record`}
              label="Reject record"
              size="default"
              onReject={(reason) => rejectEmployee(emp.id, reason)}
              successMessage={`${emp.name} rejected`}
            />
          </>
        )}
        {emp.status === "Active" && canWrite && (
          <Button
            variant="outline"
            disabled={busy}
            onClick={() =>
              act(() => setEmployeeStatus(emp.id, "Suspended"), `${emp.name} suspended`)
            }
          >
            Suspend
          </Button>
        )}
        {emp.status === "Suspended" && canWrite && (
          <Button
            disabled={busy}
            onClick={() =>
              act(() => setEmployeeStatus(emp.id, "Active"), `${emp.name} reactivated`)
            }
          >
            Reactivate
          </Button>
        )}
      </div>

      {emp.status === "Pending Approval" && !isManager && (
        <p className="mt-3 text-xs text-muted-foreground">Waiting for a Manager to approve.</p>
      )}
    </section>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd className="mt-1 text-sm font-medium">{value}</dd>
    </div>
  );
}

function BackLink() {
  return (
    <Link
      to="/employees"
      className="mb-4 inline-flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground"
    >
      <ArrowLeft className="size-4" /> Back to employees
    </Link>
  );
}
