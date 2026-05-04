# AGENTS.md

Guidance for coding agents working in this repository.

## Project Overview

`active-github-org-members` is a small open source Ruby CLI that reports active
members in a GitHub organization.

For this project, an org member is considered active when a commit in an
organization repository is attributed to their GitHub account within the lookback
window. The default lookback window is `90` days.

The CLI is intentionally simple:

```bash
script/server my-org
script/server my-org 30
script/server my-org 30 --json
```

By default, the scanner only checks each repository's default branch. This is an
important scalability decision. A large organization can have thousands of repos
and hundreds of branches per repo, so branch-wide scanning must remain an
explicit opt-in:

```bash
script/server my-org --all-branches
```

## Repository Shape

This repo follows the Ruby template style used in adjacent local projects:

- `script/bootstrap` installs dependencies.
- `script/test` runs RSpec and enforces 100% coverage.
- `script/lint` runs RuboCop.
- `script/server` runs the CLI.
- `vendor/cache/` contains vendored gem tarballs and is intended to be committed.
- `vendor/gems/`, `bin/`, and `coverage/` are local generated artifacts and are ignored.

Primary code paths:

- `lib/active_github_org_members.rb`: Scanner and result model.
- `lib/cli.rb`: CLI parsing and text/JSON output.
- `lib/github.rb`: GitHub App authentication wrapper around Octokit.
- `spec/lib/*_spec.rb`: Unit coverage for scanner, CLI, and GitHub auth wrapper.

## Authentication Model

This project uses GitHub App installation authentication, not a PAT-first flow.
The auth wrapper in `lib/github.rb` should remain a lightweight wrapper around
Octokit.

Required environment variables:

```bash
export GH_APP_ID="12345"
export GH_APP_INSTALLATION_ID="87654321"
export GH_APP_KEY="<GitHub App private key PEM with newlines escaped as \n>"
```

Optional environment variables:

```bash
export GH_APP_ALGO="RS256"
export GH_APP_LOG_LEVEL="INFO"
export GH_APP_SLEEP="3"
export GH_APP_RETRIES="10"
export GH_APP_EXPONENTIAL_BACKOFF="false"
```

Do not add secrets, real private keys, real installation IDs, or internal org
names to fixtures, docs, tests, or examples. This repository is open source.

Tests should generate disposable key material at runtime rather than committing
PEM fixtures.

## Performance And Semantics

Default-branch scanning is the normal behavior and should stay that way unless
the project requirements change.

The current scalable request shape is roughly:

```text
list org members
list org repos
for each repo:
  list commits on default branch since cutoff
```

The expensive opt-in shape is:

```text
list org members
list org repos
for each repo:
  list branches
  for each branch:
    list commits since cutoff
```

Be careful before expanding the default behavior. A 5,000-repo org with hundreds
of branches per repo can turn an innocent change into hundreds of thousands of
GitHub API requests.

If improving performance, prefer this order:

1. Skip repos whose metadata shows no recent push activity.
2. Add manual pagination with early-exit checks instead of relying on blind
   auto-pagination.
3. Add bounded repo-level concurrency with conservative limits.
4. Add checkpoint/resume support for long scans.
5. Only then consider broader data sources such as commit search or audit/event
   APIs, and document any semantic differences.

Do not silently redefine "active." If a change counts pull requests, issues,
reviews, events, or default-branch-only commits differently, update the README,
CLI help, and tests to make the new definition explicit.

## Coding Guidelines

Keep the implementation small and direct. This is a CLI, not a framework.

Follow existing local patterns:

- Use plain Ruby objects.
- Keep CLI parsing in `lib/cli.rb`.
- Keep GitHub API scanning behavior in `lib/active_github_org_members.rb`.
- Keep GitHub authentication/token/rate-limit behavior in `lib/github.rb`.
- Prefer dependency-free standard library code unless a gem is already present
  and clearly useful.

Avoid dynamic dispatch helpers such as `public_send` with user-derived or
runtime-derived method names. The RuboCop GitHub config rejects this pattern.

When reading GitHub API resources, remember tests may use hashes and lightweight
structs, while real Octokit responses are Sawyer resources. Keep resource access
compatible with both where practical.

If changing output shape:

- Update `README.md`.
- Update `lib/cli.rb` help text.
- Update scanner/CLI specs.
- Preserve JSON output as stable structured data where possible.

## Testing Expectations

Run the project scripts before considering work complete:

```bash
script/test
script/lint
git diff --check
```

`script/test` currently enforces 100% SimpleCov line coverage. New code should
include focused tests rather than lowering the threshold.

Use unit tests with mocked GitHub responses for normal changes. Do not make
tests depend on live GitHub credentials or network access.

Good test coverage includes:

- CLI parsing and validation.
- Text and JSON output.
- Default lookback behavior.
- Default-branch default behavior.
- Explicit `--all-branches` behavior.
- Commit SHA deduplication.
- Author and committer attribution.
- Repository failure handling.
- GitHub App auth wrapper behavior.

## Dependency And Vendoring Notes

This repo vendors gem tarballs in `vendor/cache/`.

If dependency declarations change:

```bash
bundle lock
bundle cache
script/bootstrap
script/test
script/lint
```

Do not commit `vendor/gems/`, `bin/`, or `coverage/`.

## Open Source Hygiene

Keep examples generic:

- Use `my-org`, `octo-org`, or `example-org`.
- Do not mention private repository names as project dependencies.
- Do not document private implementation history.
- Do not include internal Slack, GitHub, Datadog, Databricks, or company-specific
  references unless the user explicitly asks and the result is safe for public
  release.

README and help text should be understandable to someone landing on the project
without access to any local context.

## Useful Commands

```bash
script/bootstrap
script/server --help
script/server my-org
script/server my-org 30 --json
script/server my-org --all-branches
script/test
script/lint
git status --short
git diff --check
```
