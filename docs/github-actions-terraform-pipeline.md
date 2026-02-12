# Terraform GitHub Actions Pipeline — Reference

Reference for implementing the Terraform CI/CD pipeline for the `court-booking-infrastructure` repository.

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              PR WORKFLOW                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  PR Opens → Plan All Envs → [Manual Gate] → Deploy Dev (PR validation)     │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                            MERGE WORKFLOW                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│  PR Merged → Plan Test → Auto-Deploy Test                                   │
│           → Plan Staging → [Manual Gate] → Deploy Staging                   │
│           → Plan Prod → [Manual Gate] → Deploy Prod                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Design Rationale

- **Plan all envs on PR**: Gives visibility into impact across environments before merge
- **Manual gate for dev on PR**: Prevents multiple PRs from overwriting each other; dev becomes a "preview" environment
- **Re-plan before each deployment**: State can drift between PR open and deployment; fresh plans ensure accuracy
- **Auto-deploy to test**: Fast feedback loop after merge
- **Manual gates for staging/prod**: Safety for production-like environments

---

## Prerequisites

### GitHub Environments

Create these environments in GitHub repo settings (`Settings → Environments`):

| Environment | Protection Rules |
|-------------|------------------|
| `dev` | Required reviewers (optional) |
| `test` | None (auto-deploy) |
| `staging` | Required reviewers |
| `production` | Required reviewers, deployment branches (main only) |

### GitHub Secrets

| Secret | Description |
|--------|-------------|
| `DO_TOKEN` | DigitalOcean API token |
| `SPACES_ACCESS_ID` | Spaces access key ID |
| `SPACES_SECRET_KEY` | Spaces secret access key |

---

## PR Workflow

Triggered when a PR is opened or updated.

```yaml
# .github/workflows/terraform-pr.yml
name: "Terraform PR — Plan & Dev Preview"

on:
  pull_request:
    branches: [main]
    paths:
      - 'environments/**'
      - 'modules/**'

env:
  TF_VERSION: "1.9.0"
  TF_VAR_do_token: ${{ secrets.DO_TOKEN }}
  TF_VAR_spaces_access_id: ${{ secrets.SPACES_ACCESS_ID }}
  TF_VAR_spaces_secret_key: ${{ secrets.SPACES_SECRET_KEY }}

jobs:
  # ─────────────────────────────────────────────────────────────────────────
  # Stage 1: Plan all environments for visibility
  # ─────────────────────────────────────────────────────────────────────────
  plan-shared:
    name: "Plan Shared (dev/test/staging)"
    runs-on: ubuntu-latest
    outputs:
      plan_exitcode: ${{ steps.plan.outputs.exitcode }}
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init
        working-directory: environments/shared

      - name: Terraform Validate
        run: terraform validate
        working-directory: environments/shared

      - name: Terraform Plan
        id: plan
        run: |
          terraform plan -no-color -detailed-exitcode -out=tfplan 2>&1 | tee plan_output.txt
          echo "exitcode=${PIPESTATUS[0]}" >> $GITHUB_OUTPUT
        working-directory: environments/shared
        continue-on-error: true

      - name: Upload Plan Artifact
        uses: actions/upload-artifact@v4
        with:
          name: tfplan-shared
          path: environments/shared/tfplan

      - name: Post Plan to PR
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const planOutput = fs.readFileSync('environments/shared/plan_output.txt', 'utf8');
            const truncated = planOutput.length > 60000 
              ? planOutput.substring(0, 60000) + '\n\n... (truncated)'
              : planOutput;
            
            const body = `### 📋 Terraform Plan — Shared Environment (dev/test/staging)
            
            <details>
            <summary>Show Plan Output</summary>
            
            \`\`\`hcl
            ${truncated}
            \`\`\`
            
            </details>
            
            *Plan exit code: ${{ steps.plan.outputs.exitcode }}* (0=no changes, 2=changes pending)`;
            
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: body
            });

  plan-production:
    name: "Plan Production"
    runs-on: ubuntu-latest
    outputs:
      plan_exitcode: ${{ steps.plan.outputs.exitcode }}
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init
        working-directory: environments/production

      - name: Terraform Validate
        run: terraform validate
        working-directory: environments/production

      - name: Terraform Plan
        id: plan
        run: |
          terraform plan -no-color -detailed-exitcode -out=tfplan 2>&1 | tee plan_output.txt
          echo "exitcode=${PIPESTATUS[0]}" >> $GITHUB_OUTPUT
        working-directory: environments/production
        continue-on-error: true

      - name: Upload Plan Artifact
        uses: actions/upload-artifact@v4
        with:
          name: tfplan-production
          path: environments/production/tfplan

      - name: Post Plan to PR
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const planOutput = fs.readFileSync('environments/production/plan_output.txt', 'utf8');
            const truncated = planOutput.length > 60000 
              ? planOutput.substring(0, 60000) + '\n\n... (truncated)'
              : planOutput;
            
            const body = `### 🚀 Terraform Plan — Production Environment
            
            <details>
            <summary>Show Plan Output</summary>
            
            \`\`\`hcl
            ${truncated}
            \`\`\`
            
            </details>
            
            *Plan exit code: ${{ steps.plan.outputs.exitcode }}* (0=no changes, 2=changes pending)`;
            
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: body
            });

  # ─────────────────────────────────────────────────────────────────────────
  # Stage 2: Manual gate + Deploy to Dev (for PR validation)
  # ─────────────────────────────────────────────────────────────────────────
  deploy-dev:
    name: "Deploy to Dev (PR Preview)"
    needs: [plan-shared, plan-production]
    runs-on: ubuntu-latest
    environment: dev  # Manual approval required
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Download Plan Artifact
        uses: actions/download-artifact@v4
        with:
          name: tfplan-shared
          path: environments/shared

      - name: Terraform Init
        run: terraform init
        working-directory: environments/shared

      - name: Terraform Apply (Dev namespace only)
        run: |
          # Apply the saved plan
          terraform apply -auto-approve tfplan
        working-directory: environments/shared

      - name: Comment Deployment Status
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '✅ **Dev environment deployed** for PR validation.\n\nTest your changes at the dev endpoints before merging.'
            });
