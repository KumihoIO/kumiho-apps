use serde::Serialize;
use serde_json::{json, Value};
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::{path::BaseDirectory, AppHandle, Emitter, Manager, State};

use crate::WorkerState;

#[derive(Debug, Serialize)]
pub struct PythonEnvInfo {
  pub app_data_dir: String,
  pub venv_dir: String,
  pub python_path: String,
  pub created: bool,
}

struct PythonCmd {
  exe: String,
  pre_args: Vec<String>,
}

pub struct WorkerProcess {
  child: Child,
  stdin: ChildStdin,
  stdout: BufReader<ChildStdout>,
}

#[derive(Clone, Serialize)]
struct LogPayload {
  level: String,
  message: String,
}

fn emit_log(app: &AppHandle, level: &str, message: impl Into<String>) {
  let payload = LogPayload {
    level: level.to_string(),
    message: message.into(),
  };
  let _ = app.emit("worker-log", payload);
}

fn normalize_control_plane_url(raw: &str) -> String {
  // The Python SDK expects KUMIHO_CONTROL_PLANE_URL to be the base host (or base /api),
  // because it appends /api/discovery/tenant internally.
  // If callers provide CONTROL_PLANE_URL that already includes /api/control-plane,
  // strip it back to the host root.
  let trimmed = raw.trim().trim_end_matches('/');
  trimmed
    .strip_suffix("/api/control-plane")
    .unwrap_or(trimmed)
    .to_string()
}

fn resolve_control_plane_url() -> String {
  if let Ok(value) = std::env::var("KUMIHO_CONTROL_PLANE_URL") {
    let value = value.trim().to_string();
    if !value.is_empty() {
      return normalize_control_plane_url(&value);
    }
  }

  if let Ok(value) = std::env::var("CONTROL_PLANE_URL") {
    let value = value.trim().to_string();
    if !value.is_empty() {
      return normalize_control_plane_url(&value);
    }
  }

  // Production default (base host, not /api/control-plane).
  "https://control.kumiho.cloud".to_string()
}

fn looks_like_local_url(url: &str) -> bool {
  let lower = url.to_ascii_lowercase();
  lower.contains("localhost") || lower.contains("127.0.0.1")
}

fn maybe_purge_localhost_discovery_cache(app: &AppHandle, cache_file: &Path, control_plane_url: &str) {
  // If the app is configured to use a remote control plane, but the discovery cache points
  // to localhost/127.0.0.1, it will keep re-resolving to the local endpoint.
  if looks_like_local_url(control_plane_url) {
    return;
  }

  if !cache_file.exists() {
    return;
  }

  let Ok(contents) = fs::read_to_string(cache_file) else {
    return;
  };

  if contents.contains("127.0.0.1") || contents.to_ascii_lowercase().contains("localhost") {
    if fs::remove_file(cache_file).is_ok() {
      emit_log(
        app,
        "info",
        format!(
          "Purged stale discovery cache pointing at localhost: {}",
          cache_file.display()
        ),
      );
    }
  }
}

pub fn ensure_python_env(app: &AppHandle) -> Result<PythonEnvInfo, String> {
  let app_data_dir = app
    .path()
    .app_data_dir()
    .map_err(|err| format!("unable to resolve app data dir: {err}"))?;
  fs::create_dir_all(&app_data_dir)
    .map_err(|err| format!("failed to create app data dir: {err}"))?;

  let venv_dir = app_data_dir.join("pyenv");
  let venv_cfg = venv_dir.join("pyvenv.cfg");
  let created = if !venv_cfg.exists() {
    create_venv(app, &venv_dir)?;
    true
  } else {
    false
  };

  let venv_python = venv_python_path(&venv_dir);
  if !venv_python.exists() {
    return Err("venv python was not found after creation".to_string());
  }

  let manifest_path = venv_dir.join("manifest.json");
  if created || !manifest_path.exists() {
    install_kumiho(&venv_python)?;
    update_manifest(&venv_python, &manifest_path)?;
  }

  Ok(PythonEnvInfo {
    app_data_dir: app_data_dir.to_string_lossy().to_string(),
    venv_dir: venv_dir.to_string_lossy().to_string(),
    python_path: venv_python.to_string_lossy().to_string(),
    created,
  })
}

