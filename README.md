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

**Note:** If pytest finds no tests (exit code 5), the job warns but still passes. This allows new projects to pass CI before tests are written.

### deploy-cloud-run.yml

Builds and deploys a container to Google Cloud Run. Used for both ephemeral PR previews and persistent release demos.

```yaml
jobs:
  preview:
    needs: [lint-and-test]
    uses: Stealth-Labs-LTD/.github/.github/workflows/deploy-cloud-run.yml@main
    with:
      service_name: my-service-pr-42  # omit for default (repo name)
    secrets:
      GCP_SA_KEY: ${{ secrets.GCP_SA_KEY }}
      OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}
      # Exposes the caller's repo secrets so APP_-prefixed ones get auto-injected
      # as Cloud Run env vars. See "App env vars" below.
      all_secrets: ${{ toJSON(secrets) }}
```

**Note:** `continue-on-error: true` is **not** a valid key on jobs that use `uses: <reusable-workflow>` — GitHub rejects the workflow with a parse error. If preview deploys fail, let them fail the PR — that's the signal you want. The deploy URL appears in the GitHub Actions job summary.

**Inputs:**
| Input | Default | Description |
|-------|---------|-------------|
| `service_name` | repo name | Cloud Run service name |
| `region` | `europe-west2` | GCP region |
| `dockerfile` | `./Dockerfile` | Path to Dockerfile |
| `port` | `8080` | Container port |
| `public` | `false` | Set `true` to disable IAP (customer-facing apps). Default is IAP-protected — only `@stealthlabs.uk` Google accounts can access. |
| `app_secret_prefix` | `APP_` | Repo secrets starting with this prefix are auto-injected as env vars (prefix stripped). |
| `runtime_service_account` | (unset) | Cloud Run runtime SA email. Set when the app authenticates to GCP APIs at runtime. See "Runtime service account" below. |

**Secrets:**
| Secret | Required | Description |
|--------|----------|-------------|
| `GCP_SA_KEY` | Yes | GCP service account key JSON (inherited from org secrets). |
| `OPENROUTER_API_KEY` | No | OpenRouter key (inherited from org secrets). Injected as an env var. |
| `all_secrets` | No | Pass `${{ toJSON(secrets) }}` from the caller to auto-inject `APP_*` repo secrets. |

#### App env vars (no shared-workflow edits needed per service)

Each service has its own env var needs (access codes, feature flags, DB URLs, etc.). Rather than adding every one of them to the shared workflow, store them as **repo-level secrets prefixed with `APP_`**. The shared workflow scans the `all_secrets` bag for matching keys, strips the `APP_` prefix, and injects them:

| Repo secret | Lands on Cloud Run as |
|---|---|
| `APP_ACCESS_CODES` | `ACCESS_CODES` |
| `APP_ACCESS_SECRET` | `ACCESS_SECRET` |
| `APP_UPSTASH_REDIS_REST_URL` | `UPSTASH_REDIS_REST_URL` |
| `APP_ANYTHING` | `ANYTHING` |

This way:
- New env vars require only a `gh secret set APP_X` — no workflow edits
- Org secrets (`OPENROUTER_API_KEY`, `GCP_SA_KEY`) stay explicit and named
- `toJSON(secrets)` exposes *every* secret the caller has access to, but only `APP_*` ones are used — so stray org secrets (PAT tokens, etc.) are never silently leaked onto a deployed service

#### Runtime service account (for apps that need GCP-native auth)

`APP_*` secrets cover external services with API keys (OpenRouter, third-party SaaS). They **don't** cover GCP-native services that authenticate via IAM (Cloud Run API, BigQuery, Cloud Storage, Pub/Sub, Cloud SQL via IAM, etc.). Those need an *identity*, not a secret.

By default, `deploy-cloud-run.yml` doesn't pass `--service-account=` to `gcloud run deploy`, so the deployed service inherits the **default Compute SA** (`<project-number>-compute@developer.gserviceaccount.com`), which has no project-level roles in `stealthlabs-dev`. POC apps that only call external HTTP APIs are fine with this — they don't authenticate to GCP at all.

Apps that *do* need GCP-native auth set `runtime_service_account` to a dedicated SA:

