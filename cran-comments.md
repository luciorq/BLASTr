# cran-comments

## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

- Local: Linux (x86_64), R 4.5.3
- GitHub Actions: ubuntu-latest (R devel, release, oldrel-1),
  macos-latest (R release)

## Notes for CRAN reviewers

- All tests and examples that require external command-line tools
  (BLAST+, installed on demand into a conda
  environments via the `condathis` package) or network access are
  skipped on CRAN (`skip_on_cran()` / `\dontrun{}`).
- No software is downloaded or installed without an explicit user
  action (`install_dependencies()` or a function call that documents
  this behavior).
- The package writes only to the R user cache/data directories
  (`tools::R_user_dir()`) and temporary directories.
