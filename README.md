# active-github-org-members

A small Ruby CLI for finding active members in a GitHub organization.

An org member is counted as active when they have at least one commit attributed
to their GitHub account in an organization repository during the lookback window.
The default lookback window is 90 days.

## Authentication

This project uses GitHub App installation authentication through the bundled
Octokit wrapper in `lib/github.rb`.

Set these environment variables before running the CLI:

```bash
export GH_APP_ID="12345"
export GH_APP_INSTALLATION_ID="87654321"
export GH_APP_KEY="<GitHub App private key PEM with newlines escaped as \n>"
```

Optional knobs:

```bash
export GH_APP_ALGO="RS256"
export GH_APP_LOG_LEVEL="INFO"
export GH_APP_SLEEP="3"
export GH_APP_RETRIES="10"
export GH_APP_EXPONENTIAL_BACKOFF="false"
```

The GitHub App installation needs enough repository access to list organization
repositories and commits. To count private org members, it also needs access to
list organization members.

## Usage

Bootstrap the repository:

```bash
script/bootstrap
```

Scan an organization with the default 90 day lookback:

```bash
script/server my-org
```

Scan a 30 day lookback:

```bash
script/server my-org 30
```

Emit JSON:

```bash
script/server my-org 30 --json
```

By default the CLI scans only each repository's default branch. This keeps the
request count practical for large organizations.

To opt into the more expensive exhaustive branch scan:

```bash
script/server my-org --all-branches
```

## Output

Text output includes:

- active member count
- total visible org member count
- commit count scanned
- repositories scanned
- active member login, commit count, and repositories

JSON output includes the same fields as structured data.

## Development

Run tests:

```bash
script/test
```

Run lint:

```bash
script/lint
```
