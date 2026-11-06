# Release and scheduled security scan: design

Status: draft for review, 6 November 2026.

## What this is and why

`security-scans.yml` becomes the org's single answer to **"is anything bad in here?"** Any release workflow calls it before it ships anything, and so does a weekly schedule. It works whatever the project deploys to.

`security-baseline.yml` stays the mandatory pull request check. Its question is different: **"did this pull request make anything worse?"**

Both use the same tools, versions and rules, so a pull request that passes is never judged by a different rule at release.

Why now:

- **Pull requests no longer catch existing issues.** On 5 November we decided that PR checks block only what a PR introduces; existing issues show as warnings. That is the right call for PRs, but it means releases are now the only place an existing problem can stop anything, so the release scan must be thorough.
- **`security-scans.yml` today falls short in four ways:**
  - **Not pinned.** Actions are referenced by tag and the Semgrep image has no version. In March 2026, 76 of the 77 trivy-action tags were hijacked to steal CI secrets (CVE-2026-33634).
  - **Skips silently.** The infrastructure scan runs only if an `infra/` folder exists, and the image scan only builds `./Dockerfile`. Both still report green.
  - **Rules differ from the baseline.** It uses Semgrep packs chosen by each repo at any severity, and Trivy for dependencies; the baseline uses Semgrep default rules at high severity, and OSV-Scanner.
  - **No settings.** At least one repo copied the whole file because it couldn't adjust one scanner.
- **Projects deploy in very different ways:**
  - quick internal proofs of concept on GCP Cloud Run, through the central deploy workflow;
  - business-critical HQ line-of-business apps on Azure, which will get a structured release workflow kept in the HQ org;
  - customer projects, often deployed straight into the customer's own environment.

  Deployment stays each project's choice. The scan has to fit all of them.

## Goals

1. **Release gate.** Fails on any high or critical issue anywhere in the repo or in what it ships, whoever introduced it. Every kind of project is held to the same bar, proofs of concept included.
2. **Weekly scan.** The same scan in report mode. It never fails anything, and it opens or updates one issue in the repo when it finds something.
3. **Fits what each repo ships**, through settings that can only add things to scan, never loosen the bar.
4. **Fails closed.** It is never green because something wasn't scanned. Each run says what it did not cover.
5. **In step with the baseline.** Same tools, versions, rules and suppression conventions, enforced by a test.
6. **Leaves evidence:** a readable summary, a machine-readable results file for the future devsecops portal, and an SBOM for each image.
7. **Existing callers keep working** without changes.

## Non-goals

- **Controlling or centralising deployments.** Projects keep their own deploy routes.
- **Forcing repos to call it.** Visibility of which repos use it comes later, from the devsecops portal and its agents (SL-1664, SL-2295).
- **Changing what the PR baseline blocks.** Only its shared versions and rules are touched.
- **Fixing findings.** Dependabot, and later the agents, do that.
- **Paid GitHub security products.**

## Anti-goals: failure even if it technically works

- Repos copy and modify it because it can't be configured.
- It reports green while something was skipped.
- Any action, image or tool is referenced by a tag, a branch or `latest`.
- Any setting lets a repo lower the bar.
- A scanner runs in a job that holds deploy credentials or secrets.
- It goes back into pull request checks, where red on existing issues becomes normal and gets ignored.

## Decisions already made

These came from the 5–6 November discussion with Ben:

- **Two files, not one with a switch.** `security-baseline.yml` for pull requests; `security-scans.yml` for releases and the weekly scan. One file would put release-only code (image builds, archives, SBOMs) inside the check every pull request in both orgs depends on.
- **Pull requests block only what they introduce. Releases block on any known high or critical issue.**
- **`security-scans.yml` comes out of pull request checks** in every repo. That clean-up is tracked separately.
- **Deployment stays per project.**

## Current state, for reference

- **`security-baseline.yml`.** Required on pull requests by org rulesets in Stealth-Labs-LTD and Stealth-Labs-HQ. HQ calls it through a thin caller in its own `.github`. Everything is pinned to a commit or digest. Tools:
  - TruffleHog on the PR's commits, verified and unknown results;
  - Semgrep `p/default` at ERROR;
  - OSV-Scanner;
  - zizmor at high;
  - Trivy config at high and critical.
- **`security-scans.yml`.** Called with `@main` from about 12 repos' pull request checks, which are being removed, and from release workflows. Its inputs are `semgrep-config`, `trivy-severity` and `infra-path`.
- **`release.yml`**, the central build, scan, sign and push to GHCR. It has its own Trivy image scan, being pinned in .github#32. **`deploy-cloud-run.yml`** is the central Cloud Run deploy.