```yaml
jobs:
  deploy:
    uses: Stealth-Labs-LTD/.github/.github/workflows/deploy-cloud-run.yml@main
    with:
      runtime_service_account: myapp-runtime@stealthlabs-dev.iam.gserviceaccount.com
    secrets: { ... }
```

One-off setup (per app, per environment) before the input works:

```bash
# Create the SA
gcloud iam service-accounts create myapp-runtime \
  --display-name="myapp runtime" \
  --project=stealthlabs-dev

# Grant only the roles the app actually needs (principle of least privilege)
gcloud projects add-iam-policy-binding stealthlabs-dev \
  --member="serviceAccount:myapp-runtime@stealthlabs-dev.iam.gserviceaccount.com" \
  --role="roles/run.developer"   # or whichever role(s) the app needs
```

The `github-deployer@…` SA already has `roles/iam.serviceAccountUser` at project level, so no additional per-SA binding is needed for the deploy workflow to attach the runtime SA.

For PR previews on the same app, use a separate runtime SA scoped to the preview environment (e.g. `myapp-preview@…`) so previews can be granted different (typically smaller) roles than prod.

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

### release.yml

Builds a container image, scans with Trivy, pushes to GHCR with semver + SHA tags, signs with Cosign, generates an SBOM with Syft, and attaches it to the image. Language-agnostic — uses whatever Dockerfile is in the repo.

```yaml
jobs:
  release:
    uses: Stealth-Labs-LTD/.github/.github/workflows/release.yml@main
  deploy:
    needs: [release]
    uses: Stealth-Labs-LTD/.github/.github/workflows/deploy-cloud-run.yml@main
    secrets:
      GCP_SA_KEY: ${{ secrets.GCP_SA_KEY }}
      OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}
      all_secrets: ${{ toJSON(secrets) }}
```

**Inputs:**
| Input | Default | Description |
|-------|---------|-------------|
| `trivy-severity` | `HIGH,CRITICAL` | Trivy severity threshold |
| `dockerfile` | `./Dockerfile` | Path to Dockerfile |

The caller must set `permissions: { contents: read, packages: write, id-token: write }` for GHCR push and Cosign signing.

## Workflow templates

Starter workflows available in the GitHub UI under **Actions > New workflow** for any repo in the org. These are copied into the repo (not referenced), so they serve as a starting point.

| Template | Description |
|----------|-------------|
| PR checks (Python) | Security scans + Ruff/pytest + Cloud Run preview |
| PR checks (Node/TypeScript) | Security scans + ESLint/tsc/npm test + Cloud Run preview |
| PR cleanup | Tears down ephemeral Cloud Run service on PR close |
| Release | Build, scan, sign, push to GHCR, then deploy to Cloud Run |

## Starting a new project

Use one of the template repos — they come with caller workflows, local tooling, Dockerfile, Makefile, CLAUDE.md, and editor config pre-configured.

| Template | Language | Includes |
|----------|----------|----------|
| [`template-repo-python`](https://github.com/Stealth-Labs-LTD/template-repo-python) | Python | Ruff, pytest, pre-commit hooks, Python Alpine Dockerfile |
| `template-repo-node` (coming soon) | Node/TypeScript | ESLint, Vitest, Husky + lint-staged, Node Alpine Dockerfile |

Create a new repo from the template, replace the placeholders in CLAUDE.md, run `make setup`, and start coding. The caller workflows and security scans work out of the box.

## Adopting shared workflows in an existing repo

For repos not created from a template:
1. Go to **Actions > New workflow** and pick the relevant starter template (Python or Node)
2. Or copy the examples from the reusable workflow docs above into `.github/workflows/`
3. Add a `pr-cleanup.yml` if using PR preview deploys

The repo needs access to the `GCP_SA_KEY` and `OPENROUTER_API_KEY` secrets for Cloud Run deploys — both are set at org level so all repos inherit them automatically. Add any service-specific env vars as **repo-level secrets prefixed with `APP_`** (e.g. `APP_ACCESS_SECRET`) and they'll flow into Cloud Run automatically via the `all_secrets` passthrough.

**Dockerfile note:** Cloud Run defaults to port 8080 via the `PORT` env var. Make sure your Dockerfile exposes 8080 (or reads `PORT` from the environment) and your app listens on it.
