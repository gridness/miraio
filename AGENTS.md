## Working on Issues

- When working on an issue, always first check if local main branch is up-to-date using `gh repo sync`.
- For each issue create a new separate branch.
- Name branches as: `<issue_type>/<issue_number>-<issue_title>`. e.g.: `feat/99-implement-new-parser`.
- When merging to main requires merging multiple PRs, use GitHub Stacked Pull Requsts: `gh stack`.
- When stacked PRs are required, always merge them using stack: `gh stack merge`.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues for `gridness/miraio`. See `docs/agents/issue-tracker.md`.

### Triage labels

This repo uses the default five-role triage label vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context domain-doc layout. See `docs/agents/domain.md`.
