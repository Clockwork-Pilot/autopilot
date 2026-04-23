#!/usr/bin/env bash
# Parses a docker manifest JSON and emits digest/image to $GITHUB_OUTPUT.
# Required env: MANIFEST_JSON, IMAGE_REPO, GITHUB_OUTPUT.
set -euo pipefail
: "${MANIFEST_JSON:?MANIFEST_JSON is required}"
: "${IMAGE_REPO:?IMAGE_REPO is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

echo "$MANIFEST_JSON" | python3 -c '
import json, os, sys
m = json.load(sys.stdin)
if m.get("manifests"):
    digest = m["manifests"][0].get("digest", "")
elif "config" in m:
    digest = m["config"].get("digest", "")
else:
    print("ERROR: no digest found in manifest", file=sys.stderr); sys.exit(1)
if not digest:
    print("ERROR: digest is empty", file=sys.stderr); sys.exit(1)
image_repo = os.environ["IMAGE_REPO"]
with open(os.environ["GITHUB_OUTPUT"], "a") as f:
    f.write(f"digest={digest}\n")
    f.write(f"image={image_repo}@{digest}\n")
'
