# Security baseline

[`.github/workflows/security-baseline.yml`](../.github/workflows/security-baseline.yml) is the security check every pull request has to pass. This page covers what it checks, what you'll see, and how it behaves.

## The short version

- It runs **automatically on every pull request** in both orgs. Nobody adds it to a repo, and nobody can switch it off or bypass it, admins included.
- It asks one question: **did this pull request make anything worse?**
  - If the pull request **adds** a problem, the check goes **red and the pull request can't merge**.
  - Problems **already on the base branch** don't block. They show as **warnings**.
- It takes about a minute, and it works on any stack with no set-up.

## Where and when it runs

The org rulesets named `security-baseline` require it on pull requests to the default branch. Stealth-Labs-HQ's rulesets run it through a thin caller in that org's own `.github` repo.

| Repos (by `tier` property) | Behaviour |
|---|---|
| Stealth-Labs-LTD: `customer`, `internal`, `open-source` | **Blocking.** A red check stops the merge. |
| Stealth-Labs-HQ: `business-critical`, `back-office` | **Blocking.** |
| `experimental`, in both orgs | **Report only.** It runs and reports but never blocks, so direct pushes still work. |

It runs when a pull request is **opened, reopened or gets a new commit**. GitHub doesn't run it on pull requests that were already open when the rule was added. Those show **"Security baseline: Expected — Waiting for workflow to run"** until they're updated (see "If something looks wrong").

**Nobody can bypass it.** The rulesets have no bypass list, so org admins can't use "merge without waiting for requirements" either. In an emergency, for example if the baseline itself breaks, an org admin can switch the ruleset to Evaluate. That's a deliberate, logged change to org settings, not a per-pull-request override.

## How it decides

Every job scans **the pull request's code** and **the base branch**, then compares the two:

- **Found in the pull request, not on the base:** the pull request added it, so the job **fails**.
- **Found in both:** it was already there, so the job **passes** and lists it as a warning.

It compares with the base branch's *current* tip, so a pull request that has fallen behind isn't blamed for changes merged since it branched.

## The five checks

| Check | Tool | Looks at | Fails when the pull request adds | Warns about (already on the base) |
|---|---|---|---|---|
| `secrets` | TruffleHog | The pull request's commits | A live secret, or one it can't confirm is dead | Not covered (see "What it doesn't do") |
| `code` | Semgrep, default rules (`p/default`), high severity | All code except workflow files | A high-severity finding, such as injection, unsafe deserialisation or shell command execution | High-severity findings |
| `dependencies` | OSV-Scanner | Every lockfile, on the base and the pull request | A dependency version with a known vulnerability | Vulnerabilities with CVSS 7 or more |
| `workflows` | zizmor | Workflow and action files the pull request adds or changes | A high-severity GitHub Actions issue, such as script injection, a dangerous trigger, or an action not pinned to a commit | High-severity issues in every workflow and action file |
| `infrastructure` | Trivy (config) | Terraform, Dockerfiles, Kubernetes, Helm, CloudFormation, ARM (not Bicep) | A high or critical misconfiguration | High and critical misconfigurations |

A repo with no lockfiles, workflow changes or infrastructure files simply passes the checks that don't apply.

The warnings come from extra report steps, including a job called `dependencies already on the base (report only)`. These steps can't fail the run.

## What you'll see on a pull request

- **Usually:** green ticks under "Security baseline", and nothing to do.
- **A red check:** open it. The log names the file, line and rule. Fix it and push, and the check runs again by itself.
- **Warnings:** open the run's summary. Each check lists the issues already on the base branch, with a ⚠️ warning on the check. Fix them in their own pull request when you can; Dependabot alerts track the dependency ones.

Results are in the job logs, annotations and run summary. Private repos can't show them in the Security tab without GitHub Code Security.

## False positives: suppressing a finding

Suppressions live in the repo's own files, so they're reviewed like any change. Always name the rule, and say why in a comment.

| Tool | How to suppress one finding |
|---|---|
| Semgrep | `# nosemgrep: <rule-id>` on the line |
| Trivy | An entry in `.trivyignore`, or an inline `#trivy:ignore:<ID>:exp:YYYY-MM-DD` comment |
| OSV-Scanner | An `[[IgnoredVulns]]` entry in `osv-scanner.toml`, with `reason` and `ignoreUntil` |
| TruffleHog | `trufflehog:ignore` on the line (and rotate the key anyway) |
| zizmor | `# zizmor: ignore[<rule>]` on the line |

**Trivy expiry gotcha.** In an inline comment, `exp:` needs a **colon** before it: `#trivy:ignore:AVD-AZU-0012:exp:2027-01-31`. Written with a space (`AVD-AZU-0012 exp:2027-01-31`), Trivy silently ignores the date and the suppression never expires. In `.trivyignore` files the space form is correct.

## If something looks wrong

| You see | Why | What to do |
|---|---|---|
| "Expected — Waiting for workflow to run" | The pull request was opened before the rule existed, so the check has never run on it | Click **Update branch**, or push a commit. On Dependabot pull requests, comment `@dependabot rebase` |
| A check fails on something you didn't touch | It thinks your pull request added it, for example a moved file or a changed lockfile | Check the log. If it's wrong, ask in #engineering-process |
| `workflows` fails with `unpinned-uses` | A workflow references an action by tag or branch instead of a commit | Pin the action to a commit, with its version in a comment |

## What it doesn't do

- **Container images aren't scanned.** It can't build images without knowing how each repo builds them. Image scanning belongs to the release scan (`security-scans.yml`).
- **Secrets already in a repo's history aren't found.** It checks only the pull request's commits. Finding old secrets needs a full-history scan.
- **Existing problems never block.** They're shown as warnings. Releases are where everything known gets blocked.

## For maintainers: changing it

- **Changes go live as soon as they merge into `main`.** The rulesets run this file from `main`, not from a pinned commit. So a merged change applies to every repo's next pull request, and it never strands pull requests that are already open.
  - Pinning the rulesets to a commit was tried and dropped. With a pin, every pull request whose check ran on an older commit was blocked until it was updated, and rerunning didn't help.
- **Test before merging.** Call the workflow from a branch in a test repo (see below), including a pull request that should fail. A broken change blocks pull requests in every repo at once.
- **Pin everything inside it.** Every action is pinned to a commit, with its version in a comment. The Semgrep image is pinned by digest, and tools are pinned by version (zizmor, Trivy, and the scanners' own images). Tags can be moved: in March 2026, 76 of the 77 trivy-action tags were hijacked to steal CI secrets (CVE-2026-33634).
- **Keep it in step with `security-scans.yml`:** same tools, versions and rules, so a pull request that passes here isn't judged by a different rule at release.

**Trying it in a repo, or testing a change from a branch:**

```yaml
on: pull_request
permissions:
  actions: read
  contents: read
  security-events: write
jobs:
  baseline:
    uses: Stealth-Labs-LTD/.github/.github/workflows/security-baseline.yml@<branch or commit sha>
```
