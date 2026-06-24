from ingest import ensure_item, ensure_project, ensure_space, _build_storage_path
from storyboard import build_bundle_metadata
from image_metadata import get_metadata_for_revision, get_workflow_json
import os
import re
import shutil
from datetime import datetime

import kumiho


def _bundle_parent_path(project_name, space_name, space_parent_path):
    if not space_name:
        return f"/{project_name}"
    base = space_parent_path or f"/{project_name}"
    return f"{base.rstrip('/')}/{space_name}"


def _space_full_path(parent_path, name):
    return f"{parent_path.rstrip('/')}/{name}"


def _safe_text(value):
    if value is None:
        return None
    try:
        text = str(value)
    except Exception:
        return None
    return text.encode("utf-8", "replace").decode("utf-8")


def _strip_project_prefix(path, project_name):
    """Remove project name from the beginning of a path like /projectName/rest -> /rest"""
    if not path:
        return ""
    # Split path and remove empty segments
    segments = [s for s in re.split(r"[\\/]+", path.strip()) if s]
    # If first segment matches project name, remove it
    if segments and segments[0] == project_name:
        segments = segments[1:]
    # Return as path or empty string
    return "/" + "/".join(segments) if segments else ""


def _artifact_name_from_path(path):
    filename = os.path.basename(path) if path else ""
    _, extension = os.path.splitext(filename)
    normalized = extension.lstrip(".").lower()
    if normalized:
        return normalized
    if filename:
        return filename
    return "artifact"


def _get_unique_filename(target_dir, original_filename):
    """Generate a unique filename by adding datetime suffix if file already exists."""
    target_path = os.path.join(target_dir, original_filename)
    if not os.path.exists(target_path):
        return original_filename

    # File exists, add datetime suffix
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    name, ext = os.path.splitext(original_filename)
    return f"{name}_{timestamp}{ext}"


