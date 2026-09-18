# Package-local session state (validated environment cache).
the <- new.env(parent = emptyenv())

# Pinned conda package versions - the single source of truth for the
# command-line tool versions BLASTr installs.
#
# Update policy (see also ?install_dependencies and CONTRIBUTING.md):
# * Pins reference exact upstream releases and are bumped only in a
#   minor release (0.x.0), never in a patch release.
# * Every bump is recorded in NEWS.md with the old and new tool versions
#   and must pass the full test suite (CI builds the environments from
#   scratch, so green CI validates the pins on every platform).
# * Existing user environments are never upgraded implicitly; users
#   upgrade explicitly with `install_dependencies(force = TRUE)`.
# * The `blastr.conda.*` options override these pins at runtime without
#   a package change (e.g. for testing platform-specific candidate
#   builds).
#
# BLAST+ is installed from the `blast` package on the
# <https://prefix.dev/universe> channel: a single toolchain builds it
# uniformly for linux-64, linux-aarch64, osx-64, osx-arm64 and win-64,
# so every platform (including Windows) runs byte-identical sources of
# the same BLAST+ release. The bioconda build of the *same* version is
# the fallback, tried automatically when the universe package cannot be
# installed (no Windows build exists on bioconda).
blastr_conda_pins <- list(
  blast = "blast==2.17.0",
  blast_fallback = "bioconda::blast==2.17.0"
)

# Channels for the primary BLAST+ spec (universe first, conda-forge for
# its runtime dependencies) and for the fallback.
blastr_blast_channels <- c("https://prefix.dev/universe", "conda-forge")
blastr_default_channels <- c("conda-forge", "bioconda")

#' Conda Package Specification for a Command-Line Tool
#'
#' Central place mapping supported command-line tools to the conda packages
#'   (and channels) used to install them. Each specification may carry a
#'   `fallback` specification, tried automatically when the primary one
#'   cannot be installed (e.g. no build for the current platform).
#'
#' The defaults can be overridden per tool family through options, which
#' also unlocks the corresponding tools on any platform (useful for
#' testing platform-specific candidate packages before they become the
#' default):
#'
#' * `options(blastr.conda.blast = "<package>==<version>")`
#' * `options(blastr.conda.blast_channels = c("<url-or-name>", ...))`
#' * `options(blastr.conda.blast_fallback = "<channel>::<package>==<version>")`
#' * `options(blastr.conda.fallback_channels = c("<url-or-name>", ...))`
#' * `options(blastr.conda.channels = c("conda-forge", "bioconda"))`
#'
#' @param cmd Character string with the command-line tool name.
#'
#' @returns A list with elements `packages`, `channels`, and `fallback`
#'   (either `NULL` or a list with `packages` and `channels`).
#'
#' @keywords internal
#' @noRd
conda_pkg_spec <- function(cmd) {
  sys_arch <- get_sys_arch()
  channels <- getOption(
    "blastr.conda.channels",
    default = blastr_default_channels
  )
  blast_channels <- getOption(
    "blastr.conda.blast_channels",
    default = blastr_blast_channels
  )
  fallback_channels <- getOption(
    "blastr.conda.fallback_channels",
    default = blastr_default_channels
  )

  if (stringr::str_detect(cmd, "^(t?)blast|makeblastdb|blastdbcmd")) {
    # The universe `blast` package covers every platform, so the BLAST+
    # family is supported everywhere (including Windows).
    return(
      list(
        packages = getOption(
          "blastr.conda.blast",
          default = blastr_conda_pins$blast
        ),
        channels = blast_channels,
        fallback = list(
          packages = getOption(
            "blastr.conda.blast_fallback",
            default = blastr_conda_pins$blast_fallback
          ),
          channels = fallback_channels
        )
      )
    )
  }
  cli::cli_abort(
    message = c(
      `x` = "Unsupported command: {.val {cmd}}.",
      `i` = "Supported commands: BLAST+ tools ({.code blastn}, {.code blastp}, {.code blastx}, {.code tblastn}, {.code tblastx}, {.code makeblastdb}, {.code blastdbcmd})." # nolint: line_length_linter
    ),
    class = "blastr_check_cmd_unsupported_cmd"
  )
}

