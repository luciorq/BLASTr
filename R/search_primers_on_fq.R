#' Count Primer Occurrences in FASTQ Files
#'
#' Searches (possibly degenerate) primer sequences in FASTQ files and
#' reports, for each file/primer combination, the number and percentage
#' of reads containing the primer. Matching is performed with
#' `seqkit grep` (installed automatically in a conda environment), which
#' supports IUPAC degenerate bases in the primer sequences and works on
#' plain or gzip-compressed FASTQ files on any operating system.
#'
#' By default both strands are searched (`seqkit` default); set
#' `only_positive_strand = TRUE` to restrict matching to the forward
#' strand.
#'
#' @param primer_seqs Named character vector of primer sequences (IUPAC
#'   degenerate bases allowed). Names are used as primer identifiers;
#'   unnamed primers are labeled `primer_<i>`.
#' @param fastq_paths Character vector of paths to FASTQ files
#'   (optionally gzip-compressed).
#' @param only_positive_strand Logical, search only the forward strand.
#'   Defaults to `FALSE` (both strands).
#' @param verbose Verbosity level. One of `"silent"` (default), `"cmd"`,
#'   `"output"`, or `"full"`.
#' @param env_name Name of the conda environment where `seqkit` is
#'   installed. Defaults to `"blastr-seqkit-env"`.
#'
#' @inheritParams rlang::args_dots_empty
#'
#' @returns A tibble with columns `file_name`, `primer_name`,
#'   `primer_sequence`, `total_reads`, `primer_matches`, and
#'   `percentage`.
#'
#' @examples
#' \dontrun{
#' # Toy FASTQ file with two reads, one containing the primer motif
#' fastq_path <- tempfile(fileext = ".fastq")
#' writeLines(
#'   c(
#'     "@read_1", "TTTTACAGGTTTTTTTTTTT", "+", "IIIIIIIIIIIIIIIIIIII",
#'     "@read_2", "CCCCCCCCCCCCCCCCCCCC", "+", "IIIIIIIIIIIIIIIIIIII"
#'   ),
#'   fastq_path
#' )
#' # Degenerate primer: ACWGGT matches ACAGGT and ACTGGT
#' search_primers_on_fq(
#'   primer_seqs = c(TEST = "ACWGGT"),
#'   fastq_paths = fastq_path
#' )
#' }
#'
#' @export
search_primers_on_fq <- function(
  primer_seqs,
  fastq_paths,
  ...,
  only_positive_strand = FALSE,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = "blastr-seqkit-env"
) {
  rlang::check_dots_empty()
  rlang::check_required(primer_seqs)
  rlang::check_required(fastq_paths)
  verbose <- rlang::arg_match(verbose)

  primer_seqs <- toupper(
    as.character(primer_seqs) |>
      rlang::set_names(names(primer_seqs))
  )
  if (rlang::is_null(names(primer_seqs))) {
    names(primer_seqs) <- paste0("primer_", seq_along(primer_seqs))
  }
  empty_names_lgl <- !nzchar(names(primer_seqs))
  names(primer_seqs)[empty_names_lgl] <- paste0(
    "primer_",
    seq_along(primer_seqs)
  )[empty_names_lgl]
  if (isTRUE(anyDuplicated(names(primer_seqs)) > 0L)) {
    cli::cli_warn(
      "Duplicated primer names found; renaming with {.fun make.unique} so every primer is searched." # nolint: line_length_linter
    )
    names(primer_seqs) <- make.unique(names(primer_seqs), sep = "_")
  }

  invalid_primers_lgl <- !stringr::str_detect(
    primer_seqs,
    "^[ACGTUWSMKRYBDHVN]+$"
  )
  if (isTRUE(any(invalid_primers_lgl))) {
    cli::cli_abort(
      message = c(
        `x` = "Primer{?s} {.val {names(primer_seqs)[invalid_primers_lgl]}} contain{?s/} non-IUPAC characters." # nolint: line_length_linter
      ),
      class = "blastr_invalid_primer_error"
    )
  }

  missing_files_lgl <- !fs::file_exists(fastq_paths)
  if (isTRUE(any(missing_files_lgl))) {
    cli::cli_abort(
      message = c(
        `x` = "FASTQ file{?s} not found: {.file {fastq_paths[missing_files_lgl]}}." # nolint: line_length_linter
      ),
      class = "blastr_fastq_file_not_readable"
    )
  }

  check_cmd("seqkit", env_name = env_name, verbose = verbose)

  count_reads <- function(path) {
    stats_res <- condathis::run_bin(
      "seqkit",
      "stats",
      "-T",
      path,
      env_name = env_name,
      verbose = verbose,
      error = "continue"
    )
    if (isTRUE(stats_res$status != 0L)) {
      cli::cli_abort(
        message = c(
          `x` = "seqkit failed to read {.file {path}}.",
          `!` = stats_res$stderr
        ),
        class = "blastr_seqkit_error"
      )
    }
    stats_tbl <- readr::read_tsv(
      I(stats_res$stdout),
      show_col_types = FALSE
    )
    n_seqs <- suppressWarnings(as.numeric(stats_tbl$num_seqs[1]))
    if (isTRUE(length(n_seqs) == 0L) || isTRUE(is.na(n_seqs))) {
      n_seqs <- 0
    }
    n_seqs
  }

  results_list <- list()
  for (fastq_path in fastq_paths) {
    total_reads <- count_reads(fastq_path)

    # Iterate positionally: indexing by name would always fetch the
    # first element for duplicated names.
    for (primer_i in seq_along(primer_seqs)) {
      primer_name <- names(primer_seqs)[primer_i]
      primer_seq <- primer_seqs[[primer_i]]
      # `--count` prints the number of matching records directly: no
      # temporary file and no second seqkit process needed.
      grep_args <- c(
        "grep",
        "--by-seq",
        "--degenerate",
        "--ignore-case",
        "--count",
        "--pattern",
        primer_seq,
        fastq_path
      )
      if (isTRUE(only_positive_strand)) {
        grep_args <- append(grep_args, "--only-positive-strand", after = 1L)
      }
      grep_res <- condathis::run_bin(
        "seqkit",
        grep_args,
        env_name = env_name,
        verbose = verbose,
        error = "continue"
      )
      primer_matches <- suppressWarnings(
        as.numeric(stringr::str_trim(grep_res$stdout))
      )
      if (
        isTRUE(grep_res$status != 0L) ||
          isTRUE(length(primer_matches) == 0L) ||
          isTRUE(is.na(primer_matches))
      ) {
        cli::cli_abort(
          message = c(
            `x` = "seqkit grep failed for primer {.val {primer_name}} on {.file {fastq_path}}.", # nolint: line_length_linter
            `!` = grep_res$stderr
          ),
          class = "blastr_seqkit_error"
        )
      }

      percentage <- 0
      if (isTRUE(total_reads > 0)) {
        percentage <- (primer_matches / total_reads) * 100
      }

      results_list <- c(
        results_list,
        list(
          tibble::tibble(
            file_name = fastq_path,
            primer_name = primer_name,
            primer_sequence = primer_seq,
            total_reads = total_reads,
            primer_matches = primer_matches,
            percentage = percentage
          )
        )
      )
    }
  }

  return(purrr::list_rbind(results_list))
}
