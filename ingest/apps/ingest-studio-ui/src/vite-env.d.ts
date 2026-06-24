/// <reference types="vite/client" />

type ViteEnvString = string;

declare interface ImportMetaEnv {
  readonly VITE_FIREBASE_API_KEY: ViteEnvString;
  readonly VITE_FIREBASE_AUTH_DOMAIN: ViteEnvString;
  readonly VITE_FIREBASE_PROJECT_ID: ViteEnvString;
  readonly VITE_FIREBASE_APP_ID: ViteEnvString;
  readonly VITE_FIREBASE_STORAGE_BUCKET?: ViteEnvString;
  readonly VITE_FIREBASE_MESSAGING_SENDER_ID?: ViteEnvString;
}

declare interface ImportMeta {
  readonly env: ImportMetaEnv;
}
