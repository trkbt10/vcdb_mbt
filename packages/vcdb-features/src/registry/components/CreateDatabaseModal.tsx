import { useState } from "react";
import { Modal, Input, Button, Select } from "@vcdb/ui-kit";
import styles from "./CreateDatabaseModal.module.css";

type CreateDatabaseData = {
  name: string;
  config: {
    dim: number;
    metric?: string;
    strategy?: string;
  };
};

type CreateDatabaseModalProps = {
  open: boolean;
  onClose: () => void;
  onSubmit: (data: CreateDatabaseData) => Promise<void>;
};

export function CreateDatabaseModal({
  open,
  onClose,
  onSubmit,
}: CreateDatabaseModalProps) {
  const [name, setName] = useState("");
  const [dim, setDim] = useState(384);
  const [metric, setMetric] = useState("cosine");
  const [strategy, setStrategy] = useState("hnsw");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      await onSubmit({
        name,
        config: { dim, metric, strategy },
      });
      // Reset form
      setName("");
      setDim(384);
      setMetric("cosine");
      setStrategy("hnsw");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create database");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleClose = () => {
    if (!isSubmitting) {
      setError(null);
      onClose();
    }
  };

  return (
    <Modal open={open} onClose={handleClose} title="Create Collection">
      <form onSubmit={handleSubmit} className={styles.form}>
        {error && <div className={styles.error}>{error}</div>}

        <Input
          label="Name"
          data-testid="create-collection-name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="my-vectors"
          required
          disabled={isSubmitting}
        />

        <Input
          label="Dimensions"
          data-testid="create-collection-dim"
          type="number"
          value={dim}
          onChange={(e) => setDim(parseInt(e.target.value) || 384)}
          min={1}
          max={4096}
          required
          disabled={isSubmitting}
        />

        <Select
          value={metric}
          onChange={(e) => setMetric(e.target.value)}
          disabled={isSubmitting}
          options={[
            { value: "cosine", label: "Cosine" },
            { value: "l2", label: "L2 (Euclidean)" },
            { value: "dot", label: "Dot Product" },
          ]}
        />

        <Select
          value={strategy}
          onChange={(e) => setStrategy(e.target.value)}
          disabled={isSubmitting}
          options={[
            { value: "hnsw", label: "HNSW" },
            { value: "bruteforce", label: "Brute Force" },
          ]}
        />

        <div className={styles.actions}>
          <Button type="button" variant="ghost" onClick={handleClose} disabled={isSubmitting}>
            Cancel
          </Button>
          <Button type="submit" variant="primary" loading={isSubmitting} data-testid="create-collection-submit">
            Create
          </Button>
        </div>
      </form>
    </Modal>
  );
}