def storyboard_ingest(client, payload):
    project_name = payload.get("project_name")
    if not project_name:
        raise ValueError("project_name is required")
    space_name = payload.get("space_name", "storyboards")
    space_parent_path = payload.get("space_parent_path")
    bundle_name = payload.get("bundle_name", "storyboard-sequence")
    raw_bundle_tags = payload.get("bundle_tags", payload.get("bundle_tag", ""))
    source = payload.get("source", {})

    contact_sheet_path = payload.get("contact_sheet_path")
    if not contact_sheet_path:
        raise ValueError("contact_sheet_path is required")

    panels = payload.get("panels") or []
    if not panels:
        raise ValueError("panels list is required")

    move_files = payload.get("move_files", False)
    move_root = payload.get("move_root") if move_files else None
    if move_files and not move_root:
        raise ValueError("move_root is required when move_files is true")

    project = ensure_project(client, project_name, payload.get("project_description", ""))
    sequence_parent_path = space_parent_path or f"/{project_name}"
    sequence_space = ensure_space(project, space_name, sequence_parent_path)
    sequence_full_path = _space_full_path(sequence_parent_path, space_name)

    contact_sheet_name = payload.get("contact_sheet_name") or "storyboard.contactsheet"

    contact_sheet_kind = payload.get("contact_sheet_kind", "storyboard_contact_sheet")
    contact_sheet_item = ensure_item(sequence_space, contact_sheet_name, contact_sheet_kind)

    # Build contact sheet revision metadata with image dimensions and extracted metadata
    contact_sheet_metadata = dict(payload.get("revision_metadata") or {})

    # Extract PNG metadata (dimensions, ComfyUI workflow settings, etc.)
    try:
        extracted_meta = get_metadata_for_revision(contact_sheet_path)
        for key, value in extracted_meta.items():
            if key not in contact_sheet_metadata:  # Don't overwrite explicit metadata
                contact_sheet_metadata[key] = value
    except Exception:
        pass

    # Fallback to source-provided dimensions if not extracted
    image_width = source.get("image_width")
    image_height = source.get("image_height")
    if image_width is not None and "width" not in contact_sheet_metadata:
        contact_sheet_metadata["width"] = _safe_text(image_width)
    if image_height is not None and "height" not in contact_sheet_metadata:
        contact_sheet_metadata["height"] = _safe_text(image_height)

    contact_sheet_revision = contact_sheet_item.create_revision(
        metadata=contact_sheet_metadata or None
    )

    contact_sheet_artifact_path = contact_sheet_path
    if move_files:
        # Strip project name from space_parent_path to avoid duplication in storage path
        relative_parent = _strip_project_prefix(space_parent_path, project_name)
        target_dir = _build_storage_path(
            move_root, project_name, relative_parent, space_name
        )
        os.makedirs(target_dir, exist_ok=True)
        unique_filename = _get_unique_filename(target_dir, os.path.basename(contact_sheet_path))
        target_path = os.path.join(target_dir, unique_filename)
        shutil.move(contact_sheet_path, target_path)
        contact_sheet_artifact_path = target_path

    # Build artifact metadata with role and optional workflow JSON
    contact_sheet_artifact_metadata = {"role": "contact_sheet"}
    try:
        workflow_json = get_workflow_json(contact_sheet_path)
        if workflow_json:
            contact_sheet_artifact_metadata["comfyui_workflow"] = workflow_json
    except Exception:
        pass

    contact_sheet_artifact = contact_sheet_revision.create_artifact(
        name=os.path.basename(contact_sheet_path),
        location=contact_sheet_artifact_path,
        metadata=contact_sheet_artifact_metadata,
    )

    results = []
    for index, entry in enumerate(panels):
        path = entry.get("path")
        if not path:
            raise ValueError("panel entry missing path")
        shot_code = (
            _safe_text(entry.get("shot_code") or entry.get("shot_name") or entry.get("name") or "") or ""
        ).strip() or f"{index + 1:03d}"
        shot_name = shot_code
        shot_camera = (
            _safe_text(entry.get("shot_camera") or entry.get("kind") or "") or ""
        ).strip() or "storyboard_panel"
        shot_description = _safe_text(entry.get("shot_description", entry.get("description")))
        shot_index = entry.get("shot_index", entry.get("index", index))
        shot_width = entry.get("shot_width", entry.get("width"))
        shot_height = entry.get("shot_height", entry.get("height"))
        shot_type = (_safe_text(entry.get("shot_type")) or "").strip() or None
        camera_angle = (_safe_text(entry.get("camera_angle")) or "").strip() or None
        camera_move = (_safe_text(entry.get("camera_move")) or "").strip() or None

        item_name = (_safe_text(entry.get("item_name")) or "").strip()
        if not item_name:
            item_name = shot_name or "storyboard"

        item_kind = (_safe_text(entry.get("item_kind")) or "").strip() or "shotdesign"

        shot_space = ensure_space(project, shot_code, sequence_full_path)
        item = ensure_item(shot_space, item_name, item_kind)

        revision_metadata = dict(payload.get("revision_metadata") or {})

        # Extract PNG metadata (dimensions, ComfyUI workflow settings, etc.) for each panel
        try:
            extracted_meta = get_metadata_for_revision(path)
            for key, value in extracted_meta.items():
                if key not in revision_metadata:  # Don't overwrite explicit metadata
                    revision_metadata[key] = value
        except Exception:
            pass

        # Add shot-specific metadata (these override extracted values)
        revision_metadata["shot_name"] = shot_name
        revision_metadata["shot_code"] = shot_code
        revision_metadata["shot_camera"] = shot_camera
        if shot_type is not None:
            revision_metadata["shot_type"] = shot_type
        if camera_angle is not None:
            revision_metadata["camera_angle"] = camera_angle
        if camera_move is not None:
            revision_metadata["camera_move"] = camera_move
        if shot_description is not None:
            revision_metadata["prompt"] = _safe_text(shot_description)
        if shot_index is not None:
            revision_metadata["shot_index"] = _safe_text(shot_index)
        # Use explicit dimensions if provided, otherwise keep extracted ones
        if shot_width is not None:
            revision_metadata["width"] = _safe_text(shot_width)
        if shot_height is not None:
            revision_metadata["height"] = _safe_text(shot_height)

        revision = item.create_revision(metadata=revision_metadata or None)

        artifact_path = path
        if move_files:
            shot_space_parent = _space_full_path(sequence_parent_path, space_name)
            # Strip project name from shot_space_parent to avoid duplication in storage path
            relative_parent = _strip_project_prefix(shot_space_parent, project_name)
            target_dir = _build_storage_path(
                move_root, project_name, relative_parent, shot_code
            )
            os.makedirs(target_dir, exist_ok=True)
            unique_filename = _get_unique_filename(target_dir, os.path.basename(path))
            target_path = os.path.join(target_dir, unique_filename)
            shutil.move(path, target_path)
            artifact_path = target_path

        # Build artifact metadata, optionally including workflow JSON
        panel_artifact_metadata = dict(entry.get("artifact_metadata") or {})
        try:
            workflow_json = get_workflow_json(path)
            if workflow_json and "comfyui_workflow" not in panel_artifact_metadata:
                panel_artifact_metadata["comfyui_workflow"] = workflow_json
        except Exception:
            pass

        artifact = revision.create_artifact(
            name=entry.get("artifact_name") or _artifact_name_from_path(path),
            location=artifact_path,
            metadata=panel_artifact_metadata or None,
        )

        # Link each panel back to the source contact sheet revision.
        try:
            edge_metadata = {
                "panel_index": str(entry.get("index") if entry.get("index") is not None else len(results)),
                "rows": str(source.get("rows") or ""),
                "cols": str(source.get("cols") or ""),
                "shot_code": str(shot_name),
            }
            # Remove empty values (server-side metadata expects strings, but empty keys are noisy).
            edge_metadata = {k: v for k, v in edge_metadata.items() if v}
            revision.create_edge(contact_sheet_revision, kumiho.EdgeType.DERIVED_FROM, edge_metadata or None)
        except Exception:
            pass
        results.append(
            {
                "path": path,
                "item_kref": getattr(item, "kref", None),
                "revision_kref": getattr(revision, "kref", None),
                "artifact_kref": getattr(artifact, "kref", None),
                "artifact_path": artifact_path,
                "name": item_name,
                "kind": item_kind,
                "item_name": item_name,
                "item_kind": item_kind,
                "description": "" if shot_description is None else str(shot_description),
                "shot_name": shot_name,
                "shot_code": shot_code,
                "shot_camera": shot_camera,
                "shot_description": "" if shot_description is None else str(shot_description),
                "shot_index": str(shot_index) if shot_index is not None else None,
            }
        )

    bundle_parent = _bundle_parent_path(project.name, sequence_space.name, space_parent_path)
    try:
        bundle = project.get_bundle(bundle_name, parent_path=bundle_parent)
    except Exception:
        bundle = project.create_bundle(bundle_name, parent_path=bundle_parent)

    bundle_tags = []
    if isinstance(raw_bundle_tags, (list, tuple)):
        for tag in raw_bundle_tags:
            cleaned = (_safe_text(tag) or "").strip()
            if cleaned:
                bundle_tags.append(cleaned)
    else:
        cleaned = (_safe_text(raw_bundle_tags) or "").strip()
        if cleaned:
            bundle_tags = [tag.strip() for tag in re.split(r"[,\s]+", cleaned) if tag.strip()]
    if bundle_tags:
        bundle_tags = list(dict.fromkeys(bundle_tags))

    for entry in results:
        try:
            item_kref = entry.get("item_kref")
            if item_kref:
                item = client.get_item_by_kref(item_kref)
                bundle.add_member(item)
        except Exception:
            pass

    sequence = []
    for index, entry in enumerate(results):
        seq_index = index
        try:
            if panels[index].get("index") is not None:
                seq_index = int(panels[index].get("index"))
        except Exception:
            seq_index = index
        sequence.append(
            {
                "index": seq_index,
                "panel_ref": entry.get("revision_kref")
                or entry.get("item_kref")
                or entry.get("path"),
            }
        )

    metadata = build_bundle_metadata(source, sequence)
    bundle.set_metadata(metadata)

    if bundle_tags:
        try:
            latest_revision = bundle.get_latest_revision()
        except Exception:
            latest_revision = None
        if latest_revision is not None:
            for tag in bundle_tags:
                try:
                    latest_revision.tag(tag)
                except Exception:
                    pass

    return {"panels": results, "bundle_kref": getattr(bundle, "kref", None)}


def bundle_update_sequence(client, payload):
    project_name = payload.get("project_name")
    if not project_name:
        raise ValueError("project_name is required")
    space_name = payload.get("space_name", "storyboards")
    space_parent_path = payload.get("space_parent_path")
    bundle_name = payload.get("bundle_name", "storyboard-sequence")
    sequence = payload.get("sequence", [])
    source = payload.get("source", {})

    project = ensure_project(client, project_name, payload.get("project_description", ""))
    bundle_parent = _bundle_parent_path(project.name, space_name, space_parent_path)
    bundle = project.get_bundle(bundle_name, parent_path=bundle_parent)
    metadata = build_bundle_metadata(source, sequence)
    bundle.set_metadata(metadata)
    return {"ok": True}
