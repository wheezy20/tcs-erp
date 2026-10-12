import { useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import type { StaffRole } from "@/data/auth-store";
import { listNotes, type ApplicationNote } from "@/modules/admissions/data/application-detail";
import { addApplicationNote, updateApplicationNote } from "@/modules/admissions/data/mutations";
import { listStaffNames } from "@/modules/admissions/data/reference";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import { canAddNote, canEditNote } from "@/modules/admissions/permissions";
import { getErrorMessage } from "@/lib/utils";

const NOTE_MAX_LENGTH = 10000;
const dateTime = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });

export function NotesPanel({
  applicationId,
  role,
  staffId,
}: {
  applicationId: string;
  role: StaffRole | undefined;
  staffId: string | null;
}) {
  const notes = useLoad(() => listNotes(applicationId), [applicationId], "Could not load notes.");
  const names = useLoad(listStaffNames, [], "Could not load staff names.");
  const [draft, setDraft] = useState("");
  const [saving, setSaving] = useState(false);

  async function add() {
    setSaving(true);
    try {
      await addApplicationNote(applicationId, draft);
      setDraft("");
      toast.success("Note added");
      await notes.reload();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not add the note."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">Notes</h2>

      {canAddNote(role) && (
        <div className="mt-4 space-y-2">
          <Textarea
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="Add a note for other staff"
            maxLength={NOTE_MAX_LENGTH}
            rows={3}
          />
          <div className="flex justify-end">
            <Button onClick={add} disabled={saving || draft.trim() === ""}>
              {saving ? "Adding…" : "Add note"}
            </Button>
          </div>
        </div>
      )}

      <div className="mt-5 space-y-3">
        {notes.error && <p className="text-sm text-destructive">{notes.error}</p>}
        {!notes.error && notes.loading && !notes.data && (
          <p className="text-sm text-muted-foreground">Loading…</p>
        )}
        {notes.data && notes.data.length === 0 && (
          <p className="text-sm text-muted-foreground">No notes yet.</p>
        )}
        {notes.data?.map((note) => (
          <NoteRow
            key={note.id}
            note={note}
            authorName={note.authorId ? (names.data?.get(note.authorId) ?? "Unknown") : "Unknown"}
            canEdit={canEditNote(role, note.authorId, staffId)}
            onSaved={notes.reload}
          />
        ))}
      </div>
    </section>
  );
}

function NoteRow({
  note,
  authorName,
  canEdit,
  onSaved,
}: {
  note: ApplicationNote;
  authorName: string;
  canEdit: boolean;
  onSaved: () => Promise<void>;
}) {
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(note.content);
  const [saving, setSaving] = useState(false);

  async function save() {
    setSaving(true);
    try {
      await updateApplicationNote(note.id, text);
      toast.success("Note updated");
      setEditing(false);
      await onSaved();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not update the note."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="rounded-md border px-3 py-2 text-sm">
      <div className="flex items-center justify-between gap-2 text-xs text-muted-foreground">
        <span>
          {authorName} · {dateTime.format(new Date(note.createdAt))}
          {note.editedAt ? ` · edited ${dateTime.format(new Date(note.editedAt))}` : ""}
        </span>
        {canEdit && !editing && (
          <Button
            variant="ghost"
            size="sm"
            className="h-7"
            onClick={() => {
              setText(note.content);
              setEditing(true);
            }}
          >
            Edit
          </Button>
        )}
      </div>
      {editing ? (
        <div className="mt-2 space-y-2">
          <Textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            maxLength={NOTE_MAX_LENGTH}
            rows={3}
          />
          <div className="flex justify-end gap-2">
            <Button variant="outline" size="sm" onClick={() => setEditing(false)} disabled={saving}>
              Cancel
            </Button>
            <Button size="sm" onClick={save} disabled={saving || text.trim() === ""}>
              {saving ? "Saving…" : "Save"}
            </Button>
          </div>
        </div>
      ) : (
        <p className="mt-1 whitespace-pre-wrap">{note.content}</p>
      )}
    </div>
  );
}
