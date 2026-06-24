// Best-effort auto-update check for the Tauri desktop build.
//
// Dormant until the updater is activated: generate a keypair
// (`npx @tauri-apps/cli signer generate`), set the public key in
// src-tauri/tauri.conf.json (plugins.updater.pubkey), flip
// bundle.createUpdaterArtifacts to true, and add the private key as the
// TAURI_SIGNING_PRIVATE_KEY repo secret. Until then this is a safe no-op:
// the endpoint returns no manifest and any error is swallowed.

export async function checkForUpdates(): Promise<void> {
  // Only meaningful inside the Tauri shell; harmless in a plain browser/dev.
  if (typeof window === "undefined" || !("__TAURI_INTERNALS__" in window)) {
    return;
  }

  try {
    const { check } = await import("@tauri-apps/plugin-updater");
    const update = await check();
    if (!update?.available) return;

    const ok = window.confirm(
      `Kumiho Ingest Studio ${update.version} is available ` +
        `(you have ${update.currentVersion}). Download and install now?`,
    );
    if (!ok) return;

    await update.downloadAndInstall();

    const { relaunch } = await import("@tauri-apps/plugin-process");
    await relaunch();
  } catch (err) {
    // No manifest / not configured / offline — never block app startup.
    console.debug("Update check skipped:", err);
  }
}
