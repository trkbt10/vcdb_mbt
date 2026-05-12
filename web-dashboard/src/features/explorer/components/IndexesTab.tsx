import { useState, useEffect, useCallback } from "react";
import { useAsyncFn } from "react-use";
import { Button, Modal, Spinner, ConfirmDialog } from "@vcdb/ui-kit";
import { useDatabase, type IndexEntry, type IndexConfig } from "@/contexts/DatabaseContext";
import { useToast } from "@vcdb/ui-kit/toast";
import { IndexEditor, type IndexEditorEntry } from "@/features/index-editor";
import { IndexCard } from "./IndexCard";
import styles from "./IndexesTab.module.css";

export function IndexesTab() {
  const { listIndexes, createIndex, dropIndex, rebuildIndex } = useDatabase();
  const toast = useToast();

  const [indexes, setIndexes] = useState<IndexEntry[]>([]);
  const [isEditorOpen, setIsEditorOpen] = useState(false);
  const [editingEntry, setEditingEntry] = useState<IndexEditorEntry | null>(null);
  const [rebuildingName, setRebuildingName] = useState<string | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<{ name: string } | null>(null);

  // Fetch indexes
  const [fetchState, fetchIndexes] = useAsyncFn(async () => {
    const result = await listIndexes();
    setIndexes(result);
    return result;
  }, [listIndexes]);

  useEffect(() => {
    fetchIndexes();
  }, [fetchIndexes]);

  // Create/Update index
  const handleSaveIndex = useCallback(
    async (name: string, config: IndexConfig, originalName?: string) => {
      try {
        // If editing and name changed, we need to delete old and create new
        if (originalName && originalName !== name) {
          await dropIndex(originalName);
        }

        await createIndex({ name, config, replace: !!originalName });
        toast.success(originalName ? "Index updated" : "Index created");
        setIsEditorOpen(false);
        setEditingEntry(null);
        fetchIndexes();
      } catch (e) {
        toast.error(e instanceof Error ? e.message : "Failed to save index");
      }
    },
    [createIndex, dropIndex, fetchIndexes, toast]
  );

  // Rebuild index
  const handleRebuild = useCallback(
    async (name: string) => {
      setRebuildingName(name);
      try {
        await rebuildIndex(name);
        toast.success(`Index "${name}" rebuilt`);
        fetchIndexes();
      } catch (e) {
        toast.error(e instanceof Error ? e.message : "Failed to rebuild index");
      } finally {
        setRebuildingName(null);
      }
    },
    [rebuildIndex, fetchIndexes, toast]
  );

  // Delete index
  const handleDelete = useCallback(
    async (name: string) => {
      try {
        await dropIndex(name, true);
        toast.success(`Index "${name}" deleted`);
        setDeleteConfirm(null);
        fetchIndexes();
      } catch (e) {
        toast.error(e instanceof Error ? e.message : "Failed to delete index");
      }
    },
    [dropIndex, fetchIndexes, toast]
  );

  const handleEdit = useCallback((entry: IndexEntry) => {
    setEditingEntry({ name: entry.name, config: entry.def });
    setIsEditorOpen(true);
  }, []);

  const handleCreate = useCallback(() => {
    setEditingEntry(null);
    setIsEditorOpen(true);
  }, []);

  const handleCloseEditor = useCallback(() => {
    setIsEditorOpen(false);
    setEditingEntry(null);
  }, []);

  const existingNames = indexes.map((i) => i.name);

  if (fetchState.loading && indexes.length === 0) {
    return (
      <div className={styles.loading}>
        <Spinner />
        <span>Loading indexes...</span>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h3 className={styles.title}>Indexes</h3>
        <Button onClick={handleCreate}>+ Create Index</Button>
      </div>

      {indexes.length === 0 ? (
        <div className={styles.empty}>
          <p>No indexes defined yet.</p>
          <p className={styles.emptyHint}>
            Create an index to enable fast vector similarity search.
          </p>
        </div>
      ) : (
        <div className={styles.grid}>
          {indexes.map((entry) => (
            <IndexCard
              key={entry.id}
              entry={entry}
              onEdit={() => handleEdit(entry)}
              onRebuild={() => handleRebuild(entry.name)}
              onDelete={() => setDeleteConfirm({ name: entry.name })}
              rebuilding={rebuildingName === entry.name}
            />
          ))}
        </div>
      )}

      <Modal
        open={isEditorOpen}
        onClose={handleCloseEditor}
        title={editingEntry ? `Edit Index: ${editingEntry.name}` : "Create Index"}
      >
        <IndexEditor
          onClose={handleCloseEditor}
          onSave={handleSaveIndex}
          existingNames={existingNames}
          editingEntry={editingEntry}
        />
      </Modal>

      <ConfirmDialog
        open={deleteConfirm !== null}
        title="Delete Index"
        message={`Are you sure you want to delete the index "${deleteConfirm?.name}"? This action cannot be undone.`}
        confirmLabel="Delete"
        onConfirm={() => deleteConfirm && handleDelete(deleteConfirm.name)}
        onClose={() => setDeleteConfirm(null)}
        variant="danger"
      />
    </div>
  );
}
