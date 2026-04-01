import { useEffect, useCallback, useRef } from "react";

type KeyboardShortcut = {
  key: string;
  ctrl?: boolean;
  meta?: boolean;
  shift?: boolean;
  alt?: boolean;
  action: () => void;
  description?: string;
};

type UseKeyboardOptions = {
  shortcuts: KeyboardShortcut[];
  enabled?: boolean;
};

function matchesShortcut(e: KeyboardEvent, shortcut: KeyboardShortcut): boolean {
  const keyMatches = e.key.toLowerCase() === shortcut.key.toLowerCase();
  if (!keyMatches) {
    return false;
  }

  const shiftMatches = !!shortcut.shift === e.shiftKey;
  if (!shiftMatches) {
    return false;
  }

  const altMatches = !!shortcut.alt === e.altKey;
  if (!altMatches) {
    return false;
  }

  // If ctrl is specified, treat meta as equivalent (for Mac compatibility)
  if (shortcut.ctrl) {
    return e.ctrlKey || e.metaKey;
  }

  const ctrlMatches = !!shortcut.ctrl === (e.ctrlKey || e.metaKey);
  const metaMatches = !!shortcut.meta === e.metaKey;
  if (!ctrlMatches) {
    return false;
  }
  return metaMatches;
}

export function useKeyboard({ shortcuts, enabled = true }: UseKeyboardOptions) {
  const shortcutsRef = useRef(shortcuts);
  shortcutsRef.current = shortcuts;

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (!enabled) {
        return;
      }

      // Ignore if typing in an input field
      const target = e.target as HTMLElement;
      if (
        target.tagName === "INPUT" ||
        target.tagName === "TEXTAREA" ||
        target.isContentEditable
      ) {
        // Allow Escape in input fields
        if (e.key !== "Escape") {
          return;
        }
      }

      for (const shortcut of shortcutsRef.current) {
        if (matchesShortcut(e, shortcut)) {
          e.preventDefault();
          shortcut.action();
          return;
        }
      }
    },
    [enabled],
  );

  useEffect(() => {
    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [handleKeyDown]);
}

// Common shortcuts
export const SHORTCUTS = {
  search: { key: "k", ctrl: true, description: "Focus search" },
  escape: { key: "Escape", description: "Close modal / Clear selection" },
  refreshStats: { key: "s", ctrl: true, description: "Refresh collection stats" },
  refresh: { key: "r", ctrl: true, description: "Refresh" },
  next: { key: "j", description: "Next item" },
  prev: { key: "k", description: "Previous item" },
  help: { key: "?", shift: true, description: "Show shortcuts" },
} as const;
