use keyring::Entry;
use serde_json::{json, Value};
use tauri::{AppHandle, State};

use crate::{python_env, AuthState, WorkerState};

#[tauri::command]
pub fn ensure_python_env(app: AppHandle) -> Result<python_env::PythonEnvInfo, String> {
  python_env::ensure_python_env(&app)
}

#[tauri::command]
pub fn start_python_worker(
  app: AppHandle,
  worker_state: State<WorkerState>,
  auth_state: State<AuthState>,
) -> Result<(), String> {
  python_env::start_worker(&app, &worker_state)?;
  python_env::send_worker_request(&worker_state, "ping", json!({}))?;
  let token = auth_state
    .0
    .lock()
    .map_err(|_| "auth state lock poisoned".to_string())?
    .clone();
  if let Some(token) = token {
    python_env::send_worker_request(
      &worker_state,
      "set_auth_token",
      json!({ "token": token }),
    )?;
  }
  Ok(())
}

#[tauri::command]
pub fn restart_python_worker(
  app: AppHandle,
  worker_state: State<WorkerState>,
  auth_state: State<AuthState>,
) -> Result<(), String> {
  python_env::stop_worker(&app, &worker_state)?;
  python_env::start_worker(&app, &worker_state)?;
  python_env::send_worker_request(&worker_state, "ping", json!({}))?;
  let token = auth_state
    .0
    .lock()
    .map_err(|_| "auth state lock poisoned".to_string())?
    .clone();
  if let Some(token) = token {
    python_env::send_worker_request(
      &worker_state,
      "set_auth_token",
      json!({ "token": token }),
    )?;
  }
  Ok(())
}

#[tauri::command]
pub fn update_kumiho_sdk(app: AppHandle) -> Result<python_env::PythonEnvInfo, String> {
  python_env::update_kumiho_sdk(&app)
}

fn keychain_entry() -> Result<Entry, String> {
  Entry::new("com.kumiho.ingest.studio", "firebase_id_token")
    .map_err(|err| format!("failed to init keychain entry: {err}"))
}

#[tauri::command]
pub fn store_auth_token_secure(token: String) -> Result<(), String> {
  let entry = keychain_entry()?;
  entry
    .set_password(&token)
    .map_err(|err| format!("failed to store token: {err}"))
}

#[tauri::command]
pub fn load_auth_token_secure() -> Result<Option<String>, String> {
  let entry = keychain_entry()?;
  match entry.get_password() {
    Ok(token) => Ok(Some(token)),
    Err(keyring::Error::NoEntry) => Ok(None),
    Err(err) => Err(format!("failed to load token: {err}")),
  }
}

#[tauri::command]
pub fn clear_auth_token_secure() -> Result<(), String> {
  let entry = keychain_entry()?;
  match entry.delete_password() {
    Ok(()) => Ok(()),
    Err(keyring::Error::NoEntry) => Ok(()),
    Err(err) => Err(format!("failed to clear token: {err}")),
  }
}

#[tauri::command]
pub fn set_auth_token(
  token: String,
  auth_state: State<AuthState>,
  worker_state: State<WorkerState>,
) -> Result<(), String> {
  let mut guard = auth_state
    .0
    .lock()
    .map_err(|_| "auth state lock poisoned".to_string())?;
  *guard = Some(token);
  let token = guard.clone().unwrap_or_default();
  if worker_state
    .0
    .lock()
    .map_err(|_| "worker state lock poisoned".to_string())?
    .is_some()
  {
    python_env::send_worker_request(
      &worker_state,
      "set_auth_token",
      json!({ "token": token }),
    )?;
  }
  Ok(())
}

#[tauri::command]
pub fn ingest_files(payload: Value, worker_state: State<WorkerState>) -> Result<Value, String> {
  python_env::send_worker_request(&worker_state, "ingest_files", payload)
}

#[tauri::command]
pub fn storyboard_ingest(
  payload: Value,
  worker_state: State<WorkerState>,
) -> Result<Value, String> {
  python_env::send_worker_request(&worker_state, "storyboard_ingest", payload)
}

#[tauri::command]
pub fn bundle_update_sequence(
  payload: Value,
  worker_state: State<WorkerState>,
) -> Result<Value, String> {
  python_env::send_worker_request(&worker_state, "bundle_update_sequence", payload)
}

#[tauri::command]
pub fn list_projects(payload: Value, worker_state: State<WorkerState>) -> Result<Value, String> {
  python_env::send_worker_request(&worker_state, "list_projects", payload)
}

#[tauri::command]
pub fn list_spaces(payload: Value, worker_state: State<WorkerState>) -> Result<Value, String> {
  python_env::send_worker_request(&worker_state, "list_spaces", payload)
}

#[tauri::command]
pub fn list_items(payload: Value, worker_state: State<WorkerState>) -> Result<Value, String> {
  python_env::send_worker_request(&worker_state, "list_items", payload)
}
