#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════
# Court Booking Platform — GitHub Repository Setup Script
#
# Prerequisites:
#   - gh CLI installed and authenticated (gh auth login)
#   - All repos already created on GitHub
#
# Usage:
#   chmod +x scripts/setup-github-repos.sh
#   ./scripts/setup-github-repos.sh
#
# What this script does:
#   1. Adds collaborators to all repos
#   2. Creates develop branch on all repos
#   3. Sets develop as default branch
#   4. Configures branch protection for main and develop
#   5. Enables delete-branch-on-merge
#   6. Sets QA dispatch token secret on service repos
# ═══════════════════════════════════════════════════════════════════════

# ─── Configuration (EDIT THESE) ───────────────────────────────────────

ORG="kevag4"

COLLABORATOR_1="ikaryoti"
COLLABORATOR_2="nimitsis"

# Permission level: pull, push, maintain, admin
COLLABORATOR_PERMISSION="push"

# GitHub PAT with repo scope for cross-repo QA dispatch triggers
# Generate at: https://github.com/settings/tokens (classic) with "repo" scope
QA_DISPATCH_TOKEN=""

# ─── Repository Lists ────────────────────────────────────────────────

ALL_REPOS=(
  "court-booking-platform-service"
  "court-booking-transaction-service"
  "court-booking-mobile-app"
  "court-booking-admin-web"
  "court-booking-qa"
  "court-booking-infrastructure"
  "court-booking-common"
)

# Repos that deploy services and need to trigger QA workflows
SERVICE_REPOS=(
  "court-booking-platform-service"
  "court-booking-transaction-service"
  "court-booking-mobile-app"
  "court-booking-admin-web"
)

# CI job names that must pass before merge (adjust to match your workflow job names)
CI_CONTEXTS='["lint", "test", "build"]'

# ─── Helper ──────────────────────────────────────────────────────────

log() { echo -e "\n\033[1;34m▸ $1\033[0m"; }
ok()  { echo "  ✓ $1"; }
err() { echo "  ✗ $1" >&2; }


# ─── Preflight Checks ────────────────────────────────────────────────

log "Preflight checks"

if ! command -v gh &> /dev/null; then
  err "gh CLI not found. Install: https://cli.github.com/"
  exit 1
fi

if ! gh auth status &> /dev/null; then
  err "gh CLI not authenticated. Run: gh auth login"
  exit 1
fi

if [[ "$ORG" == "your-org-or-username" ]]; then
  err "Edit the script first: set ORG, COLLABORATOR_1, COLLABORATOR_2"
  exit 1
fi

ok "gh CLI authenticated"

# ─── Step 1: Add Collaborators ───────────────────────────────────────

log "Step 1: Adding collaborators to all repos"

for REPO in "${ALL_REPOS[@]}"; do
  for COLLAB in "$COLLABORATOR_1" "$COLLABORATOR_2"; do
    if [[ "$COLLAB" == "collaborator-username-"* ]]; then
      err "Skipping placeholder collaborator: $COLLAB"
      continue
    fi
    if gh api "repos/$ORG/$REPO/collaborators/$COLLAB" -X PUT \
      -f permission="$COLLABORATOR_PERMISSION" --silent 2>/dev/null; then
      ok "$REPO → $COLLAB ($COLLABORATOR_PERMISSION)"
    else
      err "$REPO → $COLLAB failed"
    fi
  done
done

# ─── Step 2: Create develop branch ──────────────────────────────────

log "Step 2: Creating develop branch on all repos"

for REPO in "${ALL_REPOS[@]}"; do
  # Check if develop already exists
  if gh api "repos/$ORG/$REPO/git/ref/heads/develop" --silent 2>/dev/null; then
    ok "$REPO → develop already exists"
    continue
  fi

  # Get main branch SHA
  DEFAULT_SHA=$(gh api "repos/$ORG/$REPO/git/ref/heads/main" --jq '.object.sha' 2>/dev/null || echo "")
  if [[ -z "$DEFAULT_SHA" ]]; then
    err "$REPO → could not find main branch SHA, skipping"
    continue
  fi

  if gh api "repos/$ORG/$REPO/git/refs" -X POST \
    -f ref="refs/heads/develop" \
    -f sha="$DEFAULT_SHA" --silent 2>/dev/null; then
    ok "$REPO → develop created from main ($DEFAULT_SHA)"
  else
    err "$REPO → failed to create develop"
  fi
done

# ─── Step 3: Set default branch to develop ──────────────────────────

log "Step 3: Setting default branch to develop"

for REPO in "${ALL_REPOS[@]}"; do
  if gh api "repos/$ORG/$REPO" -X PATCH \
    -f default_branch=develop --silent 2>/dev/null; then
    ok "$REPO → default branch = develop"
  else
    err "$REPO → failed to set default branch"
  fi
done

# ─── Step 4: Enable delete-branch-on-merge ──────────────────────────

log "Step 4: Enabling delete-branch-on-merge"

for REPO in "${ALL_REPOS[@]}"; do
  if gh api "repos/$ORG/$REPO" -X PATCH \
    -F delete_branch_on_merge=true --silent 2>/dev/null; then
    ok "$REPO → delete-branch-on-merge enabled"
  else
    err "$REPO → failed"
  fi
done


# ─── Step 5: Branch protection for main ─────────────────────────────

log "Step 5: Configuring branch protection for main (strict)"

for REPO in "${ALL_REPOS[@]}"; do
  if gh api "repos/$ORG/$REPO/branches/main/protection" -X PUT \
    --input - --silent 2>/dev/null <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": $CI_CONTEXTS
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true
}
EOF
  then
    ok "$REPO → main protected (1 approval, enforce admins, strict status checks)"
  else
    err "$REPO → failed to protect main"
  fi
done

# ─── Step 6: Branch protection for develop ──────────────────────────

log "Step 6: Configuring branch protection for develop"

for REPO in "${ALL_REPOS[@]}"; do
  if gh api "repos/$ORG/$REPO/branches/develop/protection" -X PUT \
    --input - --silent 2>/dev/null <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": $CI_CONTEXTS
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": false
}
EOF
  then
    ok "$REPO → develop protected (1 approval, status checks, admins can bypass)"
  else
    err "$REPO → failed to protect develop"
  fi
done

# ─── Step 7: Set QA dispatch token on service repos ─────────────────

log "Step 7: Setting QA_DISPATCH_TOKEN secret on service repos"

if [[ -z "$QA_DISPATCH_TOKEN" ]]; then
  echo "  ⚠ QA_DISPATCH_TOKEN is empty — skipping."
  echo "  To set it later, run:"
  echo "    gh secret set QA_DISPATCH_TOKEN --repo \$ORG/\$REPO --body \"your-pat-here\""
else
  for REPO in "${SERVICE_REPOS[@]}"; do
    if gh secret set QA_DISPATCH_TOKEN \
      --repo "$ORG/$REPO" \
      --body "$QA_DISPATCH_TOKEN" 2>/dev/null; then
      ok "$REPO → QA_DISPATCH_TOKEN set"
    else
      err "$REPO → failed to set secret"
    fi
  done
fi

# ─── Done ────────────────────────────────────────────────────────────

log "Setup complete!"
echo ""
echo "  Next steps:"
echo "  1. Verify collaborators accepted invitations"
echo "  2. Update CI_CONTEXTS in this script once your GitHub Actions workflow job names are finalized"
echo "  3. Set QA_DISPATCH_TOKEN if you skipped it (see step 7 output)"
echo "  4. See docs/github-actions-qa-trigger.md for cross-repo QA dispatch workflow snippets"
echo ""
