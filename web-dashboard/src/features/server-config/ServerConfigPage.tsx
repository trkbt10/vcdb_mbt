import { useState, useEffect } from "react";
import { useServerConfig } from "./hooks/useServerConfig";
import { Button, PageHeader, ArrowLeft, Input } from "@vcdb/ui-kit";
import { useToast } from "@vcdb/ui-kit/toast";
import styles from "./ServerConfigPage.module.css";

type ServerConfigPageProps = {
  onClose: () => void;
};

export function ServerConfigPage({ onClose }: ServerConfigPageProps) {
  const { config, loading, saving, error, update } = useServerConfig();
  const { showToast } = useToast();

  // Form state
  const [baseDir, setBaseDir] = useState("");
  const [port, setPort] = useState("");
  const [host, setHost] = useState("");
  const [hasChanges, setHasChanges] = useState(false);
  const [needsRestart, setNeedsRestart] = useState(false);

  // Initialize form from config
  useEffect(() => {
    if (config) {
      setBaseDir(config.baseDir);
      setPort(String(config.port));
      setHost(config.host);
      setHasChanges(false);
    }
  }, [config]);

  // Check for changes
  useEffect(() => {
    if (!config) {
      return;
    }
    const changed =
      baseDir !== config.baseDir ||
      port !== String(config.port) ||
      host !== config.host;
    setHasChanges(changed);
  }, [config, baseDir, port, host]);

  const handleSave = async () => {
    const portNum = parseInt(port, 10);
    if (isNaN(portNum) || portNum < 1 || portNum > 65535) {
      showToast("Port must be a valid number between 1 and 65535", "error");
      return;
    }

    try {
      // Check if port/host changed (needs restart)
      const portHostChanged =
        config && (portNum !== config.port || host !== config.host);

      await update({
        baseDir,
        port: portNum,
        host,
      });

      if (portHostChanged) {
        setNeedsRestart(true);
      }

      showToast("Configuration saved successfully", "success");
      setHasChanges(false);
    } catch {
      showToast("Failed to save configuration", "error");
    }
  };

  const handleReset = () => {
    if (config) {
      setBaseDir(config.baseDir);
      setPort(String(config.port));
      setHost(config.host);
      setHasChanges(false);
    }
  };

  if (loading) {
    return (
      <div className={styles.page}>
        <PageHeader
          title="Server Configuration"
          subtitle="Loading..."
          backButton={
            <button className={styles.backButton} onClick={onClose}>
              <ArrowLeft size={16} />
              <span>Back</span>
            </button>
          }
        />
      </div>
    );
  }

  if (error || !config) {
    return (
      <div className={styles.page}>
        <PageHeader
          title="Server Configuration"
          subtitle="Failed to load configuration"
          backButton={
            <button className={styles.backButton} onClick={onClose}>
              <ArrowLeft size={16} />
              <span>Back</span>
            </button>
          }
        />
        <div className={styles.content}>
          <div className={styles.error}>{error ?? "Configuration not available"}</div>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.page}>
      <PageHeader
        title="Server Configuration"
        subtitle="Configure dashboard server settings"
        backButton={
          <button className={styles.backButton} onClick={onClose}>
            <ArrowLeft size={16} />
            <span>Back</span>
          </button>
        }
      />

      <div className={styles.content}>
        {needsRestart && (
          <div className={styles.warning}>
            <strong>Restart Required</strong>
            <p>
              Port or host settings have changed. Please restart the server for
              these changes to take effect.
            </p>
          </div>
        )}

        <section className={styles.section}>
          <h2 className={styles.sectionTitle}>Storage</h2>

          <div className={styles.setting}>
            <div className={styles.settingInfo}>
              <label htmlFor="baseDir">Data Directory</label>
              <p className={styles.description}>
                Base directory for storing database files
              </p>
            </div>
            <div className={styles.inputGroup}>
              <Input
                id="baseDir"
                value={baseDir}
                onChange={(e) => setBaseDir(e.target.value)}
                placeholder="./.dashboard-data"
              />
            </div>
          </div>
        </section>

        <section className={styles.section}>
          <h2 className={styles.sectionTitle}>Network</h2>

          <div className={styles.setting}>
            <div className={styles.settingInfo}>
              <label htmlFor="host">Host</label>
              <p className={styles.description}>
                Network interface to bind to (0.0.0.0 for all interfaces)
              </p>
            </div>
            <div className={styles.inputGroup}>
              <Input
                id="host"
                value={host}
                onChange={(e) => setHost(e.target.value)}
                placeholder="0.0.0.0"
              />
            </div>
          </div>

          <div className={styles.setting}>
            <div className={styles.settingInfo}>
              <label htmlFor="port">Port</label>
              <p className={styles.description}>
                TCP port for the dashboard server
              </p>
            </div>
            <div className={styles.inputGroup}>
              <Input
                id="port"
                type="number"
                min={1}
                max={65535}
                value={port}
                onChange={(e) => setPort(e.target.value)}
                placeholder="8765"
              />
            </div>
          </div>
        </section>

        <div className={styles.actions}>
          <Button variant="ghost" onClick={handleReset} disabled={!hasChanges}>
            Reset
          </Button>
          <Button onClick={handleSave} disabled={!hasChanges || saving}>
            {saving ? "Saving..." : "Save Changes"}
          </Button>
        </div>
      </div>
    </div>
  );
}
