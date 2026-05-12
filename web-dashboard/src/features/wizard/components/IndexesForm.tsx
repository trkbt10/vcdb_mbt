import React, { useMemo, useState } from "react";
import { Button } from "@vcdb/ui-kit";
import type { IndexConfig } from "vcdb/meta/index-types";
import type { WizardData, IndexEntry } from "../types";
import { IndexEditor } from "./IndexEditor";
import { IndexCard } from "./IndexCard";
import { WizardStepLayout } from "./WizardStepLayout";
import indexStyles from "./IndexesForm.module.css";

type EditorBodyContentProps = {
  editorOpen: boolean;
  onClose: () => void;
  onSave: (name: string, config: IndexConfig, originalName?: string) => void;
  existingNames: string[];
  editingEntry: IndexEntry | null;
};

function EditorBodyContent({ editorOpen, onClose, onSave, existingNames, editingEntry }: EditorBodyContentProps): React.ReactNode {
  if (!editorOpen) {
    return (
      <div className={indexStyles.editorEmpty}>
        Select an index card to edit, or add a new index to begin.
      </div>
    );
  }
  return (
    <IndexEditor
      onClose={onClose}
      onSave={onSave}
      existingNames={existingNames}
      editingEntry={editingEntry}
    />
  );
}

type IndexesFormProps = {
  data: WizardData;
  onSetIndex: (name: string, config: IndexConfig) => void;
  onRemoveIndex: (name: string) => void;
  onRenameIndex: (oldName: string, newName: string) => void;
  onNext: () => void;
  onPrev: () => void;
};

export function IndexesForm({
  data,
  onSetIndex,
  onRemoveIndex,
  onRenameIndex,
  onNext,
  onPrev,
}: IndexesFormProps) {
  const [editorOpen, setEditorOpen] = useState(false);
  const [editingEntry, setEditingEntry] = useState<IndexEntry | null>(null);

  // Convert Record to array for display
  const indexEntries: IndexEntry[] = Object.entries(data.indexes).map(
    ([name, config]) => ({ name, config })
  );
  const existingNames = Object.keys(data.indexes);
  const editorTitle = useMemo(() => {
    if (!editorOpen) {
      return "Index Editor";
    }
    if (editingEntry) {
      return `Edit Index: ${editingEntry.name}`;
    }
    return "Add New Index";
  }, [editingEntry, editorOpen]);

  const handleAdd = () => {
    setEditingEntry(null);
    setEditorOpen(true);
  };

  const handleEdit = (entry: IndexEntry) => {
    setEditingEntry(entry);
    setEditorOpen(true);
  };

  const handleSave = (name: string, config: IndexConfig, originalName?: string) => {
    if (originalName && originalName !== name) {
      // Rename: remove old, add new
      onRenameIndex(originalName, name);
    }
    onSetIndex(name, config);
    setEditorOpen(false);
    setEditingEntry(null);
  };

  const handleDelete = (name: string) => {
    onRemoveIndex(name);
  };

  return (
    <WizardStepLayout
      title="Configure Indexes"
      description="Define one or more indexes for your database. You can create vector indexes for similarity search, attribute indexes for filtering, or combined indexes for pre-filtered vector search."
      actions={(
        <>
          <Button variant="ghost" onClick={onPrev}>
            Back
          </Button>
          <Button
            variant="primary"
            onClick={onNext}
            disabled={indexEntries.length === 0}
          >
            Continue
          </Button>
        </>
      )}
    >
      <div className={indexStyles.layout}>
        <div className={indexStyles.listPane}>
          <div className={indexStyles.indexList}>
            {indexEntries.map((entry) => (
              <IndexCard
                key={entry.name}
                entry={entry}
                onEdit={() => handleEdit(entry)}
                onDelete={() => handleDelete(entry.name)}
                canDelete={indexEntries.length > 1}
              />
            ))}

            <button
              type="button"
              className={indexStyles.addButton}
              onClick={handleAdd}
            >
              <svg
                width="24"
                height="24"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
              >
                <path d="M12 5v14M5 12h14" />
              </svg>
              <span>Add Index</span>
            </button>
          </div>
        </div>

        <div className={indexStyles.editorPane} data-open={editorOpen}>
          <div className={indexStyles.editorHeader}>
            <div className={indexStyles.editorTitle}>{editorTitle}</div>
            <button
              type="button"
              className={indexStyles.editorToggle}
              onClick={() => {
                if (!editorOpen && !editingEntry) {
                  handleAdd();
                  return;
                }
                setEditorOpen((prev) => !prev);
              }}
            >
              {editorOpen ? "Collapse" : "Expand"}
            </button>
          </div>

          <div className={indexStyles.editorBody} data-open={editorOpen}>
            <EditorBodyContent
              editorOpen={editorOpen}
              onClose={() => {
                setEditorOpen(false);
                setEditingEntry(null);
              }}
              onSave={handleSave}
              existingNames={existingNames}
              editingEntry={editingEntry}
            />
          </div>
        </div>
      </div>
    </WizardStepLayout>
  );
}