```

---

## Merge Workflow

Triggered when a PR is merged to main.

```yaml
# .github/workflows/terraform-deploy.yml
name: "Terraform Deploy — Test → Staging → Production"

on:
  push:
    branches: [main]
    paths:
      - 'environments/**'
      - 'modules/**'

env:
  TF_VERSION: "1.9.0"
  TF_VAR_do_token: ${{ secrets.DO_TOKEN }}
  TF_VAR_spaces_access_id: ${{ secrets.SPACES_ACCESS_ID }}
  TF_VAR_spaces_secret_key: ${{ secrets.SPACES_SECRET_KEY }}

jobs:
  # ─────────────────────────────────────────────────────────────────────────
  # Stage 1: Re-plan and auto-deploy to Test
  # ─────────────────────────────────────────────────────────────────────────
  deploy-test:
    name: "Plan & Deploy Test"
    runs-on: ubuntu-latest
    environment: test  # No approval required
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init
        working-directory: environments/shared

      - name: Terraform Plan (fresh)
        run: terraform plan -no-color -out=tfplan
        working-directory: environments/shared

      - name: Terraform Apply
        run: terraform apply -auto-approve tfplan
        working-directory: environments/shared

  # ─────────────────────────────────────────────────────────────────────────
  # Stage 2: Re-plan Staging, wait for manual approval, then deploy
  # ─────────────────────────────────────────────────────────────────────────
  plan-staging:
    name: "Plan Staging"
    needs: deploy-test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init
        working-directory: environments/shared

      - name: Terraform Plan
        run: terraform plan -no-color -out=tfplan
        working-directory: environments/shared

      - name: Upload Plan Artifact
        uses: actions/upload-artifact@v4
        with:
          name: tfplan-staging
          path: environments/shared/tfplan

  deploy-staging:
    name: "Deploy Staging"
    needs: plan-staging
    runs-on: ubuntu-latest
    environment: staging  # Manual approval required
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Download Plan Artifact
        uses: actions/download-artifact@v4
        with:
          name: tfplan-staging
          path: environments/shared

      - name: Terraform Init
        run: terraform init
        working-directory: environments/shared

      - name: Terraform Apply
        run: terraform apply -auto-approve tfplan
        working-directory: environments/shared

  # ─────────────────────────────────────────────────────────────────────────
  # Stage 3: Re-plan Production, wait for manual approval, then deploy
  # ─────────────────────────────────────────────────────────────────────────
  plan-production:
    name: "Plan Production"
    needs: deploy-staging
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init
        working-directory: environments/production

      - name: Terraform Plan
        run: terraform plan -no-color -out=tfplan
        working-directory: environments/production

      - name: Upload Plan Artifact
        uses: actions/upload-artifact@v4
        with:
          name: tfplan-production
          path: environments/production/tfplan

  deploy-production:
    name: "Deploy Production"
    needs: plan-production
    runs-on: ubuntu-latest
    environment: production  # Manual approval required
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Download Plan Artifact
        uses: actions/download-artifact@v4
        with:
          name: tfplan-production
          path: environments/production

      - name: Terraform Init
        run: terraform init
        working-directory: environments/production

      - name: Terraform Apply
        run: terraform apply -auto-approve tfplan
        working-directory: environments/production
```

---

## Environment Targeting

Since dev/test/staging share the same Terraform state (`environments/shared`), use Kubernetes namespaces to isolate:

| Environment | Terraform State | K8s Namespace | Notes |
|-------------|-----------------|---------------|-------|
| dev | `environments/shared` | `dev` | PR preview deployments |
| test | `environments/shared` | `test` | Auto-deploy after merge |
| staging | `environments/shared` | `staging` | Manual gate |
| production | `environments/production` | `production` | Dedicated cluster, manual gate |

For namespace-specific deployments (application code, not infra), see `github-actions-qa-trigger.md`.

---

## Notes

- **Plan artifacts**: Saved plans ensure the exact changes reviewed are what gets applied
- **Re-planning**: Always re-plan before deployment to catch state drift
- **Concurrency**: Consider adding `concurrency` groups to prevent parallel runs:
  ```yaml
  concurrency:
    group: terraform-${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: false
  ```
- **Notifications**: Add Slack/Teams notifications on deployment success/failure
- **Rollback**: Terraform doesn't have built-in rollback; revert the PR and re-run the pipeline