pub fn start_worker(app: &AppHandle, worker_state: &State<WorkerState>) -> Result<(), String> {
  let mut guard = worker_state
    .0
    .lock()
    .map_err(|_| "worker state lock poisoned".to_string())?;
  if guard.is_some() {
    emit_log(app, "info", "Worker already running.");
    return Ok(());
  }

  emit_log(app, "info", "Starting Python worker...");
  let env_info = ensure_python_env(app)?;
  emit_log(
    app,
    "info",
    format!("Using Python at {}", env_info.python_path),
  );
  let worker_path = resolve_worker_path(app)?;
  let worker_dir = worker_path
    .parent()
    .ok_or_else(|| "worker path has no parent directory".to_string())?
    .to_path_buf();
  emit_log(
    app,
    "info",
    format!("Worker entrypoint {}", worker_path.display()),
  );

  let kumiho_dir = PathBuf::from(&env_info.app_data_dir).join("kumiho");
  fs::create_dir_all(&kumiho_dir)
    .map_err(|err| format!("failed to create kumiho config dir: {err}"))?;

  let control_plane_url = resolve_control_plane_url();
  emit_log(
    app,
    "info",
    format!("Using KUMIHO_CONTROL_PLANE_URL={control_plane_url}"),
  );

  let discovery_cache_file = kumiho_dir.join("discovery-cache.json");
  maybe_purge_localhost_discovery_cache(app, &discovery_cache_file, &control_plane_url);

  let mut command = Command::new(&env_info.python_path);
  command
    .arg("-u")
    .arg(worker_path)
    .current_dir(worker_dir)
    .env("KUMIHO_CONFIG_DIR", &kumiho_dir)
    .env("KUMIHO_DISCOVERY_CACHE_FILE", &discovery_cache_file)
    .env("KUMIHO_CONTROL_PLANE_URL", &control_plane_url)
    // Ensure we always use control-plane discovery (never a pinned local endpoint).
    .env("KUMIHO_FORCE_DISCOVERY_REFRESH", "1")
    .env_remove("KUMIHO_SERVER_ENDPOINT")
    .env_remove("KUMIHO_SERVER_ADDRESS")
    .env_remove("KUMIHO_DISABLE_AUTO_DISCOVERY")
    .stdin(Stdio::piped())
    .stdout(Stdio::piped())
    .stderr(Stdio::piped());

  let mut child = command
    .spawn()
    .map_err(|err| format!("failed to start python worker: {err}"))?;

  let stdin = child
    .stdin
    .take()
    .ok_or_else(|| "failed to open stdin for worker".to_string())?;
  let stdout = child
    .stdout
    .take()
    .ok_or_else(|| "failed to open stdout for worker".to_string())?;

  if let Some(stderr) = child.stderr.take() {
    let app_handle = app.clone();
    std::thread::spawn(move || {
      let reader = BufReader::new(stderr);
      for line in reader.lines().flatten() {
        eprintln!("[worker] {line}");
        emit_log(&app_handle, "error", line);
      }
    });
  }

  *guard = Some(WorkerProcess {
    child,
    stdin,
    stdout: BufReader::new(stdout),
  });
  emit_log(app, "info", "Worker process started.");
  Ok(())
}

pub fn stop_worker(app: &AppHandle, worker_state: &State<WorkerState>) -> Result<(), String> {
  let mut guard = worker_state
    .0
    .lock()
    .map_err(|_| "worker state lock poisoned".to_string())?;

  let mut worker = match guard.take() {
    Some(worker) => worker,
    None => {
      emit_log(app, "info", "Worker not running.");
      return Ok(());
    }
  };

  emit_log(app, "info", "Stopping Python worker...");

  match worker.child.try_wait() {
    Ok(Some(_status)) => {
      emit_log(app, "info", "Worker already exited.");
      return Ok(());
    }
    Ok(None) => {
      worker
        .child
        .kill()
        .map_err(|err| format!("failed to kill worker: {err}"))?;
      let _ = worker.child.wait();
      emit_log(app, "info", "Worker stopped.");
      Ok(())
    }
    Err(err) => Err(format!("failed to query worker status: {err}")),
  }
}

fn resolve_worker_path(app: &AppHandle) -> Result<PathBuf, String> {
  let resource_path = app
    .path()
    .resolve("worker/main.py", BaseDirectory::Resource)
    .map_err(|err| format!("unable to resolve worker/main.py resource: {err}"))?;
  if resource_path.exists() {
    return Ok(resource_path);
  }

  let dev_path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../worker/main.py");
  if dev_path.exists() {
    return Ok(dev_path);
  }

  Err(format!(
    "worker/main.py not found. Tried: {} and {}",
    resource_path.display(),
    dev_path.display()
  ))
}

