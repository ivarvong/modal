# Working in this repo

## Git workflow: PR-only, never push to `main`

All changes land via pull request. Never `git push` directly to `main`,
and never `git push --force` / `--force-with-lease` to `main`, even if
explicitly authorized in conversation — say no and open a PR instead.

Concretely:

1. Branch off `main` (`git switch -c <topic>`).
2. Commit on the branch.
3. `git push -u origin <topic>`.
4. `gh pr create` and let CI run.
5. Merge via `gh pr merge` (or the GitHub UI) once green.

CI on `main` is the source of truth for the package — push-to-main
breaks the property that every commit on `main` shipped through a PR
that ran the full matrix + live contract suite.
