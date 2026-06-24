import argparse
import os
import sys

from kumiho_client import KumihoClient
from ingest import ingest_files
from storyboard_ingest import bundle_update_sequence, storyboard_ingest


def parse_args():
    parser = argparse.ArgumentParser(description="Kumiho ingest studio smoke test")
    parser.add_argument("--project", required=True, help="Project name")
    parser.add_argument("--space", default="assets", help="Space name")
    parser.add_argument("--file", action="append", default=[], help="File path to ingest")
    parser.add_argument("--bundle", default="storyboard-sequence", help="Bundle name")
    parser.add_argument("--panel", action="append", default=[], help="Panel file path")
    return parser.parse_args()


def main():
    args = parse_args()
    token = os.environ.get("KUMIHO_FIREBASE_ID_TOKEN")
    if not token:
        print("KUMIHO_FIREBASE_ID_TOKEN is required for smoke test.")
        sys.exit(1)

    client = KumihoClient()
    client.set_auth_token(token)
    kumiho_client = client.get_client()

    if args.file:
        ingest_payload = {
            "project_name": args.project,
            "space_name": args.space,
            "files": [{"path": path} for path in args.file],
        }
        ingest_result = ingest_files(kumiho_client, ingest_payload)
        print("Ingest result:", ingest_result)

    if args.panel:
        storyboard_payload = {
            "project_name": args.project,
            "space_name": args.space,
            "bundle_name": args.bundle,
            "source": {"type": "contact_sheet"},
            "panels": [{"path": path} for path in args.panel],
        }
        storyboard_result = storyboard_ingest(kumiho_client, storyboard_payload)
        print("Storyboard ingest result:", storyboard_result)

        sequence = [
            {"index": index, "panel_ref": panel.get("revision_kref") or panel.get("item_kref")}
            for index, panel in enumerate(storyboard_result.get("panels", []))
        ]
        sequence.reverse()
        update_payload = {
            "project_name": args.project,
            "space_name": args.space,
            "bundle_name": args.bundle,
            "source": {"type": "contact_sheet"},
            "sequence": sequence,
        }
        update_result = bundle_update_sequence(kumiho_client, update_payload)
        print("Bundle update result:", update_result)


if __name__ == "__main__":
    main()
