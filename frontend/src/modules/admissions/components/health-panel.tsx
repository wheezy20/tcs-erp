import { HeartPulse } from "lucide-react";

import { Skeleton } from "@/components/ui/skeleton";
import {
  getHealthInfo,
  hasHealthCapability,
  type HealthInfo,
} from "@/modules/admissions/data/health";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import {
  healthPanelState,
  type HealthCapability,
  type HealthFetch,
} from "@/modules/admissions/permissions";

/** Renders nothing, not even a heading, unless the live capability check
 * returns true. Only then is the answers component mounted, so a user
 * without the capability never fires the health read at all. */
export function HealthPanel({ applicationId }: { applicationId: string }) {
  const check = useLoad(hasHealthCapability, [], "Could not check health access.");
  const capability: HealthCapability = check.loading
    ? "checking"
    : check.error
      ? "error"
      : check.data
        ? "granted"
        : "denied";
  if (capability !== "granted") return null;
  return <HealthAnswers applicationId={applicationId} />;
}

function HealthAnswers({ applicationId }: { applicationId: string }) {
  const health = useLoad(
    () => getHealthInfo(applicationId),
    [applicationId],
    "Could not load health information.",
  );
  const fetch: HealthFetch = health.loading
    ? "loading"
    : health.error
      ? "error"
      : health.data
        ? "row"
        : "none";
  const state = healthPanelState("granted", fetch);

  return (
    <section className="card-surface p-6">
      <h2 className="flex items-center gap-2 text-sm font-semibold">
        <HeartPulse className="size-4 text-muted-foreground" /> Health
      </h2>
      <p className="mt-1 text-xs text-muted-foreground">
        Shown only to staff with health access. Not included in lists, search or exports.
      </p>
      <div className="mt-4">
        {state === "loading" && <Skeleton className="h-16 w-full" />}
        {state === "error" && (
          <p className="text-sm text-destructive">Could not load health information.</p>
        )}
        {state === "empty" && (
          <p className="text-sm text-muted-foreground">No health information on file.</p>
        )}
        {state === "answers" && health.data && <HealthAnswerList info={health.data} />}
      </div>
    </section>
  );
}

function HealthAnswerList({ info }: { info: HealthInfo }) {
  const items = [
    {
      label: "Learning or physical needs",
      yes: info.hasLearningOrPhysicalNeeds,
      details: info.learningOrPhysicalNeedsDetails,
    },
    {
      label: "Medical conditions",
      yes: info.hasMedicalConditions,
      details: info.medicalConditionsDetails,
    },
    {
      label: "Allergies or dietary requirements",
      yes: info.hasAllergiesOrDietaryRequirements,
      details: info.allergiesDietaryDetails,
    },
  ];
  return (
    <dl className="space-y-3">
      {items.map((item) => (
        <div key={item.label}>
          <dt className="text-xs uppercase tracking-wide text-muted-foreground">{item.label}</dt>
          <dd className="mt-1 text-sm">
            <span className="font-medium">{item.yes ? "Yes" : "No"}</span>
            {item.details ? (
              <p className="mt-1 whitespace-pre-wrap text-muted-foreground">{item.details}</p>
            ) : null}
          </dd>
        </div>
      ))}
    </dl>
  );
}
