# Install Required Command-line Tool Dependencies

Installs the command-line tool used by `BLASTr` - currently only
BLAST+ - into a dedicated conda environment if not already available.
(NCBI Taxonomy lookups query the NCBI E-utilities directly over HTTPS,
and
[`search_primers_on_fq()`](https://heronoh.github.io/BLASTr/reference/search_primers_on_fq.md)
runs in R, so neither needs a tool.) This ensures that all dependencies
required by the package are present with known, reproducible versions.

## Usage

``` r
install_dependencies(
  verbose = c("silent", "cmd", "output", "full"),
  force = FALSE
)
```

## Arguments

- verbose:

  A character string specifying the verbosity level during environment
  creation. Options include `"silent"`, `"cmd"`, `"output"`, or
  `"full"`. Default is `"silent"`.

- force:

  A logical value indicating whether to force the re-creation of the
  conda environments even if they already exist (the supported upgrade
  path to the currently pinned versions). Default is `FALSE`.

## Value

Invisibly returns `TRUE` once BLAST+ is installed and validated.

## Pinned tool versions

Tools are installed with pinned versions (exact upstream releases), so
that analyses are reproducible and results can be attributed to a
specific tool version in publications:

- BLAST+: `blast==2.17.0` from the <https://prefix.dev/universe> channel
  (uniform builds for Linux, macOS and Windows); fallback
  `bioconda::blast==2.17.0`

The update policy is:

- Pins are only changed in a minor `BLASTr` release (never in a patch
  release), and every change is recorded in the changelog (NEWS) with
  the old and new tool versions.

- Existing conda environments are **never upgraded implicitly**: if an
  environment already exists, it is left untouched, whatever versions it
  contains. Run `install_dependencies(force = TRUE)` to re-create the
  environments with the currently pinned versions (this is the supported
  upgrade path after updating `BLASTr` itself).

- Advanced users can override the specifications at runtime - without
  any package change - via options, e.g.
  `options(blastr.conda.blast = "<package>==<version>")` (similarly
  `blastr.conda.blast_channels`, `blastr.conda.blast_fallback`,
  `blastr.conda.fallback_channels`, and `blastr.conda.channels`).

## Fallback packages and platform coverage

BLAST+ is installed from the `blast` package on the
<https://prefix.dev/universe> channel, which is built with a single
toolchain for Linux (x86-64 and aarch64), macOS (Intel and Apple
silicon) and Windows, so the BLAST+ family works on every platform. If
that package cannot be installed, the bioconda build of the same BLAST+
release is tried automatically (bioconda has no Windows build).

## Installation validation

After creating an environment (and once per session for existing
environments), each tool is validated by running its version probe. A
stale or corrupted environment (e.g. after an interrupted installation)
is rebuilt once automatically; if the tool still fails, a classed error
explains how to inspect the environment.

## Examples

``` r
if (FALSE) { # \dontrun{
# Install dependencies with default settings
install_dependencies()

# Install dependencies with verbose output
install_dependencies(verbose = "output")

# Upgrade to the currently pinned tool versions
install_dependencies(force = TRUE)
} # }
```
