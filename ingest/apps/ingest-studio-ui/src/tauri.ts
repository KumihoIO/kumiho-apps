import { invoke } from "@tauri-apps/api/core";

export function isTauri(): boolean {
  if (typeof window === "undefined") {
    return false;
  }
  return Boolean(
    (window as { __TAURI_INTERNALS__?: unknown; __TAURI__?: unknown }).__TAURI_INTERNALS__ ??
      (window as { __TAURI_INTERNALS__?: unknown; __TAURI__?: unknown }).__TAURI__
  );
}

export async function callCommand<T>(
  command: string,
  payload?: Record<string, unknown>
): Promise<T> {
  if (!isTauri()) {
    throw new Error("Tauri APIs are not available in the browser preview.");
  }
  return invoke<T>(command, payload);
}
