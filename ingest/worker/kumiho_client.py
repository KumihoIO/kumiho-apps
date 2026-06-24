import importlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import base64
from pathlib import Path
from typing import List, Optional


_DEBUG_LOGS_ENABLED = os.environ.get("KUMIHO_DEBUG_LOGS", "0").lower() in {"1", "true", "yes"}


def _safe_stderr_log(message: str, payload=None):
    if not _DEBUG_LOGS_ENABLED:
        return
    try:
        if payload is None:
            sys.stderr.write(message + "\n")
        else:
            sys.stderr.write(message + " " + json.dumps(payload, ensure_ascii=False) + "\n")
        sys.stderr.flush()
    except Exception:
        pass


def _looks_like_local_target(value: Optional[str]) -> bool:
    if not value:
        return False
    lower = value.lower()
    return "127.0.0.1" in lower or "localhost" in lower


def _credential_paths() -> List[Path]:
    # Prefer the worker's isolated config dir (set by the Tauri host process).
    paths: List[Path] = []
    config_dir = os.environ.get("KUMIHO_CONFIG_DIR")
    if config_dir:
        paths.append(Path(config_dir).expanduser() / "kumiho_authentication.json")
    # Also allow the default SDK CLI location for dev convenience.
    paths.append(Path.home() / ".kumiho" / "kumiho_authentication.json")
    return paths


def _credentials_path_for_config_dir() -> Optional[Path]:
    config_dir = os.environ.get("KUMIHO_CONFIG_DIR")
    if not config_dir:
        return None
    return Path(config_dir).expanduser() / "kumiho_authentication.json"


def _sync_home_credentials_into_config_dir() -> None:
    """Ensure the worker-scoped KUMIHO_CONFIG_DIR has a credentials file.

    The upstream SDK loads credentials from KUMIHO_CONFIG_DIR; in our app we also
    want to support developer credentials stored at ~/.kumiho.
    """

    target = _credentials_path_for_config_dir()
    if not target:
        return
    if target.exists():
        return

    # Copy from HOME if present.
    home_path = Path.home() / ".kumiho" / "kumiho_authentication.json"
    if not home_path.exists():
        return
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(home_path.read_text(encoding="utf-8"), encoding="utf-8")
        _safe_stderr_log(
            "[kumiho-worker] credentials_sync",
            {"copied_from": str(home_path), "copied_to": str(target)},
        )
    except Exception:
        return


def _load_cached_id_token() -> Optional[str]:
    for path in _credential_paths():
        try:
            if not path.exists():
                continue
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                token = data.get("id_token")
                if isinstance(token, str) and token.strip():
                    return token.strip()
        except Exception:
            continue
    return None


def _load_cached_email() -> Optional[str]:
    for path in _credential_paths():
        try:
            if not path.exists():
                continue
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                email = data.get("email")
                if isinstance(email, str) and email.strip():
                    return email.strip()
        except Exception:
            continue
    return None


