import { useState } from "react";
import { useRegistry } from "../hooks/useRegistry";
import { ConnectionItem } from "./ConnectionItem";
import { CreateDatabaseModal } from "./CreateDatabaseModal";
import { Plus, Refresh, ConfirmDialog, Spinner } from "@vcdb/ui-kit";
import type { DatabaseInfo } from "../types";
import styles from "./ConnectionManager.module.css";

type ConnectionManagerProps = {
  mode: "compact" | "full";
  selectedId?: string | null;
  onSelect?: (database: DatabaseInfo) => void;
};

export function ConnectionManager({
  mode,
  selectedId,
  onSelect,
}: ConnectionManagerProps) {
  const { databases, loading, error, refresh, createDatabase, deleteDatabase } = useRegistry();
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [deletingDb, setDeletingDb] = useState<DatabaseInfo | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  const handleCreate = async (data: { name: string; config: { dim: number; metric?: string; strategy?: string } }) => {
    await createDatabase(data);
    setShowCreateModal(false);
  };

  const handleRemoveConfirm = async () => {
    if (!deletingDb) {
      return;
    }
    setIsDeleting(true);
    try {
      await deleteDatabase(deletingDb.name);
    } finally {
      setIsDeleting(false);
      setDeletingDb(null);
    }
  };

  if (mode === "compact") {
    return (
      <div className={styles.compact}>
        <div className={styles.compactHeader}>
          <span className={styles.compactTitle}>Collections</span>
          <div className={styles.compactActions}>
            <button className={styles.iconButton} onClick={refresh} disabled={loading} title="Refresh">
              <Refresh size={14} className={loading ? styles.spinning : ""} />
            </button>
            <button
              className={styles.iconButton}
              onClick={() => setShowCreateModal(true)}
              title="Create Collection"
            >
              <Plus size={16} />
            </button>
          </div>
        </div>

        <div className={styles.compactList}>
          {loading && databases.length === 0 ? (
            <div className={styles.loading}>
              <Spinner size="sm" />
              <span>Loading...</span>
            </div>
          ) : error ? (
            <div className={styles.error}>
              <p>{error}</p>
              <button className={styles.retryButton} onClick={refresh}>
                Retry
              </button>
            </div>
          ) : databases.length === 0 ? (
            <div className={styles.empty}>
              <p>No collections</p>
              <button className={styles.emptyButton} onClick={() => setShowCreateModal(true)}>
                Create Collection
              </button>
            </div>
          ) : (
            databases.map((db) => (
              <ConnectionItem
                key={db.id}
                database={db}
                mode="compact"
                selected={selectedId === db.id}
                onSelect={() => onSelect?.(db)}
                onRemove={() => setDeletingDb(db)}
              />
            ))
          )}
        </div>

        <CreateDatabaseModal
          open={showCreateModal}
          onClose={() => setShowCreateModal(false)}
          onSubmit={handleCreate}
        />

        <ConfirmDialog
          open={!!deletingDb}
          onClose={() => setDeletingDb(null)}
          onConfirm={handleRemoveConfirm}
          title="Delete Collection"
          message={`Delete "${deletingDb?.name}" and all persisted vectors?`}
          confirmLabel={isDeleting ? "Deleting..." : "Delete"}
          cancelLabel="Cancel"
          variant="danger"
        />
      </div>
    );
  }

  return (
    <div className={styles.full}>
      <div className={styles.fullHeader}>
        <div className={styles.fullHeaderText}>
          <h2>Collections</h2>
          <p>Manage vector collections exposed by the gateway</p>
        </div>
        <div className={styles.fullActions}>
          <button className={styles.secondaryButton} onClick={refresh} disabled={loading}>
            {loading ? "Refreshing..." : "Refresh"}
          </button>
          <button className={styles.primaryButton} onClick={() => setShowCreateModal(true)}>
            Create Collection
          </button>
        </div>
      </div>

      {error && (
        <div className={styles.errorBanner}>
          <span>{error}</span>
          <button onClick={refresh}>Retry</button>
        </div>
      )}

      <div className={styles.fullGrid}>
        {loading && databases.length === 0 ? (
          <div className={styles.loadingFull}>
            <Spinner size="lg" />
            <p>Loading collections...</p>
          </div>
        ) : databases.length === 0 ? (
          <div className={styles.emptyFull}>
            <p>No collections</p>
            <p className={styles.emptyHint}>Create a collection to get started</p>
            <button className={styles.primaryButton} onClick={() => setShowCreateModal(true)}>
              Create Collection
            </button>
          </div>
        ) : (
          databases.map((db) => (
            <ConnectionItem
              key={db.id}
              database={db}
              mode="full"
              selected={selectedId === db.id}
              onSelect={() => onSelect?.(db)}
              onRemove={() => setDeletingDb(db)}
            />
          ))
        )}
      </div>

      <CreateDatabaseModal
        open={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSubmit={handleCreate}
      />

      <ConfirmDialog
        open={!!deletingDb}
        onClose={() => setDeletingDb(null)}
        onConfirm={handleRemoveConfirm}
        title="Delete Collection"
        message={`Delete "${deletingDb?.name}" and all persisted vectors?`}
        confirmLabel={isDeleting ? "Deleting..." : "Delete"}
        cancelLabel="Cancel"
        variant="danger"
      />
    </div>
  );
}
