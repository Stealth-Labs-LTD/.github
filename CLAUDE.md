# Stealth Labs shared GitHub config (`.github`)

The org-wide GitHub config: reusable workflows (`.github/workflows/`, called by other repos via
`workflow_call`), starter workflows (`workflow-templates/`, shown under Actions > New workflow), the
default pull request template and the public org profile (`profile/`). `README.md` documents each
workflow and template. This repo is public.

## Rules
- **Callers use `@main`.** A change to a reusable workflow reaches every repo that calls it the moment
  it merges. Keep changes backward compatible: a new input needs a default, and inputs, secrets and
  outputs that callers use are not renamed or removed.
- **A template must still work with its workflow.** A starter template's `permissions` block has to
  cover what its reusable workflow needs, because a called workflow can't be granted more than the
  caller holds.
- **Least privilege.** Ask only for the `permissions` a job needs (`GITHUB_TOKEN` is read-only by
  default) and name the org secrets a workflow uses rather than passing everything.
- **Public repo.** Never commit secrets, tokens or anything customer-specific.
- **AI review is advisory.** Nothing here may make the AI reviewer approve, request changes or fail a
  PR on its verdict.
- `continue-on-error` is not valid on a job that `uses:` a reusable workflow; GitHub rejects it.
- Comments in workflows explain why, not what.

## Reviewing a PR
- **Blocking:** a breaking change for callers (an input, secret or output removed or renamed, or a new
  required input without a default); permissions or secrets wider than the job needs; a secret or
  customer detail in this public repo; a template whose `permissions` no longer cover its workflow.
- **Check the docs move with the change:** a new or changed workflow or template is documented in
  `README.md` in the same PR.
