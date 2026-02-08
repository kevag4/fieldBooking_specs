# Cross-Repo QA Trigger — GitHub Actions Reference

Reference snippets for implementing the cross-repo QA dispatch workflow.
Use these when building the GitHub Actions CI/CD pipelines for each service.

## Prerequisites

- A GitHub PAT (classic) with `repo` scope stored as `QA_DISPATCH_TOKEN` secret in each service repo
- The `court-booking-qa` repo must have a workflow listening for `repository_dispatch` events

---

## Service Repo Side (sender)

Add this step in your service repo workflow after successful deployment to the test environment:

```yaml
# .github/workflows/deploy.yml (in platform-service, transaction-service, etc.)

jobs:
  deploy-test:
    # ... deploy to test steps ...

  trigger-qa-regression:
    needs: deploy-test
    runs-on: ubuntu-latest
    steps:
      - name: Trigger QA functional regression suite
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.QA_DISPATCH_TOKEN }}
          repository: your-org/court-booking-qa
          event-type: run-functional-regression
          client-payload: |
            {
              "service": "${{ github.event.repository.name }}",
              "version": "${{ github.sha }}",
              "environment": "test",
              "triggered_by": "${{ github.actor }}",
              "run_url": "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
            }
```

After staging deployment, trigger the smoke + stress suites:

```yaml
  trigger-qa-staging:
    needs: deploy-staging
    runs-on: ubuntu-latest
    steps:
      - name: Trigger QA smoke + stress suite
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.QA_DISPATCH_TOKEN }}
          repository: your-org/court-booking-qa
          event-type: run-staging-validation
          client-payload: |
            {
              "service": "${{ github.event.repository.name }}",
              "version": "${{ github.sha }}",
              "environment": "staging",
              "triggered_by": "${{ github.actor }}",
              "run_url": "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
            }
```

---

## QA Repo Side (receiver)

### Functional Regression (triggered after test deployment)

```yaml
# court-booking-qa/.github/workflows/functional-regression.yml

name: Functional Regression Suite

on:
  repository_dispatch:
    types: [run-functional-regression]
  workflow_dispatch:
    inputs:
      service:
        description: "Service name"
        required: true
      environment:
        description: "Target environment"
        required: true
        default: "test"

env:
  SERVICE: ${{ github.event.client_payload.service || inputs.service }}
  VERSION: ${{ github.event.client_payload.version || 'manual' }}
  ENVIRONMENT: ${{ github.event.client_payload.environment || inputs.environment }}

jobs:
  regression:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Run functional regression
        run: |
          pytest tests/functional/ \
            --env=${{ env.ENVIRONMENT }} \
            --service=${{ env.SERVICE }} \
            -v --tb=short \
            --junitxml=reports/functional-results.xml

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: functional-regression-results
          path: reports/

      # Optional: post results back to the triggering repo
      - name: Report results back
        if: always()
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.QA_DISPATCH_TOKEN }}
          repository: your-org/${{ env.SERVICE }}
          event-type: qa-results
          client-payload: |
            {
              "suite": "functional-regression",
              "status": "${{ job.status }}",
              "environment": "${{ env.ENVIRONMENT }}",
              "version": "${{ env.VERSION }}"
            }
```

### Staging Validation (smoke + stress)

```yaml
# court-booking-qa/.github/workflows/staging-validation.yml

name: Staging Validation (Smoke + Stress)

on:
  repository_dispatch:
    types: [run-staging-validation]
  workflow_dispatch:
    inputs:
      service:
        description: "Service name"
        required: true

env:
  SERVICE: ${{ github.event.client_payload.service || inputs.service }}
  VERSION: ${{ github.event.client_payload.version || 'manual' }}

jobs:
  smoke:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Run smoke suite
        run: |
          pytest tests/smoke/ \
            --env=staging \
            -v --tb=short \
            --junitxml=reports/smoke-results.xml

      - name: Upload smoke results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: smoke-results
          path: reports/

  stress:
    needs: smoke
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Run stress suite (Locust)
        run: |
          locust -f tests/stress/locustfile.py \
            --headless \
            --host=https://staging-api.courtbooking.gr \
            --users=100 \
            --spawn-rate=10 \
            --run-time=5m \
            --csv=reports/stress \
            --html=reports/stress-report.html

      - name: Validate performance SLAs
        run: |
          python scripts/validate_slas.py \
            --csv=reports/stress_stats.csv \
            --avg-threshold=500 \
            --peak-threshold=1000 \
            --error-rate-threshold=5

      - name: Upload stress results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: stress-results
          path: reports/
```

---

## Notes

- Replace `your-org` with your actual GitHub org/username
- The `QA_DISPATCH_TOKEN` PAT needs `repo` scope to trigger workflows in other repos
- The `peter-evans/repository-dispatch@v3` action is the standard way to trigger cross-repo workflows
- `workflow_dispatch` inputs allow manual runs for debugging
- SLA thresholds in `validate_slas.py` align with Requirement 19 (500ms avg, 1000ms peak, 5% error rate)
