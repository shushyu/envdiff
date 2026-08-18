# envdiff.sh

Side-by-side diff of two helmfile environment folders, with a summary table and
git-style highlighting.

```bash
cd helmfile/environments
./envdiff.sh default dev
```

Prints a status table per file (identical / differing with +/- counts / only in
one side), then a two-column diff of each differing file with per-side line
numbers and intra-line highlighting.

| Flag | Effect |
|------|--------|
| `-s` | summary table only |
| `-f STR` | only files whose name contains `STR` |
| `-c N` | context lines (default 2) |
| `-W N` | force output width |
| `-P` | plain git colours, no background |

Needs bash 4+, GNU diff/find/awk. Colour is dropped when the output is piped —
use `less -R` if you page it.
