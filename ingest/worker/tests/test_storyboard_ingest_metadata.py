import unittest

import storyboard_ingest as si


class _StubRevision:
    def __init__(self):
        self.kref = "kref://demo/rev.kind?r=1"
        self.artifacts = []
        self.edges = []

    def create_artifact(self, name, location, metadata=None):
        artifact = type("Artifact", (), {"kref": "kref://demo/artifact.kind?r=1"})()
        self.artifacts.append((name, location, metadata))
        return artifact

    def create_edge(self, other_revision, edge_type, metadata=None):
        self.edges.append((getattr(other_revision, "kref", None), edge_type, metadata))


class _StubItem:
    def __init__(self, name, kind):
        self.name = name
        self.kind = kind
        self.kref = f"kref://demo/{name}.{kind}"
        self.revisions = []
        self.last_revision_metadata = None

    def create_revision(self, metadata=None):
        self.last_revision_metadata = metadata
        rev = _StubRevision()
        self.revisions.append(rev)
        return rev


class _StubSpace:
    def __init__(self, name):
        self.name = name


class _StubBundle:
    def __init__(self):
        self.kref = "kref://demo/bundle.bundle?r=1"
        self.metadata = None

    def add_member(self, item):
        return None

    def set_metadata(self, metadata):
        self.metadata = metadata

    def get_latest_revision(self):
        return None


class _StubProject:
    def __init__(self, name):
        self.name = name
        self._bundle = _StubBundle()

    def get_bundle(self, bundle_name, parent_path=None):
        return self._bundle

    def create_bundle(self, bundle_name, parent_path=None):
        return self._bundle


class _StubClient:
    def get_item_by_kref(self, kref):
        return None


class _StubKumiho:
    class EdgeType:
        DERIVED_FROM = "DERIVED_FROM"


class TestStoryboardIngestPanelPromptMetadata(unittest.TestCase):
    def test_panel_shot_description_is_written_as_prompt(self):
        created_items = []

        def ensure_project(_client, project_name, _description):
            return _StubProject(project_name)

        def ensure_space(_project, name, _parent_path):
            return _StubSpace(name)

        def ensure_item(_space, name, kind):
            item = _StubItem(name, kind)
            created_items.append(item)
            return item

        # Patch module-level imports used by storyboard_ingest.
        old_ensure_project = si.ensure_project
        old_ensure_space = si.ensure_space
        old_ensure_item = si.ensure_item
        old_kumiho = si.kumiho
        try:
            si.ensure_project = ensure_project
            si.ensure_space = ensure_space
            si.ensure_item = ensure_item
            si.kumiho = _StubKumiho

            payload = {
                "project_name": "demo",
                "contact_sheet_path": "C:/tmp/contacts.png",
                "panels": [
                    {
                        "path": "C:/tmp/panel-001.png",
                        "shot_code": "SH001",
                        "shot_description": "A wide establishing shot.",
                    }
                ],
            }

            result = si.storyboard_ingest(_StubClient(), payload)
            self.assertIn("panels", result)

            # We should have created at least: contact sheet item + one panel item.
            self.assertGreaterEqual(len(created_items), 2)

            panel_item = created_items[-1]
            metadata = panel_item.last_revision_metadata or {}

            self.assertEqual(metadata.get("prompt"), "A wide establishing shot.")
            self.assertNotIn("shot_description", metadata)
        finally:
            si.ensure_project = old_ensure_project
            si.ensure_space = old_ensure_space
            si.ensure_item = old_ensure_item
            si.kumiho = old_kumiho

    def test_artifact_name_uses_extension(self):
        self.assertEqual(si._artifact_name_from_path("C:/tmp/panel-001.PNG"), "png")
        self.assertEqual(si._artifact_name_from_path("/tmp/panel"), "panel")
        self.assertEqual(si._artifact_name_from_path(""), "artifact")


if __name__ == "__main__":
    unittest.main()