pub fn update_kumiho_sdk(app: &AppHandle) -> Result<PythonEnvInfo, String> {
  let env_info = ensure_python_env(app)?;
  let venv_python = PathBuf::from(&env_info.python_path);
  install_kumiho(&venv_python)?;
  let manifest_path = PathBuf::from(&env_info.venv_dir).join("manifest.json");
  update_manifest(&venv_python, &manifest_path)?;
  Ok(env_info)
}

pub fn send_worker_request(
  worker_state: &State<WorkerState>,
  method: &str,
  params: Value,
) -> Result<Value, String> {
  let mut guard = worker_state
    .0
    .lock()
    .map_err(|_| "worker state lock poisoned".to_string())?;
  let worker = guard
    .as_mut()
    .ok_or_else(|| "worker is not running".to_string())?;

  let request = json!({
    "method": method,
    "params": params
  });

  let payload = serde_json::to_vec(&request)
    .map_err(|err| format!("failed to serialize request: {err}"))?;
  worker
    .stdin
    .write_all(&payload)
    .and_then(|_| worker.stdin.write_all(b"\n"))
    .map_err(|err| format!("failed to write to worker stdin: {err}"))?;
  worker
    .stdin
    .flush()
    .map_err(|err| format!("failed to flush worker stdin: {err}"))?;

  // Some third-party libs can (incorrectly) write to stdout. Since we use
  // line-delimited JSON over stdout, ignore any non-JSON lines until we get
  // a valid response object.
  let mut response_line = String::new();
  let mut attempts = 0;
  let response = loop {
    response_line.clear();
    let bytes = worker
      .stdout
      .read_line(&mut response_line)
      .map_err(|err| format!("failed to read worker response: {err}"))?;
    if bytes == 0 {
      return Err("worker exited while waiting for response".to_string());
    }
    if response_line.trim().is_empty() {
      continue;
    }

    match serde_json::from_str::<Value>(&response_line) {
      Ok(value) => break value,
      Err(err) => {
        attempts += 1;
        // Surface the unexpected stdout line for debugging, but keep going.
        eprintln!("[worker-stdout] {}", response_line.trim_end());
        if attempts >= 25 {
          return Err(format!(
            "failed to parse worker response after {attempts} lines: {err}"
          ));
        }
      }
    }
  };

  // The Python worker returns errors as a normal JSON object:
  // {"error": "...", "traceback": "..."}
  // Surface those as command failures so the UI hits its catch-path and doesn't
  // attempt to render invalid result shapes.
  if let Some(obj) = response.as_object() {
    if let Some(err_value) = obj.get("error") {
      let err_text = err_value
        .as_str()
        .map(|text| text.to_string())
        .unwrap_or_else(|| err_value.to_string());
      let trace = obj
        .get("traceback")
        .and_then(|value| value.as_str())
        .unwrap_or("");

      eprintln!("[worker-error] method={method} error={err_text}");
      if !trace.trim().is_empty() {
        // Keep stderr readable; traceback can be long.
        eprintln!("[worker-error-trace] {trace}");
      }

      if trace.trim().is_empty() {
        return Err(format!("worker error for {method}: {err_text}"));
      }
      return Err(format!("worker error for {method}: {err_text}\n{trace}"));
    }
  }

  Ok(response)
}

fn create_venv(app: &AppHandle, venv_dir: &Path) -> Result<(), String> {
  let python = find_python(app)
    .ok_or_else(|| "python not found (bundled or system python required)".to_string())?;

  fs::create_dir_all(venv_dir)
    .map_err(|err| format!("failed to create venv directory: {err}"))?;

  let mut command = Command::new(&python.exe);
  command
    .args(&python.pre_args)
    .arg("-m")
    .arg("venv")
    .arg(venv_dir);

  run_command(command, "creating venv")?;
  Ok(())
}

fn install_kumiho(venv_python: &Path) -> Result<(), String> {
  run_command_with_retry(
    || {
      let mut command = Command::new(venv_python);
      command.arg("-m").arg("pip").arg("install").arg("--upgrade").arg("pip");
      command
    },
    "upgrading pip",
    2,
  )?;

  run_command_with_retry(
    || {
      let mut command = Command::new(venv_python);
      command
        .arg("-m")
        .arg("pip")
        .arg("install")
        .arg("--upgrade")
        .arg("kumiho");
      command
    },
    "installing kumiho",
    2,
  )?;
  Ok(())
}

