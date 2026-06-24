import json


def build_sequence_metadata(source, sequence):
    return {
        "sequence_version": 1,
        "source": {
            "type": source.get("type", "contact_sheet"),
            "rows": source.get("rows", 0),
            "cols": source.get("cols", 0),
            "margin_px": source.get("margin_px", 0),
            "gutter_px": source.get("gutter_px", 0),
            "image_width": source.get("image_width", 0),
            "image_height": source.get("image_height", 0),
        },
        "sequence": sequence,
    }


def build_bundle_metadata(source, sequence):
    payload = build_sequence_metadata(source, sequence)
    return {
        "kumiho_storyboard_sequence_version": "1",
        "kumiho_storyboard_sequence_v1": json.dumps(payload),
    }
