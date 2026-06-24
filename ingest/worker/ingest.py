import os
import re
import shutil
from datetime import datetime

from image_metadata import get_metadata_for_revision, get_workflow_json


def _is_image_file(path):
    """Check if a file is an image based on extension."""
    if not path:
        return False
    ext = os.path.splitext(path)[1].lower()
    return ext in {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp', '.tiff', '.tif'}


def _sanitize_segment(value):
    value = value.strip()
    if not value:
        return "unnamed"
    value = re.sub(r"[\\/]+", "_", value)
    return value or "unnamed"


def _segments_from_path(path_value):
    if not path_value:
        return []
    segments = re.split(r"[\\/]+", path_value.strip())
    return [_sanitize_segment(segment) for segment in segments if segment]


def _build_storage_path(root, project_name, space_parent_path, space_name):
    segments = [_sanitize_segment(project_name)]
    segments.extend(_segments_from_path(space_parent_path))
    segments.append(_sanitize_segment(space_name))
    return os.path.join(root, *segments)


def _get_unique_filename(target_dir, original_filename):
    """Generate a unique filename by adding datetime suffix if file already exists."""
    target_path = os.path.join(target_dir, original_filename)
    if not os.path.exists(target_path):
        return original_filename

    # File exists, add datetime suffix
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    name, ext = os.path.splitext(original_filename)
    return f"{name}_{timestamp}{ext}"



def ensure_project(client, name, description):
    project = client.get_project(name)
    if project is None:
        project = client.create_project(name, description or "")
    return project


def ensure_space(project, name, parent_path):
    try:
        return project.get_space(name, parent_path=parent_path)
    except Exception:
        return project.create_space(name, parent_path=parent_path)


def ensure_item(space, name, kind):
    try:
        return space.get_item(name, kind)
    except Exception:
        return space.create_item(name, kind)


def ingest_files(client, payload):
    project_name = payload.get("project_name")
    if not project_name:
        raise ValueError("project_name is required")

    project_description = payload.get("project_description", "")
    space_name = payload.get("space_name", "assets")
    space_parent_path = payload.get("space_parent_path")
    item_kind_default = payload.get("item_kind", "file")
    multi_file_mode = payload.get("multi_file_mode") or "per_file"
    batch_item_name = payload.get("item_name") or ""
    revision_metadata = payload.get("revision_metadata") or {}

    project = ensure_project(client, project_name, project_description)
    space = ensure_space(project, space_name, space_parent_path)

    results = []
    errors = []
    move_files = payload.get("move_files", False)
    move_root = payload.get("move_root") if move_files else None
    if move_files and not move_root:
        raise ValueError("move_root is required when move_files is true")

    files = payload.get("files") or []

    if multi_file_mode == "single_item":
        if not files:
            return {"ok": True, "count": 0, "results": [], "errors": []}

        if len(files) > 1 and not str(batch_item_name).strip():
            raise ValueError("item_name is required when multi_file_mode is single_item")

        first_path = (files[0] or {}).get("path")
        if not first_path:
            raise ValueError("file entry missing path")
        item_name = str(batch_item_name).strip() or os.path.splitext(os.path.basename(first_path))[0]
        # In batch mode, item kind comes from payload default.
        item = ensure_item(space, item_name, item_kind_default)

        # Build revision metadata, extracting from first image if available
        merged_revision_metadata = dict(revision_metadata or {})
        if _is_image_file(first_path):
            try:
                extracted_meta = get_metadata_for_revision(first_path)
                for key, value in extracted_meta.items():
                    if key not in merged_revision_metadata:
                        merged_revision_metadata[key] = value
            except Exception:
                pass

        revision = item.create_revision(metadata=merged_revision_metadata or None)

        for entry in files:
            path = entry.get("path")
            if not path:
                errors.append({"path": None, "error": "file entry missing path"})
                continue
            try:
                artifact_name = entry.get("artifact_name") or os.path.basename(path)
                artifact_metadata = dict(entry.get("artifact_metadata") or {})

                # Extract workflow JSON for PNG files
                if _is_image_file(path) and path.lower().endswith('.png'):
                    try:
                        workflow_json = get_workflow_json(path)
                        if workflow_json and "comfyui_workflow" not in artifact_metadata:
                            artifact_metadata["comfyui_workflow"] = workflow_json
                    except Exception:
                        pass

                artifact_path = path
                if move_files:
                    target_dir = _build_storage_path(
                        move_root, project_name, space_parent_path, space_name
                    )
                    os.makedirs(target_dir, exist_ok=True)
                    unique_filename = _get_unique_filename(target_dir, os.path.basename(path))
                    target_path = os.path.join(target_dir, unique_filename)
                    shutil.move(path, target_path)
                    artifact_path = target_path

                artifact = revision.create_artifact(
                    name=artifact_name,
                    location=artifact_path,
                    metadata=artifact_metadata or None,
                )

                results.append(
                    {
                        "path": path,
                        "item_kref": getattr(item, "kref", None),
                        "revision_kref": getattr(revision, "kref", None),
                        "artifact_kref": getattr(artifact, "kref", None),
                        "artifact_path": artifact_path,
                    }
                )
            except Exception as exc:
                errors.append({"path": path, "error": str(exc)})

    else:
        for entry in files:
            path = entry.get("path")
            if not path:
                errors.append({"path": None, "error": "file entry missing path"})
                continue
            try:
                file_name = entry.get("name") or os.path.splitext(os.path.basename(path))[0]
                item_kind = entry.get("kind") or item_kind_default
                artifact_name = entry.get("artifact_name") or os.path.basename(path)
                item_metadata = entry.get("item_metadata") or {}
                artifact_metadata = dict(entry.get("artifact_metadata") or {})

                item = ensure_item(space, file_name, item_kind)
                if item_metadata:
                    try:
                        item.set_metadata(item_metadata)
                    except Exception:
                        pass

                # Build revision metadata, extracting from image if available
                merged_revision_metadata = dict(revision_metadata or {})
                if _is_image_file(path):
                    try:
                        extracted_meta = get_metadata_for_revision(path)
                        for key, value in extracted_meta.items():
                            if key not in merged_revision_metadata:
                                merged_revision_metadata[key] = value
                    except Exception:
                        pass

                # Extract workflow JSON for PNG files into artifact metadata
                if _is_image_file(path) and path.lower().endswith('.png'):
                    try:
                        workflow_json = get_workflow_json(path)
                        if workflow_json and "comfyui_workflow" not in artifact_metadata:
                            artifact_metadata["comfyui_workflow"] = workflow_json
                    except Exception:
                        pass

                artifact_path = path
                if move_files:
                    target_dir = _build_storage_path(
                        move_root, project_name, space_parent_path, space_name
                    )
                    os.makedirs(target_dir, exist_ok=True)
                    unique_filename = _get_unique_filename(target_dir, os.path.basename(path))
                    target_path = os.path.join(target_dir, unique_filename)
                    shutil.move(path, target_path)
                    artifact_path = target_path

                revision = item.create_revision(metadata=merged_revision_metadata or None)
                artifact = revision.create_artifact(
                    name=artifact_name,
                    location=artifact_path,
                    metadata=artifact_metadata or None,
                )

                results.append(
                    {
                        "path": path,
                        "item_kref": getattr(item, "kref", None),
                        "revision_kref": getattr(revision, "kref", None),
                        "artifact_kref": getattr(artifact, "kref", None),
                        "artifact_path": artifact_path,
                    }
                )
            except Exception as exc:
                errors.append({"path": path, "error": str(exc)})

    return {
        "ok": len(errors) == 0,
        "count": len(results),
        "results": results,
        "errors": errors,
    }
