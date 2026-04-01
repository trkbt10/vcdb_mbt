import { useState, useEffect } from "react";
import { Modal, Input, Button } from "@/components/ui";
import type { DatabaseInfo } from "../types";
import { DEFAULT_HOST, DEFAULT_PORT } from "../../../constants";
import styles from "./ConnectionFormModal.module.css";

type ConnectionData = { name: string; host: string; port: number };

type ConnectionFormModalProps = {
  open: boolean;
  onClose: () => void;
  onSubmit: (data: ConnectionData) => void;
  initialData?: DatabaseInfo;
};

export function ConnectionFormModal({
  open,
  onClose,
  onSubmit,
  initialData,
}: ConnectionFormModalProps) {
  const [name, setName] = useState("");
  const [host, setHost] = useState(DEFAULT_HOST);
  const [port, setPort] = useState(DEFAULT_PORT);

  const isEdit = !!initialData;

  useEffect(() => {
    if (initialData) {
      setName(initialData.name);
      setHost(initialData.host);
      setPort(initialData.port);
    } else {
      setName("");
      setHost(DEFAULT_HOST);
      setPort(DEFAULT_PORT);
    }
  }, [initialData, open]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit({ name, host, port });
    onClose();
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? "Edit Connection" : "Add Connection"}
    >
      <form onSubmit={handleSubmit} className={styles.form}>
        <Input
          label="Name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="my-database"
          required
        />
        <Input
          label="Host"
          value={host}
          onChange={(e) => setHost(e.target.value)}
          placeholder="localhost"
          required
        />
        <Input
          label="Port"
          type="number"
          value={port}
          onChange={(e) => setPort(parseInt(e.target.value) || DEFAULT_PORT)}
          required
        />
        <div className={styles.actions}>
          <Button type="button" variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" variant="primary">
            {isEdit ? "Save" : "Add"}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
