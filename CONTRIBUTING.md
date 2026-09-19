# Contributing to BLASTr

This outlines how to propose a change to BLASTr. For a detailed
discussion on contributing to this and other R packages, please see the
[development contributing guide](https://rstd.io/tidy-contrib) and our
[code review principles](https://code-review.tidyverse.org/).

## Fixing typos

You can fix typos, spelling mistakes, or grammatical errors in the
documentation directly using the GitHub web interface, as long as the
changes are made in the *source* file. This generally means you’ll need
to edit [roxygen2
comments](https://roxygen2.r-lib.org/articles/roxygen2.html) in an `.R`,
not a `.Rd` file. You can find the `.R` file that generates the `.Rd` by
reading the comment in the first line.

## Bigger changes

If you want to make a bigger change, it’s a good idea to first file an
issue and make sure someone from the team agrees that it’s needed. If
you’ve found a bug, please file an issue that illustrates the bug with a
minimal [reprex](https://www.tidyverse.org/help/#reprex) (this will also
help you write a unit test, if needed). See our guide on [how to create
a great issue](https://code-review.tidyverse.org/issues/) for more
advice.

### Pull request process

- Fork the package and clone onto your computer. If you haven’t done
  this before, we recommend using
  `usethis::create_from_github("heronoh/BLASTr", fork = TRUE)`.

- Install all development dependencies with
  `devtools::install_dev_deps()`, and then make sure the package passes
  R CMD check by running `devtools::check()`. If R CMD check doesn’t
  pass cleanly, it’s a good idea to ask for help before continuing.

- Create a Git branch for your pull request (PR). We recommend using
  `usethis::pr_init("brief-description-of-change")`.

- Make your changes, commit to git, and then create a PR by running
  `usethis::pr_push()`, and following the prompts in your browser. The
  title of your PR should briefly describe the change. The body of your
  PR should contain `Fixes #issue-number`.

- For user-facing changes, add a bullet to the top of `NEWS.md`
  (i.e. just below the first header). Follow the style described in
  <https://style.tidyverse.org/news.html>.

### Code style

- New code should follow the tidyverse [style
  guide](https://style.tidyverse.org). You can use the
  [styler](https://CRAN.R-project.org/package=styler) package to apply
  these styles, but please don’t restyle code that has nothing to do
  with your PR.

- We use [roxygen2](https://cran.r-project.org/package=roxygen2), with
  [Markdown
  syntax](https://cran.r-project.org/web/packages/roxygen2/vignettes/rd-formatting.html),
  for documentation.

- We use [testthat](https://cran.r-project.org/package=testthat) for
  unit tests. Contributions with test cases included are easier to
  accept.

## Code of Conduct

Please note that the BLASTr project is released with a [Contributor Code
of Conduct](https://heronoh.github.io/BLASTr/CODE_OF_CONDUCT.md) derived
from the [Contributor Covenant](https://www.contributor-covenant.org/)
v2.1. By contributing to this project you agree to abide by its terms.

## Pinned command-line tool versions

`BLASTr` installs its only command-line dependency, BLAST+, into a conda
environment with a **pinned version**. (NCBI Taxonomy is queried over
HTTPS via the E-utilities client in `R/eutils.R` - the test suite
validates it against the real Entrez Direct tools, see
`tests/testthat/test-eutils-vs-edirect.R` - and
[`search_primers_on_fq()`](https://heronoh.github.io/BLASTr/reference/search_primers_on_fq.md)
runs in R.) The pins live in a single place: `blastr_conda_pins` in
`R/check_cmd.R`.

Maintainer policy for updating a pin:

1.  Pins reference exact upstream releases (e.g. `blast==2.17.0`) and
    are bumped **only in a minor release** (`0.x.0`), never in a patch
    release.
2.  Before bumping, confirm the new version is available for every
    supported platform: BLAST+ on <https://prefix.dev/universe>
    (linux-64, linux-aarch64, osx-64, osx-arm64, win-64) **and** on
    bioconda (the fallback must pin the same release).
3.  Bump the value in `blastr_conda_pins`, then run the full test suite
    locally with fresh environments
    (`install_dependencies(force = TRUE)` first, or rely on the hermetic
    test setup, which builds environments from scratch). CI also builds
    environments from scratch, so a green run validates the pins on
    every platform in the matrix.
4.  Record the change in `NEWS.md` with the old and new tool versions,
    and mirror it in the
    [`?install_dependencies`](https://heronoh.github.io/BLASTr/reference/install_dependencies.md)
    documentation.
5.  User environments are never upgraded implicitly;
    `install_dependencies(force = TRUE)` is the documented upgrade path.

At runtime, users can override any spec without a package change via
`options(blastr.conda.blast = ...)` / `blastr.conda.blast_channels` /
`blastr.conda.channels` - useful for testing candidate builds
(e.g. platform-specific packages) before they become the pinned default.

### Fallback packages

Tool families may declare a *fallback* conda specification in
`blastr_conda_pins` / `conda_pkg_spec()` (`R/check_cmd.R`), tried
automatically when the primary spec cannot be installed on the current
platform. The BLAST+ family is installed primarily from the `blast`
package on <https://prefix.dev/universe> (one toolchain, all platforms
including Windows; owner-maintained) and falls back to the bioconda
build of the **same** release, so results never depend on which source
was installed. Fallback pins follow the same update policy as primary
pins (bump both together, only in minor releases; record in NEWS).
