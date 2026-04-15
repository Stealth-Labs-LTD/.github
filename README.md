# Stealth Labs — Shared GitHub Config

Org-wide defaults and reusable workflows for all Stealth Labs repositories.

## What's here

| Path | Purpose |
|------|---------|
| `pull_request_template.md` | Org-wide default PR template (repos inherit this automatically) |
| `.github/workflows/` | Reusable workflows called by individual repos |
| `workflow-templates/` | Starter workflows shown in the GitHub UI (Actions > New workflow) |

## Reusable workflows

These live in `.github/workflows/` and are called via `workflow_call` from each repo's own workflow files.

### security-scans.yml

Runs Semgrep SAST, TruffleHog secret scanning, and Trivy scans (dependencies, infra config, container image). Language-agnostic.

```yaml
jobs:
  security:
    uses: Stealth-Labs-LTD/.github/.github/workflows/security-scans.yml@main
    with:
      semgrep-config: p/python p/security-audit p/secrets  # or: p/typescript p/nodejs p/security-audit p/secrets
```

**Inputs:**
| Input | Default | Description |
|-------|---------|-------------|
| `semgrep-config` | `p/security-audit p/secrets` | Semgrep rule sets (space-separated) |
| `trivy-severity` | `HIGH,CRITICAL` | Trivy severity threshold |
| `infra-path` | `./infra` | Path to infrastructure config for Trivy config scan |

### lint-and-test.yml

Runs install, lint, typecheck (Node only), and test. Supports Python and Node/TypeScript with sensible defaults and optional overrides.

```yaml
jobs:
  lint-and-test:
    uses: Stealth-Labs-LTD/.github/.github/workflows/lint-and-test.yml@main
    with:
      language: python        # or: node
      language-version: "3.12" # or: "22"
```

**Inputs:**
| Input | Default | Description |
|-------|---------|-------------|
| `language` | (required) | `python` or `node` |
| `language-version` | (required) | Runtime version (e.g. `3.12`, `22`) |
| `install-command` | auto | Override: `pip install -r requirements-dev.txt` (Python) or `npm ci` (Node) |
| `lint-command` | auto | Override: `ruff check .` (Python) or `npx eslint .` (Node) |
| `typecheck-command` | auto | Override: skipped (Python) or `npx tsc --noEmit` (Node) |
| `test-command` | auto | Override: `pytest --tb=short -q` (Python) or `npm test` (Node) |

### deploy-cloud-run.yml

Builds and deploys a container to Google Cloud Run. Used for both ephemeral PR previews and persistent release demos.

```yaml
jobs:
  preview:
    uses: Stealth-Labs-LTD/.github/.github/workflows/deploy-cloud-run.yml@main
    with:
      service_name: my-service-pr-42  # omit for default (repo name)
      public: true                     # disable IAP for preview access
    secrets:
      GCP_SA_KEY: ${{ secrets.GCP_SA_KEY }}
```

**Inputs:**
| Input | Default | Description |
|-------|---------|-------------|
| `service_name` | repo name | Cloud Run service name |
| `region` | `europe-west2` | GCP region |
| `dockerfile` | `./Dockerfile` | Path to Dockerfile |
| `port` | `8080` | Container port |
| `public` | `false` | Set `true` to disable IAP (for previews) |

**Secrets:**
| Secret | Required | Description |
|--------|----------|-------------|
| `GCP_SA_KEY` | Yes | GCP service account key JSON |
| `OPENROUTER_API_KEY` | No | Passed as env var to Cloud Run if set |

### cleanup-cloud-run.yml

Deletes an ephemeral Cloud Run service and its Artifact Registry image. Used on PR close to tear down previews.

```yaml
jobs:
  cleanup:
    uses: Stealth-Labs-LTD/.github/.github/workflows/cleanup-cloud-run.yml@main
    with:
      service_name: my-service-pr-42
    secrets:
      GCP_SA_KEY: ${{ secrets.GCP_SA_KEY }}
```

**Inputs:**
| Input | Default | Description |
|-------|---------|-------------|
| `service_name` | (required) | Cloud Run service name to delete |
| `region` | `europe-west2` | GCP region |

## Workflow templates

Starter workflows available in the GitHub UI under **Actions > New workflow** for any repo in the org. These are copied into the repo (not referenced), so they serve as a starting point.

| Template | Description |
|----------|-------------|
| PR checks (Python) | Security scans + Ruff/pytest + Cloud Run preview |
| PR checks (Node/TypeScript) | Security scans + ESLint/tsc/npm test + Cloud Run preview |
| PR cleanup | Tears down ephemeral Cloud Run service on PR close |

## Typical repo setup

If you're creating a new project from `template-repo` or `template-repo-node`, the caller workflows are already included — no action needed.

For an existing repo that needs to adopt the shared workflows, either:
1. Go to **Actions > New workflow** and pick the relevant starter template
2. Or copy the examples from the reusable workflow docs above into `.github/workflows/`

The repo also needs the `GCP_SA_KEY` secret set (org-level or per-repo) for Cloud Run deploys.

## Engineering principles

All workflows enforce the standards defined in our [engineering principles](https://www.notion.so/3309b7a2846e80efb191d027b44914b3) and [DevSecOps standards](https://www.notion.so/33c9b7a2846e80279eb1ed1bba220820).