#' Is a command-line tool installable on the current platform?
#'
#' `TRUE` when a conda specification exists for `cmd` on this platform
#' (by default or via the `blastr.conda.*` options), `FALSE` when the
#' tool family raises `blastr_unsupported_os_error` on this platform.
#' Every supported tool (the BLAST+ family) is currently available on
#' all platforms. Unsupported command names still raise an error.
#'
#' @keywords internal
#' @noRd
cmd_available_on_platform <- function(cmd) {
  tryCatch(
    {
      conda_pkg_spec(cmd)
      TRUE
    },
    blastr_unsupported_os_error = function(e) FALSE
  )
}

#' Version-probe arguments used to validate an installed command
#' @keywords internal
#' @noRd
cmd_version_args <- function(cmd) {
  "-version"
}

#' Validate that a command runs inside its conda environment
#'
#' Executes the tool's version probe (verified to exit 0 for every
#' supported tool) and returns `TRUE` only on a zero exit status.
#'
#' @keywords internal
#' @noRd
validate_cmd <- function(cmd, env_name) {
  probe_res <- tryCatch(
    condathis::run_bin(
      cmd,
      cmd_version_args(cmd),
      env_name = env_name,
      verbose = "silent",
      error = "continue"
    ),
    error = function(e) {
      list(status = 127L, stderr = conditionMessage(e))
    }
  )
  isTRUE(probe_res$status == 0L)
}

#' Create a conda environment from a specification, with fallback
#'
#' Tries the primary specification first; if installation fails (e.g. no
#' build for the current platform), retries with the `fallback`
#' specification. Raises a classed error carrying both failure messages
#' when nothing can be installed.
#'
#' @keywords internal
#' @noRd
install_env_spec <- function(pkg_spec, env_name, verbose, overwrite = FALSE) {
  primary_cnd <- tryCatch(
    {
      condathis::create_env(
        packages = pkg_spec$packages,
        channels = pkg_spec$channels,
        env_name = env_name,
        verbose = verbose,
        overwrite = overwrite
      )
      NULL
    },
    error = function(e) e
  )
  if (rlang::is_null(primary_cnd)) {
    return(invisible(TRUE))
  }

  if (rlang::is_null(pkg_spec$fallback)) {
    cli::cli_abort(
      message = c(
        `x` = "Failed to install {.val {pkg_spec$packages}} into environment {.val {env_name}}.", # nolint: line_length_linter
        `i` = "Channels tried: {.val {pkg_spec$channels}}."
      ),
      parent = primary_cnd,
      class = "blastr_env_install_error"
    )
  }

  if (isFALSE(identical(verbose, "silent"))) {
    cli::cli_inform(
      c(
        `!` = "Could not install {.val {pkg_spec$packages}} from {.val {pkg_spec$channels}}.", # nolint: line_length_linter
        `i` = "Falling back to {.val {pkg_spec$fallback$packages}} from {.val {pkg_spec$fallback$channels}}." # nolint: line_length_linter
      )
    )
  }
  fallback_cnd <- tryCatch(
    {
      condathis::create_env(
        packages = pkg_spec$fallback$packages,
        channels = pkg_spec$fallback$channels,
        env_name = env_name,
        verbose = verbose,
        # A failed primary attempt may leave a partial environment.
        overwrite = TRUE
      )
      NULL
    },
    error = function(e) e
  )
  if (rlang::is_null(fallback_cnd)) {
    return(invisible(TRUE))
  }
  cli::cli_abort(
    message = c(
      `x` = "Failed to install {.val {pkg_spec$packages}} (primary) and {.val {pkg_spec$fallback$packages}} (fallback) into environment {.val {env_name}}.", # nolint: line_length_linter
      `i` = "Primary channels: {.val {pkg_spec$channels}}; fallback channels: {.val {pkg_spec$fallback$channels}}.", # nolint: line_length_linter
      `i` = "Primary error: {conditionMessage(primary_cnd)}"
    ),
    parent = fallback_cnd,
    class = "blastr_env_install_error"
  )
}

