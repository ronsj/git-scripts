# git-scripts

Some useful scripts for `git` or `gh` CLI.

## Scripts

### [gh-init](/scripts/gh-init.sh)

First-time publish of a local git repo to GitHub as a public (or private) remote.

Exits with an error if origin already exists or the GitHub repo name is taken.

### Usage
```bash
~/your/path/to/gh-init.sh [options]
```

### Options
```
  --name NAME           GitHub repo name (default: directory name)
  --description TEXT    Repo description (default: empty)
  --private             Create private repo instead of public
  --dry-run             Print planned commands without executing
  -h, --help            Show this help
```

