import json
import sys
import traceback

from kumiho_client import KumihoClient
from browse import list_items, list_projects, list_spaces
from ingest import ingest_files
from storyboard import build_sequence_metadata
from storyboard_ingest import bundle_update_sequence, storyboard_ingest


client = KumihoClient()


def handle_request(request):
    method = request.get("method")
    params = request.get("params", {})

    if method == "ping":
        return {"ok": True}
    if method == "set_auth_token":
        token = params.get("token")
        client.set_auth_token(token)
        return {"ok": True}
    if method == "list_projects":
        # Uses module-level SDK functions under the current connected client.
        return list_projects(client.get_client(tenant_hint=params.get("tenant_hint")), params)
    if method == "list_spaces":
        return list_spaces(client.get_client(tenant_hint=params.get("tenant_hint")), params)
    if method == "list_items":
        return list_items(client.get_client(tenant_hint=params.get("tenant_hint")), params)
    if method == "ingest_files":
        return ingest_files(client.get_client(), params)
    if method == "bundle_sequence_preview":
        source = params.get("source", {})
        sequence = params.get("sequence", [])
        return {"metadata": build_sequence_metadata(source, sequence)}
    if method == "storyboard_ingest":
        return storyboard_ingest(client.get_client(), params)
    if method == "bundle_update_sequence":
        return bundle_update_sequence(client.get_client(), params)

    return {"error": f"Unknown method: {method}"}




def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as exc:
            response = {"error": f"Invalid JSON: {exc}"}
        else:
            try:
                response = handle_request(request)
            except Exception as exc:  # noqa: BLE001
                response = {
                    "error": f"{type(exc).__name__}: {exc}",
                    "traceback": traceback.format_exc(),
                }
        sys.stdout.write(json.dumps(response) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