fn update_manifest(venv_python: &Path, path: &Path) -> Result<(), String> {
  let version = get_kumiho_version(venv_python).unwrap_or_else(|| "unknown".to_string());
  let timestamp = SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .map_err(|_| "failed to compute timestamp".to_string())?
    .as_secs();
  let manifest = json!({
    "kumiho_version": version,
    "updated_at": timestamp
  });
  fs::write(path, serde_json::to_vec_pretty(&manifest).unwrap())
    .map_err(|err| format!("failed to write manifest: {err}"))
}

fn get_kumiho_version(venv_python: &Path) -> Option<String> {
  let output = Command::new(venv_python)
    .arg("-c")
    .arg("import kumiho; print(kumiho.__version__)")
    .output()
    .ok()?;
  if !output.status.success() {
    return None;
  }
  let version = String::from_utf8_lossy(&output.stdout).trim().to_string();
  if version.is_empty() {
    None
  } else {
    Some(version)
  }
}

fn venv_python_path(venv_dir: &Path) -> PathBuf {
  if cfg!(windows) {
    venv_dir.join("Scripts").join("python.exe")
  } else {
    venv_dir.join("bin").join("python")
  }
}

fn find_python_on_path() -> Option<PythonCmd> {
  let candidates = vec![
    PythonCmd {
      exe: "python".to_string(),
      pre_args: vec![],
    },
    PythonCmd {
      exe: "python3".to_string(),
      pre_args: vec![],
    },
    PythonCmd {
      exe: "py".to_string(),
      pre_args: vec!["-3".to_string()],
    },
  ];

  for candidate in candidates {
    if probe_python(&candidate) {
      return Some(candidate);
    }
  }
  None
}

fn find_python(app: &AppHandle) -> Option<PythonCmd> {
  if let Some(bundled) = find_bundled_python(app) {
    return Some(bundled);
  }
  find_python_on_path()
}

fn find_bundled_python(app: &AppHandle) -> Option<PythonCmd> {
  let resource_root = app.path().resolve("python", BaseDirectory::Resource).ok()?;
  let mut candidates: Vec<PathBuf> = Vec::new();

  if cfg!(windows) {
    candidates.push(resource_root.join("windows").join("python.exe"));
    candidates.push(resource_root.join("windows").join("python3.exe"));
    candidates.push(resource_root.join("python.exe"));
  } else if cfg!(target_os = "macos") {
    candidates.push(resource_root.join("macos").join("bin").join("python3"));
    candidates.push(resource_root.join("macos").join("bin").join("python"));
    candidates.push(resource_root.join("bin").join("python3"));
  } else {
    candidates.push(resource_root.join("linux").join("bin").join("python3"));
    candidates.push(resource_root.join("linux").join("bin").join("python"));
    candidates.push(resource_root.join("bin").join("python3"));
  }

  for candidate in candidates {
    if candidate.exists() {
      return Some(PythonCmd {
        exe: candidate.to_string_lossy().to_string(),
        pre_args: vec![],
      });
    }
  }
  None
}

fn probe_python(candidate: &PythonCmd) -> bool {
  let output = Command::new(&candidate.exe)
    .args(&candidate.pre_args)
    .arg("--version")
    .output();
  match output {
    Ok(result) => result.status.success(),
    Err(_) => false,
  }
}

fn run_command(mut command: Command, label: &str) -> Result<(), String> {
  let output = command
    .output()
    .map_err(|err| format!("{label} failed to start: {err}"))?;
  if output.status.success() {
    Ok(())
  } else {
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    Err(format!(
      "{label} failed (exit {}):\nstdout: {stdout}\nstderr: {stderr}",
      output.status.code().unwrap_or(-1)
    ))
  }
}

fn run_command_with_retry<F>(build: F, label: &str, attempts: usize) -> Result<(), String>
where
  F: Fn() -> Command,
{
  let mut last_error: Option<String> = None;
  for attempt in 0..attempts {
    match run_command(build(), label) {
      Ok(()) => return Ok(()),
      Err(err) => last_error = Some(err),
    }
    if attempt + 1 == attempts {
      break;
    }
  }
  Err(last_error.unwrap_or_else(|| format!("{label} failed")))
}