def _jwt_claims_unverified(token: str) -> dict:
    try:
        parts = token.split(".")
        if len(parts) != 3:
            return {}
        payload = parts[1]
        # base64url decode with padding
        padding = "=" * (-len(payload) % 4)
        decoded = base64.urlsafe_b64decode(payload + padding)
        data = json.loads(decoded.decode("utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _looks_like_control_plane_jwt(token: str) -> bool:
    claims = _jwt_claims_unverified(token)
    iss = str(claims.get("iss") or "")
    aud = claims.get("aud")
    # Heuristic: CP tokens tend to be issued by control.kumiho.cloud.
    if "control.kumiho.cloud" in iss:
        return True
    # Another heuristic: Firebase tokens have aud == Firebase project id.
    # If aud is a URL-ish string, it's likely not Firebase.
    if isinstance(aud, str) and aud.startswith("http"):
        return True
    return False


def _log_token_shape(label: str, token: str) -> None:
    claims = _jwt_claims_unverified(token)
    payload = {
        "iss": claims.get("iss"),
        "aud": claims.get("aud"),
        "exp": claims.get("exp"),
        "sub": claims.get("sub"),
    }
    _safe_stderr_log(label, payload)


def _read_cached_credentials() -> Optional[dict]:
    for path in _credential_paths():
        try:
            if not path.exists():
                continue
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return data
        except Exception:
            continue
    return None


def _refresh_firebase_id_token(*, api_key: str, refresh_token: str) -> dict:
    url = f"https://securetoken.googleapis.com/v1/token?key={urllib.parse.quote(api_key)}"
    body = urllib.parse.urlencode(
        {
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
        }
    ).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(req, timeout=15) as resp:
        raw = resp.read().decode("utf-8")
    data = json.loads(raw)
    if not isinstance(data, dict) or "id_token" not in data:
        raise RuntimeError("Unexpected refresh response")
    return data


def _ensure_firebase_token_available() -> Optional[str]:
    """Return a Firebase ID token, refreshing from cached credentials if needed.

    This is used to support the SDK discovery flow when the caller provided a
    Control Plane JWT instead of a Firebase ID token.
    """

    # If explicitly provided, prefer it.
    env_token = os.environ.get("KUMIHO_FIREBASE_ID_TOKEN")
    if isinstance(env_token, str) and env_token.strip():
        return env_token.strip()

    creds = _read_cached_credentials()
    if not creds:
        return None

    id_token = creds.get("id_token")
    if isinstance(id_token, str) and id_token.strip() and not _looks_like_control_plane_jwt(id_token):
        return id_token.strip()

    api_key = creds.get("api_key")
    refresh_token = creds.get("refresh_token")
    if not (isinstance(api_key, str) and api_key.strip() and isinstance(refresh_token, str) and refresh_token.strip()):
        return None

    refreshed = _refresh_firebase_id_token(api_key=api_key.strip(), refresh_token=refresh_token.strip())
    new_id_token = str(refreshed.get("id_token") or "").strip()
    new_refresh = str(refreshed.get("refresh_token") or "").strip()
    expires_in = int(refreshed.get("expires_in") or 3600)
    if new_id_token:
        creds["id_token"] = new_id_token
        if new_refresh:
            creds["refresh_token"] = new_refresh
        creds["expires_at"] = int(time.time()) + expires_in
        # Persist back to worker config dir (preferred) and HOME (dev convenience).
        targets: List[Path] = []
        cfg_path = _credentials_path_for_config_dir()
        if cfg_path:
            targets.append(cfg_path)
        targets.append(Path.home() / ".kumiho" / "kumiho_authentication.json")
        for path in targets:
            try:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(creds, indent=2), encoding="utf-8")
            except Exception:
                continue
        return new_id_token
    return None


def _resolve_discovery_record(
    *,
    token: str,
    tenant_hint: Optional[str],
    control_plane: Optional[str],
):
    discovery = importlib.import_module("kumiho.discovery")
    # Prefer the explicitly configured control plane to avoid any implicit defaults.
    manager = (
        discovery.DiscoveryManager(control_plane_url=control_plane)
        if control_plane
        else discovery.DiscoveryManager()
    )
    # IMPORTANT: keep discovery + data-plane identity consistent.
    # If the provided token is already a Firebase ID token (usual desktop flow),
    # use it as the Firebase token for discovery. Only reach for cached credentials
    # when the provided token looks like a true control-plane JWT.
    firebase_token = token
    if _looks_like_control_plane_jwt(token):
        firebase_token = _ensure_firebase_token_available() or token

    if firebase_token:
        os.environ["KUMIHO_FIREBASE_ID_TOKEN"] = firebase_token

    _log_token_shape("[kumiho-worker] ui_token_claims", token)
    if firebase_token and firebase_token != token:
        _log_token_shape("[kumiho-worker] cached_firebase_claims", firebase_token)

    record = manager.resolve(id_token=token, tenant_hint=tenant_hint, force_refresh=True)
    return record, firebase_token


def _connect_via_discovery_strict(
    *,
    kumiho,
    token: str,
    tenant_hint: Optional[str],
    control_plane: Optional[str],
):
    # Enforce control-plane discovery and bubble up discovery errors.
    discovery = importlib.import_module("kumiho.discovery")

    record, firebase_token = _resolve_discovery_record(
        token=token,
        tenant_hint=tenant_hint,
        control_plane=control_plane,
    )
    region = getattr(record, "region", None)
    grpc_authority = getattr(region, "grpc_authority", None) if region else None
    server_url = getattr(region, "server_url", None) if region else None
    _safe_stderr_log(
        "[kumiho-worker] discovery_record",
        {
            "tenant_id": getattr(record, "tenant_id", None),
            "tenant_name": getattr(record, "tenant_name", None),
            "grpc_authority": grpc_authority,
            "server_url": server_url,
        },
    )

    # Prefer grpc_authority but check both for safety.
    target = grpc_authority or server_url
    if _looks_like_local_target(target) or _looks_like_local_target(grpc_authority) or _looks_like_local_target(server_url):
        raise RuntimeError(
            "Discovery resolved to localhost/127.0.0.1 (grpc_authority/server_url). "
            "This indicates invalid tenant routing or a token mismatch; refusing to connect."
        )

    # IMPORTANT: use the same token identity that discovery used.
    # In our desktop app, discovery may succeed using cached credentials even
    # when the UI user token is different/unprivileged; if we then use the UI
    # token for data-plane calls, the server rejects with PERMISSION_DENIED.
    auth_token = firebase_token or token

    # Avoid interactive token prompts in a desktop/worker environment.
    client_mod = importlib.import_module("kumiho.client")
    client_cls = getattr(client_mod, "_Client")

    metadata = [("x-tenant-id", getattr(record, "tenant_id", ""))]
    return client_cls(
        target=target,
        auth_token=auth_token,
        default_metadata=metadata,
        enable_auto_login=False,
    )


class KumihoClient:
    def __init__(self):
        self._token = None
        self._client = None
        self._tenant_hint = None

    def set_auth_token(self, token):
        self._token = token
        self._client = None

    def connect(self, tenant_hint=None):
        if not self._token:
            raise RuntimeError("No auth token set.")

        # Ensure the worker-scoped config dir has credentials so the SDK can
        # refresh tokens without prompting.
        _sync_home_credentials_into_config_dir()

        kumiho = importlib.import_module("kumiho")
        self._tenant_hint = tenant_hint

        _safe_stderr_log(
            "[kumiho-worker] kumiho_sdk",
            {
                "module_file": getattr(kumiho, "__file__", None),
                "version": getattr(kumiho, "__version__", None),
            },
        )

        # Diagnostics: confirm which control plane + routing discovery resolves.
        control_plane = os.environ.get("KUMIHO_CONTROL_PLANE_URL") or os.environ.get(
            "CONTROL_PLANE_URL"
        )
        if control_plane:
            _safe_stderr_log("[kumiho-worker] control_plane", {"url": control_plane})
        cache_file = os.environ.get("KUMIHO_DISCOVERY_CACHE_FILE")
        if cache_file:
            _safe_stderr_log("[kumiho-worker] discovery_cache", {"file": cache_file})

        # Prefer strict discovery (no silent fallback to localhost).
        try:
            self._client = _connect_via_discovery_strict(
                kumiho=kumiho,
                token=self._token,
                tenant_hint=tenant_hint,
                control_plane=control_plane,
            )
        except Exception as exc:  # noqa: BLE001
            cached_token = _load_cached_id_token()
            cached_email = _load_cached_email()
            if cached_token and cached_token != self._token:
                _safe_stderr_log(
                    "[kumiho-worker] discovery failed with UI token; retrying with cached SDK credentials",
                    {"email": cached_email or "<unknown>", "error": f"{type(exc).__name__}: {exc}"},
                )
                try:
                    self._client = _connect_via_discovery_strict(
                        kumiho=kumiho,
                        token=cached_token,
                        tenant_hint=tenant_hint,
                        control_plane=control_plane,
                    )
                except Exception as exc2:  # noqa: BLE001
                    raise RuntimeError(
                        "Discovery failed for both UI token and cached SDK token. "
                        "Run 'kumiho-auth login' (SDK) to refresh credentials, or verify the desktop app is using the same Firebase project as the control plane. "
                        f"UI token discovery error: {type(exc).__name__}: {exc}. "
                        f"Cached token discovery error: {type(exc2).__name__}: {exc2}."
                    )
            else:
                raise RuntimeError(
                    "Discovery failed with the UI Firebase token and no cached SDK credentials were found. "
                    "Run 'kumiho-auth login' to create ~/.kumiho/kumiho_authentication.json, or verify the Firebase project configuration in the desktop UI. "
                    f"Discovery error: {type(exc).__name__}: {exc}."
                )

        # After strict discovery, tenant info should be available in the cache.
        info = kumiho.get_tenant_info(tenant_hint=tenant_hint)
        region = (info or {}).get("region") or {}
        _safe_stderr_log(
            "[kumiho-worker] tenant_routing",
            {
                "tenant_id": (info or {}).get("tenant_id"),
                "tenant_name": (info or {}).get("tenant_name"),
                "region": region,
            },
        )

        return self._client

    def get_client(self, tenant_hint=None):
        if self._client is None:
            return self.connect(tenant_hint=tenant_hint)
        if tenant_hint and tenant_hint != self._tenant_hint:
            return self.connect(tenant_hint=tenant_hint)
        return self._client
