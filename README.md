# NetObserv syncing scripts

## Initial setup

Run `./setup.sh`. It will clone all repos and set up the "upstream" and "downstream" remotes.

If you want to also have your own forks as "origin", set it up manually in each created directory (e.g. `git remote add origin git@github.com:me/flowlogs-pipeline.git`)

## Create new release branch

After a y-stream release, we generally prepare the next y-stream branch. Run with the appropriate arguments (current / next):

```bash
./new-branches.sh release-2.0 release-2.1
```

It will create the new branches based on the old ones, and update a few things for the tekton pipeline. It does NOT sync with upstream `main` (see next section).

## Sync with upstream

To synchronize downstream with upstream, run with the name of the downstream branch that will receive updates:

```bash
./sync.sh release-2.1
```

It merges upstream/main into downstream/$target. You may have conflicts during this operation, with warnings displayed such as:

```
WARNING: Merge failed in "operator", branch "release-2.0"; resolve conflicts, merge and push manually.
```

You need to resolve them manually, finish the pending merge with `git merge --continue`, then push with something like `git push downstream HEAD:release-2.1`.

### Common conflicts

- GitHub workflows, in `.github/`, have been removed from downstream. If they changed upstream, you get a conflict. Just keep deleting those files.