## Design

### Modes and callers

One input, `mode`:

- `gate` (the default). Fails the run on any finding at or above the bar.
- `report`. Never fails because of findings. It writes the same results, and on a scheduled run it opens or updates an issue.

Callers:

- **Any release workflow.** It runs the scan in `gate` mode, and the jobs that build for release, push, sign or deploy depend on it (`needs:`). That covers the Cloud Run template, the future HQ Azure release workflow, and customer projects' own release routes.
- **A weekly schedule.** A small template workflow, `security-weekly.yml`, runs on a weekly cron and can be started manually, in `report` mode. It goes into the repo templates; existing repos get it later.

### What it scans

This is everything in the repo at the commit being released, not a comparison.

| Area | Tool (same pin as the baseline) | Bar | Notes |
|---|---|---|---|
| Code | Semgrep, `p/default` | ERROR | Repos can add packs (additive only). |
| Dependencies | OSV-Scanner, recursive | CVSS 7 or more, with a fixed version available | Unfixable ones are listed, not blocking (see "My calls"). |
| Secrets | TruffleHog, **full history** of the default branch | verified and unknown | Same result types as the baseline. |
| Infrastructure | Trivy config, whole repo, no folder gate | HIGH, CRITICAL | Terraform, Dockerfiles, docker-compose, Kubernetes, Helm, CloudFormation, ARM. When `.bicep` files exist, compile them to ARM first; if they can't be compiled, the run fails. |
| Workflow files | zizmor, all workflow and action files | high | |
| Container images | Trivy image | HIGH, CRITICAL, fixed version available | See "Images". |

### Images

Projects ship images from root Dockerfiles, variant Dockerfiles (`Dockerfile.<name>`), per-service folders, `deploy/` folders, cloud-side builds, and image archives handed to customers. The `images` input is a list. Each entry is one of:

- **A Dockerfile to build**, with its build context and any build arguments. It is built inside the scan job and never pushed.
- **A registry reference or digest**, for images built elsewhere: cloud-side builds, or builds that need credentials or build secrets, which the scan job must never hold.
- **An archive** (`docker save` output), passed as a workflow artifact, for images handed to customers as files.

Rules:

- **No `images` given:** the scan builds `./Dockerfile` with context `.` if it exists. That keeps today's behaviour for existing callers.
- **Every Dockerfile must be accounted for.** Any Dockerfile in the repo that isn't listed, and isn't named in the `not-shipped` setting, fails the gate. That's how "every Dockerfile must be declared" is enforced without guessing build contexts.
- **Registry images:** the scanner can read public registries only. Private images that need a login are scanned from an archive the caller provides, so the scan job never holds registry credentials.
- **One SBOM per image**, uploaded as an artifact.

### Fails closed

- **Every tool must finish and write its results.** A missing or unreadable results file fails the gate.
- **Coverage is checked, not assumed:**
  - dependency manifests found against manifests actually read;
  - Dockerfiles found against Dockerfiles declared;
  - Bicep files found against Bicep files compiled.

  Anything found but not scanned fails the gate. The exception is anything the repo has declared as a known gap.
- **Known gaps** live in a file in the repo (path left to the builder), each with a reason. Every run's summary lists them, so a green run says what it doesn't cover.
- **The Trivy vulnerability database must be fresh.** Older than a set number of days fails the gate, and only warns in report mode.
- **The scanner itself is tested.** A test workflow in `.github` runs on every change to `security-scans.yml`, and weekly. It runs each scanner against planted issues (a known-critical package, a fake live-looking secret, a misconfigured Dockerfile, an unsafe workflow) and fails if any scanner doesn't go red.

### Suppressions

It honours the same per-repo suppression files and comments as the baseline: `.trivyignore`, `nosemgrep`, `osv-scanner.toml`, `trufflehog:ignore` and zizmor ignores. The summary and results file list **every suppression in effect**, by tool and file, so nothing hides quietly.

Requiring a reason and an expiry on each suppression is out of scope here; it belongs to the planned suppression check. Trivy's inline expiry needs a colon, `#trivy:ignore:ID:exp:YYYY-MM-DD`; written with a space, Trivy ignores the date without a warning.

### Outputs

- **A job summary:** findings per area, suppressions in effect, coverage, and declared gaps.
- **One JSON results file** as an artifact, in a single stable shape across tools: area, tool, rule or advisory, severity, location, fixed version, and whether it was suppressed. This is what the future portal reads.
- **SBOMs**, one per image.
- **Weekly report mode:** opens one issue labelled `security-scan` when there are findings, updates it on later runs, and closes it when a run comes back clean. Only that step gets `issues: write`.

