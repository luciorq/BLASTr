#' Install Required Command-line Tool Dependencies
#'
#' Installs the command-line tools used by `BLASTr` — BLAST+, Entrez
#' Direct, and seqkit — into dedicated conda environments if they are not
#' already available. This ensures that all dependencies required by the
#' package are present with known, reproducible versions.
#'
#' @details
#' # Pinned tool versions
#'
#' Tools are installed with pinned versions (exact upstream releases),
#' so that analyses are reproducible and results can be attributed to a
#' specific tool version in publications:
#'
#' * BLAST+: `bioconda::blast==2.16`
#' * Entrez Direct: `bioconda::entrez-direct==24.0`
#' * seqkit: `bioconda::seqkit==2.10.1`
#'
#' The update policy is:
#'
#' * Pins are only changed in a minor `BLASTr` release (never in a patch
#'   release), and every change is recorded in the changelog (NEWS) with
#'   the old and new tool versions.
#' * Existing conda environments are **never upgraded implicitly**: if an
#'   environment already exists, it is left untouched, whatever versions
#'   it contains. Run `install_dependencies(force = TRUE)` to re-create
#'   the environments with the currently pinned versions (this is the
#'   supported upgrade path after updating `BLASTr` itself).
#' * Advanced users can override the specifications at runtime — without
#'   any package change — via options, e.g.
#'   `options(blastr.conda.blast = "<channel>::<package>==<version>")`
#'   (similarly `blastr.conda.blast_fallback`, `blastr.conda.entrez`,
#'   `blastr.conda.seqkit`, `blastr.conda.channels`, and
#'   `blastr.conda.fallback_channels`). Overrides also unlock the
#'   corresponding tools on platforms where the default packages are not
#'   yet available (e.g. testing dedicated Windows builds).
#'
#' # Fallback packages and platform coverage
#'
#' If the primary bioconda/conda-forge specification cannot be installed
#' (typically because no build exists for the current platform), the
#' BLAST+ family automatically falls back to the zig-toolchain builds
#' (`blast-zig`, from the <https://prefix.dev/universe> channel), which
#' cover all platforms including Windows.
#'
#' # Installation validation
#'
#' After creating an environment (and once per session for existing
#' environments), each tool is validated by running its version probe.
#' A stale or corrupted environment (e.g. after an interrupted
#' installation) is rebuilt once automatically; if the tool still fails,
#' a classed error explains how to inspect the environment.
#'
#' @param verbose A character string specifying the verbosity level
#'   during environment creation.
#'   Options include `"silent"`, `"cmd"`, `"output"`, or `"full"`.
#'   Default is `"silent"`.
#' @param force A logical value indicating whether to force the
#'   re-creation of the conda environments even if they already exist
#'   (the supported upgrade path to the currently pinned versions).
#'   Default is `FALSE`.
#'
#' @returns Invisibly returns `TRUE` after attempting to install the
#'   dependencies.
#'
#' @examples
#' \dontrun{
#' # Install dependencies with default settings
#' install_dependencies()
#'
#' # Install dependencies with verbose output
#' install_dependencies(verbose = "output")
#'
#' # Upgrade to the currently pinned tool versions
#' install_dependencies(force = TRUE)
#' }
#' @export
install_dependencies <- function(
  verbose = c("silent", "cmd", "output", "full"),
  force = FALSE
) {
  verbose <- rlang::arg_match(verbose)
  check_cmd(
    cmd = "blastn",
    env_name = "blastr-blast-env",
    verbose = verbose,
    force = force
  )
  check_cmd(
    cmd = "efetch",
    env_name = "blastr-entrez-env",
    verbose = verbose,
    force = force
  )
  check_cmd(
    cmd = "seqkit",
    env_name = "blastr-seqkit-env",
    verbose = verbose,
    force = force
  )
  invisible(TRUE)
}
