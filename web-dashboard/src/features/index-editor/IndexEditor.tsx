import { useState, useEffect, useCallback } from "react";
import {
  Button,
  FormField,
  Input,
  Select,
  Section,
  OptionGrid,
  Toggle,
} from "@/components/ui";
import type {
  IndexConfig,
  VectorIndexConfig,
  AttributeIndexConfig,
  CombinedExecutionStrategy,
} from "vcdb/meta/index-types";
import { INDEX_NAME_PATTERN } from "vcdb/config/types-public";
import { VECTOR_STRATEGIES, ATTR_STRATEGIES, EXECUTION_OPTIONS } from "@/constants";
import { VectorParamsEditor } from "./VectorParamsEditor";
import { AttrParamsEditor } from "./AttrParamsEditor";
import { createDefaultField } from "./FieldDefsEditor";
import styles from "./IndexEditor.module.css";

export type IndexEditorEntry = {
  name: string;
  config: IndexConfig;
};

type IndexEditorProps = {
  onClose: () => void;
  onSave: (name: string, config: IndexConfig, originalName?: string) => void;
  existingNames: string[];
  editingEntry: IndexEditorEntry | null;
};

// Factory functions
export function createDefaultVectorIndex(): VectorIndexConfig {
  return { kind: "hnsw", metric: "cosine", M: 16, efConstruction: 200, efSearch: 50 };
}

export function createDefaultAttrIndex(): AttributeIndexConfig {
  return { kind: "bptree", fields: [createDefaultField()], order: "declared" };
}

function createDefaultVectorConfig(kind: VectorIndexConfig["kind"]): VectorIndexConfig {
  switch (kind) {
    case "bruteforce":
      return { kind: "bruteforce", metric: "cosine" };
    case "hnsw":
      return { kind: "hnsw", metric: "cosine", M: 16, efConstruction: 200, efSearch: 50 };
    case "ivf":
      return { kind: "ivf", metric: "cosine", nlist: 64, nprobe: 8 };
  }
}

function createDefaultAttrConfig(kind: AttributeIndexConfig["kind"]): AttributeIndexConfig {
  const defaultFields = [{ path: "category", type: "string" as const, ops: ["eq" as const] }];
  switch (kind) {
    case "basic":
      return { kind: "basic", fields: defaultFields };
    case "bitmap":
      return { kind: "bitmap", fields: defaultFields };
    case "bptree":
      return { kind: "bptree", fields: defaultFields, order: "declared" };
    case "lsm":
      return { kind: "lsm", fields: defaultFields, order: "declared" };
  }
}

function buildFinalConfig(
  attrEnabled: boolean,
  vectorConfig: VectorIndexConfig,
  attrConfig: AttributeIndexConfig,
  execution: CombinedExecutionStrategy
): IndexConfig {
  if (!attrEnabled) {
    return vectorConfig;
  }
  return {
    kind: "combined",
    vector: vectorConfig,
    attribute: attrConfig,
    execution,
  };
}

/** Extract state from existing config for editing */
function parseConfig(config: IndexConfig) {
  if (config.kind === "combined") {
    return {
      vectorConfig: config.vector,
      attrEnabled: true,
      attrConfig: config.attribute,
      execution: config.execution ?? "auto",
    };
  }
  // Vector-only config
  if (config.kind === "hnsw" || config.kind === "ivf" || config.kind === "bruteforce") {
    return {
      vectorConfig: config,
      attrEnabled: false,
      attrConfig: createDefaultAttrIndex(),
      execution: "auto" as const,
    };
  }
  // Attribute-only (rare case) - treat as combined with hnsw
  return {
    vectorConfig: createDefaultVectorIndex(),
    attrEnabled: true,
    attrConfig: config,
    execution: "auto" as const,
  };
}

