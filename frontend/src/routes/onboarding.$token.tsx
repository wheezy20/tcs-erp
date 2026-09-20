import { useEffect, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { DOCUMENT_TYPES, type DocumentType } from "@/data/employee-documents-store";
import {
  getOnboardingContext,
  submitOnboardingForm,
  uploadOnboardingDocument,
} from "@/data/onboarding-store";
import { getErrorMessage } from "@/lib/utils";

// Public, unauthenticated route — reached from a personalized single-use
// link (see generate_onboarding_token()), never through the sidebar/login.
// __root.tsx treats /onboarding/* as auth-free, same as /login and
// /accept-invite. Every check (is this token real, unexpired, unused) is
// enforced server-side inside the RPCs this page calls, not by anything
// client-side — a candidate never gets a session at all.
export const Route = createFileRoute("/onboarding/$token")({
  head: () => ({ meta: [{ title: "Onboarding — TCS" }] }),
  component: PublicOnboardingPage,
});

type Context = {
  employeeName: string | null;
  position: string | null;
  department: string | null;
  valid: boolean;
};

function PublicOnboardingPage() {
  const { token } = Route.useParams();
  const [context, setContext] = useState<Context | null>(null);
  const [loading, setLoading] = useState(true);

  const [dateOfBirth, setDateOfBirth] = useState("");
  const [gender, setGender] = useState("");
  const [nationalId, setNationalId] = useState("");
  const [personalEmail, setPersonalEmail] = useState("");
  const [emergencyContactName, setEmergencyContactName] = useState("");
  const [emergencyContactPhone, setEmergencyContactPhone] = useState("");
  const [residentialAddress, setResidentialAddress] = useState("");
  const [qualifications, setQualifications] = useState("");
  const [bankName, setBankName] = useState("");
  const [accountNo, setAccountNo] = useState("");
  const [paymentMethod, setPaymentMethod] = useState<"Bank" | "Mobile Money" | "">("");

  const [pendingDocs, setPendingDocs] = useState<{ type: DocumentType; file: File }[]>([]);
  const [docType, setDocType] = useState<DocumentType>(DOCUMENT_TYPES[0]);
  const [docFile, setDocFile] = useState<File | null>(null);

  const [contractAccepted, setContractAccepted] = useState(false);
  const [signatureName, setSignatureName] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  useEffect(() => {
    getOnboardingContext(token)
      .then(setContext)
      .catch(() =>
        setContext({ employeeName: null, position: null, department: null, valid: false }),
      )
      .finally(() => setLoading(false));
  }, [token]);

  function addDocument() {
    if (!docFile) return;
    setPendingDocs((prev) => [...prev, { type: docType, file: docFile }]);
    setDocFile(null);
  }

  function removeDocument(index: number) {
    setPendingDocs((prev) => prev.filter((_, i) => i !== index));
  }

  async function onSubmit() {
    if (!contractAccepted || !signatureName.trim()) {
      toast.error("Please accept the contract and type your full name to sign.");
      return;
    }
    setSubmitting(true);
    try {
      const uploaded = [];
      for (const doc of pendingDocs) {
        uploaded.push(await uploadOnboardingDocument(token, doc.type, doc.file));
      }
      await submitOnboardingForm(token, {
        dateOfBirth: dateOfBirth || undefined,
        gender: gender || undefined,
        nationalId: nationalId || undefined,
        personalEmail: personalEmail || undefined,
        emergencyContactName: emergencyContactName || undefined,
        emergencyContactPhone: emergencyContactPhone || undefined,
        residentialAddress: residentialAddress || undefined,
        qualifications: qualifications || undefined,
        bankName: bankName || undefined,
        accountNo: accountNo || undefined,
        paymentMethod: paymentMethod || undefined,
        contractAccepted,
        signatureName,
        uploadedDocuments: uploaded,
      });
      setSubmitted(true);
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not submit the form."));
    } finally {
      setSubmitting(false);
    }
  }

  if (loading) {
    return (
      <div className="mx-auto max-w-xl px-4 py-16 text-center text-sm text-muted-foreground">
        Loading…
      </div>
    );
  }

  if (!context?.valid) {
    return (
      <div className="mx-auto max-w-xl px-4 py-16 text-center">
        <h1 className="text-lg font-semibold">This link is invalid or has expired</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Please contact TCS HR for a new onboarding link.
        </p>
      </div>
    );
  }

  if (submitted) {
    return (
      <div className="mx-auto max-w-xl px-4 py-16 text-center">
        <h1 className="text-lg font-semibold">Thank you!</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Your onboarding details have been received. TCS HR will review them shortly.
        </p>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-xl px-4 py-10">
      <h1 className="text-lg font-semibold">Welcome to TCS, {context.employeeName}</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        {[context.position, context.department].filter(Boolean).join(" · ")}
      </p>
      <p className="mt-4 text-sm text-muted-foreground">
        Please fill in your details below. This link can only be used once.
      </p>

      <div className="mt-6 space-y-5">
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2">
            <Label>Date of birth</Label>
            <Input
              type="date"
              value={dateOfBirth}
              onChange={(e) => setDateOfBirth(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label>Gender</Label>
            <Input value={gender} onChange={(e) => setGender(e.target.value)} />
          </div>
          <div className="space-y-2">
            <Label>National ID number</Label>
            <Input value={nationalId} onChange={(e) => setNationalId(e.target.value)} />
          </div>
          <div className="space-y-2">
            <Label>Personal email</Label>
            <Input
              type="email"
              value={personalEmail}
              onChange={(e) => setPersonalEmail(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label>Emergency contact name</Label>
            <Input
              value={emergencyContactName}
              onChange={(e) => setEmergencyContactName(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label>Emergency contact phone</Label>
            <Input
              value={emergencyContactPhone}
              onChange={(e) => setEmergencyContactPhone(e.target.value)}
            />
          </div>
        </div>

        <div className="space-y-2">
          <Label>Residential address</Label>
          <Textarea
            value={residentialAddress}
            onChange={(e) => setResidentialAddress(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>Qualifications</Label>
          <Textarea value={qualifications} onChange={(e) => setQualifications(e.target.value)} />
        </div>

        <div className="rounded-md border p-4">
          <h2 className="text-sm font-semibold">Banking details</h2>
          <p className="mt-1 text-xs text-muted-foreground">
            For HR's reference — payroll setup is a separate step handled by HR.
          </p>
          <div className="mt-3 grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label>Payment method</Label>
              <Select
                value={paymentMethod}
                onValueChange={(v) => setPaymentMethod(v as "Bank" | "Mobile Money")}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Select" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Bank">Bank</SelectItem>
                  <SelectItem value="Mobile Money">Mobile Money</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Bank / network name</Label>
              <Input value={bankName} onChange={(e) => setBankName(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>Account / wallet number</Label>
              <Input value={accountNo} onChange={(e) => setAccountNo(e.target.value)} />
            </div>
          </div>
        </div>

        <div className="rounded-md border p-4">
          <h2 className="text-sm font-semibold">Documents</h2>
          <div className="mt-3 grid gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
            <div className="space-y-2">
              <Label>Type</Label>
              <Select value={docType} onValueChange={(v) => setDocType(v as DocumentType)}>
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
                onChange={(e) => setDocFile(e.target.files?.[0] ?? null)}
              />
            </div>
            <Button type="button" variant="outline" onClick={addDocument} disabled={!docFile}>
              Add
            </Button>
          </div>
          {pendingDocs.length > 0 && (
            <ul className="mt-3 space-y-1 text-sm">
              {pendingDocs.map((d, i) => (
                <li key={i} className="flex items-center justify-between rounded border px-2 py-1">
                  <span>
                    {d.type} — {d.file.name}
                  </span>
                  <button
                    type="button"
                    className="text-xs text-destructive"
                    onClick={() => removeDocument(i)}
                  >
                    Remove
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="rounded-md border p-4">
          <h2 className="text-sm font-semibold">Contract acceptance</h2>
          <label className="mt-3 flex items-start gap-2 text-sm">
            <Checkbox
              checked={contractAccepted}
              onCheckedChange={(v) => setContractAccepted(v === true)}
            />
            <span>I have read and accept the terms of my employment contract with TCS.</span>
          </label>
          <div className="mt-3 space-y-2">
            <Label>Type your full name to sign</Label>
            <Input value={signatureName} onChange={(e) => setSignatureName(e.target.value)} />
          </div>
        </div>

        <Button className="w-full" onClick={onSubmit} disabled={submitting}>
          {submitting ? "Submitting…" : "Submit"}
        </Button>
      </div>
    </div>
  );
}
