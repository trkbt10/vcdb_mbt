import { useState, useEffect } from "react";
import { Modal, Input, Button, Select } from "@/components/ui";
import type {
  EmbeddingStrategy,
  DatabaseEmbeddingConfig,
} from "../../../../server/types";
import styles from "./EmbeddingConfigModal.module.css";

type EmbeddingConfigModalProps = {
  open: boolean;
  databaseName: string;
  currentConfig: DatabaseEmbeddingConfig | null;
  onClose: () => void;
  onSubmit: (config: DatabaseEmbeddingConfig) => Promise<void>;
};

export function EmbeddingConfigModal({
  open,
  databaseName,
  currentConfig,
  onClose,
  onSubmit,
}: EmbeddingConfigModalProps) {
  const [strategy, setStrategy] = useState<EmbeddingStrategy>("none");
  const [apiKeyEnv, setApiKeyEnv] = useState("OPENAI_API_KEY");
  const [model, setModel] = useState("text-embedding-3-small");
  const [baseURL, setBaseURL] = useState("");
  const [endpointURL, setEndpointURL] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Initialize form from current config
  useEffect(() => {
    if (!currentConfig) {
      return;
    }
    setStrategy(currentConfig.strategy);

    if (currentConfig.strategy === "openai") {
      setApiKeyEnv(currentConfig.config.apiKeyEnv ?? "OPENAI_API_KEY");
      setModel(currentConfig.config.model ?? "text-embedding-3-small");
      setBaseURL(currentConfig.config.baseURL ?? "");
    } else if (currentConfig.strategy === "custom") {
      setEndpointURL(currentConfig.config.endpointURL);
    }
  }, [currentConfig, open]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setIsSubmitting(true);

    try {
      let config: DatabaseEmbeddingConfig;

      switch (strategy) {
        case "none":
          config = { strategy: "none" };
          break;
        case "hash":
          config = { strategy: "hash" };
          break;
        case "openai":
          config = {
            strategy: "openai",
            config: {
              provider: "openai",
              apiKeyEnv: apiKeyEnv || undefined,
              model: model || undefined,
              baseURL: baseURL || undefined,
            },
          };
          break;
        case "custom":
          if (!endpointURL) {
            throw new Error("Endpoint URL is required for custom strategy");
          }
          config = {
            strategy: "custom",
            config: {
              provider: "custom",
              endpointURL,
            },
          };
          break;
        default:
          throw new Error(`Unknown strategy: ${strategy}`);
      }

      await onSubmit(config);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save configuration");
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
    <Modal open={open} onClose={handleClose} title={`Embedding Config: ${databaseName}`}>
      <form onSubmit={handleSubmit} className={styles.form}>
        {error && <div className={styles.error}>{error}</div>}

        <div className={styles.strategyInfo}>
          <p className={styles.description}>
            Configure how text is converted to vectors for semantic search.
          </p>
        </div>

        <Select
          value={strategy}
          onChange={(e) => setStrategy(e.target.value as EmbeddingStrategy)}
          disabled={isSubmitting}
          options={[
            { value: "none", label: "None (Manual vectors only)" },
            { value: "hash", label: "Hash (Lightweight, offline)" },
            { value: "openai", label: "OpenAI API" },
            { value: "custom", label: "Custom Endpoint" },
          ]}
        />

        {strategy === "hash" && (
          <div className={styles.strategyInfo}>
            <p className={styles.hint}>
              Hash embedding uses feature hashing to convert text to vectors locally.
              Works offline without any external API. Best for quick testing.
            </p>
          </div>
        )}

        {strategy === "openai" && (
          <>
            <Input
              label="API Key Environment Variable"
              value={apiKeyEnv}
              onChange={(e) => setApiKeyEnv(e.target.value)}
              placeholder="OPENAI_API_KEY"
              disabled={isSubmitting}
            />
            <Input
              label="Model"
              value={model}
              onChange={(e) => setModel(e.target.value)}
              placeholder="text-embedding-3-small"
              disabled={isSubmitting}
            />
            <Input
              label="Base URL (optional)"
              value={baseURL}
              onChange={(e) => setBaseURL(e.target.value)}
              placeholder="https://api.openai.com/v1"
              disabled={isSubmitting}
            />
            <div className={styles.strategyInfo}>
              <p className={styles.hint}>
                Uses OpenAI&apos;s embedding API. Set the API key via environment variable.
              </p>
            </div>
          </>
        )}

        {strategy === "custom" && (
          <>
            <Input
              label="Endpoint URL"
              value={endpointURL}
              onChange={(e) => setEndpointURL(e.target.value)}
              placeholder="http://localhost:8000/embed"
              required
              disabled={isSubmitting}
            />
            <div className={styles.strategyInfo}>
              <p className={styles.hint}>
                POST endpoint that accepts {`{ "text": "..." }`} and returns {`{ "embedding": [...] }`}
              </p>
            </div>
          </>
        )}

        <div className={styles.actions}>
          <Button type="button" variant="ghost" onClick={handleClose} disabled={isSubmitting}>
            Cancel
          </Button>
          <Button type="submit" variant="primary" loading={isSubmitting}>
            Save
          </Button>
        </div>
      </form>
    </Modal>
  );
}
