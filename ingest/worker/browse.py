import importlib


def _with_kumiho(client):
    kumiho = importlib.import_module("kumiho")
    return kumiho, kumiho.use_client(client)


def _as_list(result):
    if result is None:
        return []
    if isinstance(result, list):
        return result
    try:
        return list(result)
    except TypeError:
        return [result]


def list_projects(client, payload):
    tenant_hint = payload.get("tenant_hint")
    active_client = client

    # If caller provides tenant_hint, reconnect via worker's KumihoClient.
    # (The Rust side can call set_auth_token + tenant selection, but this keeps
    # the API flexible without requiring UI changes.)
    try:
        if tenant_hint and hasattr(client, "connect"):
            active_client = client.connect(tenant_hint=tenant_hint)
    except Exception:
        active_client = client

    kumiho, ctx = _with_kumiho(active_client)
    with ctx:
        projects = _as_list(kumiho.get_projects())

    return {
        "projects": [
            {
                "name": getattr(p, "name", None),
                "description": getattr(p, "description", "") or "",
                "allow_public": bool(getattr(p, "allow_public", False)),
                "deprecated": bool(getattr(p, "deprecated", False)),
                "project_id": getattr(p, "project_id", None),
            }
            for p in projects
            if getattr(p, "name", None)
        ]
    }


def list_spaces(client, payload):
    project_name = payload.get("project_name")
    if not project_name:
        raise ValueError("project_name is required")

    recursive = bool(payload.get("recursive", True))
    parent_path = payload.get("parent_path") or None

    kumiho, ctx = _with_kumiho(client)
    with ctx:
        project = kumiho.get_project(project_name)
        if not project:
            return {"spaces": []}
        spaces = _as_list(project.get_spaces(parent_path=parent_path, recursive=recursive))

    return {
        "spaces": [
            {
                "name": getattr(s, "name", None),
                "path": getattr(s, "path", None),
                "type": getattr(s, "type", None),
                "metadata": getattr(s, "metadata", {}) or {},
            }
            for s in spaces
            if getattr(s, "path", None)
        ]
    }


def list_items(client, payload):
    project_name = payload.get("project_name")
    if not project_name:
        raise ValueError("project_name is required")

    space_path = payload.get("space_path") or None
    item_name_filter = payload.get("item_name_filter") or ""
    kind_filter = payload.get("kind_filter") or ""

    kumiho, ctx = _with_kumiho(client)
    with ctx:
        project = kumiho.get_project(project_name)
        if not project:
            return {"items": []}

        if space_path:
            space = project.get_space(space_path)
            items = _as_list(
                space.get_items(item_name_filter=item_name_filter, kind_filter=kind_filter)
            )
        else:
            items = _as_list(project.get_items(name_filter=item_name_filter, kind_filter=kind_filter))

    return {
        "items": [
            {
                "kref": getattr(item, "kref", None),
                "item_name": getattr(item, "item_name", None),
                "kind": getattr(item, "kind", None),
                "name": getattr(item, "name", None),
                "project": getattr(item, "project", None),
                "space": getattr(item, "space", None),
                "metadata": getattr(item, "metadata", {}) or {},
            }
            for item in items
            if getattr(item, "item_name", None) and getattr(item, "kind", None)
        ]
    }