export function IndexEditor({
  onClose,
  onSave,
  existingNames,
  editingEntry,
}: IndexEditorProps) {
  const [name, setName] = useState("");
  const [nameError, setNameError] = useState<string | null>(null);

  // Decomposed state for cleaner UI
  const [vectorConfig, setVectorConfig] = useState<VectorIndexConfig>(createDefaultVectorIndex());
  const [attrEnabled, setAttrEnabled] = useState(false);
  const [attrConfig, setAttrConfig] = useState<AttributeIndexConfig>(createDefaultAttrIndex());
  const [execution, setExecution] = useState<CombinedExecutionStrategy>("auto");

  const isEditing = editingEntry !== null;

  useEffect(() => {
    if (editingEntry) {
      setName(editingEntry.name);
      const parsed = parseConfig(editingEntry.config);
      setVectorConfig(parsed.vectorConfig);
      setAttrEnabled(parsed.attrEnabled);
      setAttrConfig(parsed.attrConfig);
      setExecution(parsed.execution);
    } else {
      // Generate unique name for new index
      let idx = 1;
      let newName = "index-1";
      while (existingNames.includes(newName)) {
        idx++;
        newName = `index-${idx}`;
      }
      setName(newName);
      setVectorConfig(createDefaultVectorIndex());
      setAttrEnabled(false);
      setAttrConfig(createDefaultAttrIndex());
      setExecution("auto");
    }
    setNameError(null);
  }, [editingEntry, existingNames]);

  const validateName = useCallback(
    (value: string): string | null => {
      if (!value.trim()) {
        return "Name is required";
      }
      if (!INDEX_NAME_PATTERN.test(value)) {
        return "Name must match [a-zA-Z0-9_-]+";
      }
      if (existingNames.includes(value)) {
        if (value !== editingEntry?.name) {
          return "An index with this name already exists";
        }
      }
      return null;
    },
    [existingNames, editingEntry]
  );

  const handleNameChange = (value: string) => {
    setName(value);
    setNameError(validateName(value));
  };

  const handleVectorKindChange = (kind: VectorIndexConfig["kind"]) => {
    setVectorConfig(createDefaultVectorConfig(kind));
  };

  const handleAttrKindChange = (kind: AttributeIndexConfig["kind"]) => {
    setAttrConfig(createDefaultAttrConfig(kind));
  };

  const handleSave = () => {
    const error = validateName(name);
    if (error) {
      setNameError(error);
      return;
    }

    // Build final config
    const finalConfig: IndexConfig = buildFinalConfig(attrEnabled, vectorConfig, attrConfig, execution);
    onSave(name, finalConfig, editingEntry?.name);
  };

  return (
    <div className={styles.panel}>
      <div className={styles.editorContent}>
        {/* Name Field */}
        <FormField label="Index Name" required error={nameError ?? undefined}>
          <Input
            value={name}
            onChange={(e) => handleNameChange(e.target.value)}
            placeholder="e.g., primary, product-search"
          />
        </FormField>

        {/* Vector Index Strategy */}
        <Section title="Vector Index Strategy">
          <OptionGrid
            options={VECTOR_STRATEGIES}
            value={vectorConfig.kind}
            onChange={handleVectorKindChange}
          />
        </Section>

        {/* Vector Parameters */}
        <VectorParamsEditor
          kind={vectorConfig.kind}
          config={vectorConfig}
          onChange={setVectorConfig}
        />

        {/* Attribute Filter Toggle */}
        <Toggle
          checked={attrEnabled}
          onChange={setAttrEnabled}
          label="Enable Attribute Filtering"
          description="Add metadata filtering to vector search (creates Combined index)"
        />

        {/* Attribute Config (shown when enabled) */}
        {attrEnabled && (
          <>
            <Section title="Attribute Index Strategy">
              <OptionGrid
                options={ATTR_STRATEGIES}
                value={attrConfig.kind}
                onChange={handleAttrKindChange}
              />
            </Section>

            <AttrParamsEditor
              kind={attrConfig.kind}
              config={attrConfig}
              onChange={setAttrConfig}
            />

            <FormField label="Execution Strategy" description="How to combine vector search with filtering">
              <Select
                value={execution}
                options={EXECUTION_OPTIONS}
                onChange={(e) => setExecution(e.target.value as CombinedExecutionStrategy)}
              />
            </FormField>
          </>
        )}
      </div>

      <div className={styles.editorFooter}>
        <Button variant="ghost" onClick={onClose}>
          Cancel
        </Button>
        <Button variant="primary" onClick={handleSave} disabled={!!nameError}>
          {isEditing ? "Save Changes" : "Add Index"}
        </Button>
      </div>
    </div>
  );
}
