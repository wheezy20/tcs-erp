import { PublicPage } from "@/modules/admissions/components/public-page-parts";
import { PRIVACY_PAGE_COPY as COPY } from "@/modules/admissions/public-copy";

// The public privacy policy page (admissions slice 15 B). Its text lives in
// PRIVACY_PAGE_COPY; while that is the placeholder, the page says so first.
export function PrivacyPage() {
  return (
    <PublicPage>
      <div className="tcs-card tcs-privacy">
        <h1>{COPY.pageTitle}</h1>
        {COPY.placeholder && (
          <p className="tcs-privacy-placeholder" role="note">
            {COPY.placeholderNotice}
          </p>
        )}
        {COPY.paragraphs.map((p, i) => (
          <p key={i}>{p}</p>
        ))}
        <p>{COPY.contactLine}</p>
      </div>
    </PublicPage>
  );
}
