mod commands;
mod python_env;

use std::sync::Mutex;

struct WorkerState(Mutex<Option<python_env::WorkerProcess>>);
struct AuthState(Mutex<Option<String>>);

fn main() {
  tauri::Builder::default()
    .manage(WorkerState(Mutex::new(None)))
    .manage(AuthState(Mutex::new(None)))
    .plugin(tauri_plugin_dialog::init())
    .plugin(tauri_plugin_fs::init())
    .plugin(tauri_plugin_updater::Builder::new().build())
    .plugin(tauri_plugin_process::init())
    .invoke_handler(tauri::generate_handler![
      commands::ensure_python_env,
      commands::update_kumiho_sdk,
      commands::set_local_server,
      commands::start_python_worker,
      commands::restart_python_worker,
      commands::set_auth_token,
      commands::store_auth_token_secure,
      commands::load_auth_token_secure,
      commands::clear_auth_token_secure,
      commands::list_projects,
      commands::list_spaces,
      commands::list_items,
      commands::ingest_files,
      commands::storyboard_ingest,
      commands::bundle_update_sequence
    ])
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