#' Determine if a Command is Available and Install if Necessary
#'
#' Checks if a specified command-line tool (e.g. 'blastn') is
#'   available in the managed conda environment.
#'   If not, it creates a conda environment and installs the required
#'   tool, falling back to alternative package sources when the primary
#'   channels have no build for the current platform.
#'   After installation (and once per session for existing
#'   environments), the tool is validated by running its version probe;
#'   a stale or corrupted environment is rebuilt once automatically.
#'
#' @param cmd Character string specifying the command-line tool to check for.
#'   Supported commands are the BLAST+ tools. Default is `"blastn"`.
#' @param env_name Name of the conda environment to create or use.
#'   Defaults to `"blastr-blast-env"`.
#' @param verbose Verbosity level during environment creation. One of
#'   `"silent"` (default), `"cmd"`, `"output"`, or `"full"`.
#' @param force Logical indicating whether to force the re-creation of the
#'   conda environment even if it exists.
#'   Default is `FALSE`.
#'
#' @returns Invisibly returns `TRUE` if the command is available
#'   or successfully installed.
#'
#' @examples
#' \dontrun{
#' # Check if 'blastn' command is available, and install it if not
#' check_cmd("blastn", env_name = "blastr-blast-env")
#'
#'
#' # Force re-creation of the conda environment and re-install 'blastn'
#' check_cmd("blastn", env_name = "blastr-blast-env", force = TRUE)
#' }
#'
#' @keywords internal
#' @noRd
check_cmd <- function(
  cmd = "blastn",
  env_name = "blastr-blast-env",
  verbose = c("silent", "cmd", "output", "full"),
  force = FALSE
) {
  verbose <- rlang::arg_match(verbose)
  pkg_spec <- conda_pkg_spec(cmd)

  cache_key <- paste(env_name, cmd, sep = "|")
  if (isFALSE(force) && isTRUE(the$validated_cmds[[cache_key]])) {
    return(invisible(TRUE))
  }

  if (isTRUE(force) || isFALSE(condathis::env_exists(env_name))) {
    install_env_spec(
      pkg_spec = pkg_spec,
      env_name = env_name,
      verbose = verbose,
      overwrite = force
    )
  }

  if (isFALSE(validate_cmd(cmd, env_name))) {
    # Stale or corrupted environment (e.g. interrupted installation,
    # moved cache directory): rebuild once and re-validate.
    if (isFALSE(identical(verbose, "silent"))) {
      cli::cli_inform(
        c(
          `!` = "Command {.code {cmd}} failed validation in environment {.val {env_name}}; rebuilding the environment." # nolint: line_length_linter
        )
      )
    }
    install_env_spec(
      pkg_spec = pkg_spec,
      env_name = env_name,
      verbose = verbose,
      overwrite = TRUE
    )
    if (isFALSE(validate_cmd(cmd, env_name))) {
      cli::cli_abort(
        message = c(
          `x` = "Command {.code {cmd}} is not functional in environment {.val {env_name}} even after rebuilding.", # nolint: line_length_linter
          `i` = "Inspect the environment with: {.code condathis::run_bin(\"{cmd}\", \"{cmd_version_args(cmd)}\", env_name = \"{env_name}\", verbose = \"full\")}" # nolint: line_length_linter
        ),
        class = "blastr_env_validation_error"
      )
    }
  }

  if (rlang::is_null(the$validated_cmds)) {
    the$validated_cmds <- list()
  }
  the$validated_cmds[[cache_key]] <- TRUE
  invisible(TRUE)
}
