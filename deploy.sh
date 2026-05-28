#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# deploy.sh — push the local tracker HTML to GitHub Pages (main branch)
# Usage:  ./deploy.sh [--message "your commit message"]
# Requires: GITHUB_TOKEN env var with repo scope
# ---------------------------------------------------------------------------

OWNER="lucianoluz"
REPO="claude-pdp"
BRANCH="main"
REMOTE_PATH="index.html"
LIVE_URL="https://${OWNER}.github.io/${REPO}"
API_BASE="https://api.github.com/repos/${OWNER}/${REPO}/contents/${REMOTE_PATH}"

# --- parse arguments -------------------------------------------------------
COMMIT_MSG="Update PDP tracker"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --message|-m)
      COMMIT_MSG="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--message \"commit message\"]" >&2
      exit 1
      ;;
  esac
done

# --- validate environment --------------------------------------------------
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo ""
  echo "Error: GITHUB_TOKEN is not set."
  echo ""
  echo "Create a token at: https://github.com/settings/tokens"
  echo "  → Token type: Classic (or fine-grained with Contents: Read & Write)"
  echo "  → Scope needed: repo  (or just 'Contents' for fine-grained)"
  echo ""
  echo "Then run:"
  echo "  export GITHUB_TOKEN=ghp_yourtoken"
  echo "  ./deploy.sh"
  echo ""
  echo "To persist it across sessions, add the export line to ~/.bashrc or ~/.zshrc"
  exit 1
fi

# --- locate source file ----------------------------------------------------
# Prefer claude_pdp_tracker.html (Claude's output), fall back to index.html
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/claude_pdp_tracker.html" ]]; then
  SOURCE_FILE="${SCRIPT_DIR}/claude_pdp_tracker.html"
elif [[ -f "${SCRIPT_DIR}/index.html" ]]; then
  SOURCE_FILE="${SCRIPT_DIR}/index.html"
else
  echo "Error: No source file found." >&2
  echo "Expected: claude_pdp_tracker.html or index.html in the same directory as deploy.sh" >&2
  exit 1
fi

echo "Deploying: ${SOURCE_FILE}"
echo "  → ${OWNER}/${REPO}:${BRANCH}/${REMOTE_PATH}"
echo "  → Commit: \"${COMMIT_MSG}\""
echo ""

# --- base64-encode the file ------------------------------------------------
# macOS uses -b 0 flag; Linux just needs -w 0
if base64 --version 2>&1 | grep -q GNU; then
  ENCODED=$(base64 -w 0 < "${SOURCE_FILE}")
else
  ENCODED=$(base64 -b 0 < "${SOURCE_FILE}")
fi

# --- fetch current file SHA (needed for updates) ---------------------------
HTTP_STATUS=$(curl -s -o /tmp/deploy_get_response.json -w "%{http_code}" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "${API_BASE}?ref=${BRANCH}")

if [[ "$HTTP_STATUS" == "200" ]]; then
  CURRENT_SHA=$(jq -r '.sha' /tmp/deploy_get_response.json)
  echo "Found existing file (SHA: ${CURRENT_SHA:0:8}...)"
elif [[ "$HTTP_STATUS" == "404" ]]; then
  CURRENT_SHA=""
  echo "File does not exist yet — will create it."
elif [[ "$HTTP_STATUS" == "401" ]]; then
  echo "Error: Authentication failed. Check your GITHUB_TOKEN." >&2
  exit 1
else
  echo "Error: Unexpected response (HTTP ${HTTP_STATUS}) fetching current file." >&2
  cat /tmp/deploy_get_response.json >&2
  exit 1
fi

# --- build the JSON payload ------------------------------------------------
if [[ -n "$CURRENT_SHA" ]]; then
  PAYLOAD=$(printf '{"message":"%s","content":"%s","sha":"%s","branch":"%s"}' \
    "$COMMIT_MSG" "$ENCODED" "$CURRENT_SHA" "$BRANCH")
else
  PAYLOAD=$(printf '{"message":"%s","content":"%s","branch":"%s"}' \
    "$COMMIT_MSG" "$ENCODED" "$BRANCH")
fi

# --- push via GitHub Contents API ------------------------------------------
HTTP_STATUS=$(curl -s -o /tmp/deploy_put_response.json -w "%{http_code}" \
  -X PUT \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "${API_BASE}")

if [[ "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "201" ]]; then
  echo "Successfully pushed to GitHub!"
  echo ""
  echo "Live URL: ${LIVE_URL}"
  echo "(GitHub Pages usually updates within 30–60 seconds)"
else
  echo "Error: Push failed (HTTP ${HTTP_STATUS})." >&2
  cat /tmp/deploy_put_response.json >&2
  exit 1
fi

# clean up
rm -f /tmp/deploy_get_response.json /tmp/deploy_put_response.json