### Settings (inputs)

- `mode`: `gate` (default) or `report`.
- `images`: as above.
- `not-shipped`: Dockerfiles in the repo that aren't released (examples, dev tooling).
- `semgrep-extra-config`: extra Semgrep packs, added to `p/default`.
- **Old inputs, still accepted:**
  - `semgrep-config` is treated as `semgrep-extra-config`.
  - `infra-path` is ignored, because the whole repo is scanned; the summary says so.
  - `trivy-severity` can't lower the bar. A value missing HIGH or CRITICAL is ignored with a warning.

There is deliberately no setting that skips an area or lowers a threshold. Leaving something out needs a declared gap, which shows in every summary.

### Security of the scanner itself

- **Pinned like the baseline:** every action to a commit with its version in a comment, container images by digest, downloaded tools by version.
- **Least privilege.** `contents: read` throughout; `issues: write` only for the weekly issue step. No cloud credentials, no `secrets: inherit`, no registry logins.
- **It builds images but never pushes them.** Pushing, signing and deploying stay with the caller, after the gate passes, in jobs the scan doesn't share.

### Keeping the two files in step

These must be identical in `security-baseline.yml` and `security-scans.yml`:

- tool versions and digests;
- Semgrep base rules (`p/default`, ERROR);
- the OSV threshold;
- zizmor's minimum severity;
- the Trivy config severities;
- the suppression conventions.

A test in `.github` runs on every pull request to `.github` and fails if they differ. The mechanism (a parsing script, or a shared versions file both read) is left to the builder.

### Changes elsewhere

- **The repo templates:**
  - their release workflow calls the scan in `gate` mode before anything builds for release or deploys;
  - add `security-weekly.yml`;
  - remove the scan from `pr-checks`.
- **Central `release.yml`.** Its own Trivy image scan must not be weaker than this design. Either it calls `security-scans.yml` with its built image as an archive before pushing, or it keeps its own scan with the shared pins. The builder chooses.
- **HQ.** The future Azure release workflow lives in Stealth-Labs-HQ's `.github` and calls this file, pinned.
- **`deploy-cloud-run.yml`:** no change.

### Rollout

Callers use `@main` and the file keeps its name, so **merging the new version is the cutover**: every caller gets it at once, in `gate` mode. The order is:

1. **Remove `security-scans.yml` from every repo's pull request checks first.** Otherwise those pull requests go red on existing issues the day the new version merges.
2. **Build the new version on a branch** in `.github`. Test it in the test repo against fixtures for each shape:
   - a root Dockerfile, multiple Dockerfiles, a registry reference and an archive;
   - Bicep, docker-compose and Terraform;
   - a manifest that can't be read, and an undeclared Dockerfile.
3. **Dry run.** Run the branch version, by commit, in `report` mode against every current release caller. Share what each would block, with a merge date.
4. **Merge on that date.** Releases that go red afterwards are the gate working. There is no temporary mode that lowers the bar. Repos fix their findings, add a reviewed suppression, or declare a gap.
5. **Add the weekly workflow** through the templates.

## My calls, for Ben to check

- **Proofs of concept are held to the same release bar** as everything else.
- **Only vulnerabilities with a fixed version block** (dependencies and images). Ones with no fix yet are listed but don't block. Otherwise a repo can be frozen with nothing to do but add a suppression. Several repos already scan this way.
- **Infrastructure blocks on HIGH and CRITICAL**, matching the baseline. Today's scan uses MEDIUM and up, but it rarely runs because of the `infra/` folder gate.
- **Full history means the default branch. Secrets found there block only when TruffleHog verifies them as live.** Unverifiable results in history are listed, not blocking. TruffleHog's only suppression is an inline comment, which can't be added to old commits, and rotating the key is the remedy anyway. The baseline still blocks unverifiable secrets in a pull request's new commits, where the author can fix them.
- **Vulnerabilities with no CVSS score aren't skipped.** Use the advisory's own severity label instead: GHSA, or the label on an alias. If there's no label either but a fixed version exists, block. With no score, no label and no fix, list it. Go advisories often have no score, which is why this matters.
- **The weekly scan opens a GitHub issue in the repo,** until the portal exists.
- **The severity input can't lower the bar.**
- **Callers keep using `@main`**, so central fixes reach everyone at once. `.github`'s `main` needs code-owner review.

## Left to the builder

- the exact syntax of the `images` list;
- the SBOM format;
- the JSON results shape;
- the known-gaps file path and format;
- how the two files are kept in step;
- how Bicep is compiled;
- how the database age is checked;
- how many days counts as stale.
