import json
import unittest

from storyboard import build_bundle_metadata, build_sequence_metadata


class TestStoryboardMetadata(unittest.TestCase):
    def test_sequence_metadata_structure(self):
        source = {
            "type": "contact_sheet",
            "rows": 3,
            "cols": 3,
            "margin_px": 8,
            "gutter_px": 4,
            "image_width": 300,
            "image_height": 300,
        }
        sequence = [{"index": 0, "panel_ref": "kref://demo/panel.image?r=1"}]
        payload = build_sequence_metadata(source, sequence)

        self.assertEqual(payload["sequence_version"], 1)
        self.assertEqual(payload["source"]["rows"], 3)
        self.assertEqual(payload["sequence"][0]["panel_ref"], sequence[0]["panel_ref"])

    def test_bundle_metadata_serializes_payload(self):
        source = {"rows": 2, "cols": 2}
        sequence = [{"index": 1, "panel_ref": "panel-2"}]
        metadata = build_bundle_metadata(source, sequence)

        self.assertEqual(metadata["kumiho_storyboard_sequence_version"], "1")
        parsed = json.loads(metadata["kumiho_storyboard_sequence_v1"])
        self.assertEqual(parsed["sequence"][0]["index"], 1)


if __name__ == "__main__":
    unittest.main()
