import { useNavigate } from "react-router";
import { useDatabase } from "../context/DatabaseContext";
import { useToast } from "@vcdb/ui-kit/toast";
import { ConnectionManager, type DatabaseInfo } from "./components";

export function RegistryPage() {
  const navigate = useNavigate();
  const { selectDatabase } = useDatabase();
  const { showToast } = useToast();

  const handleSelect = (database: DatabaseInfo) => {
    selectDatabase(database.name);
    showToast(`Connected to ${database.name}`, "success");
    navigate("/explorer");
  };

  return (
    <ConnectionManager
      mode="full"
      onSelect={handleSelect}
    />
  );
}
