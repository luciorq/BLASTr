#' @title Run Parallelized BLAST
#'
#' @description Run parallel BLAST for a set of sequences.
#'
#' Unique query sequences are batched into multi-record FASTA chunks so
#' that each BLAST+ process handles many queries at once (amortizing
#' process startup and database loading), and chunks are dispatched to
#' [mirai::daemons()] with [mirai::mirai_map()]. When the `mori` package
#' is installed, the query set is placed in shared memory
#' ([mori::share()]) so parallel workers receive a zero-copy reference
#' instead of a full copy of the sequences.
#'
#' If a chunk fails (non-zero BLAST exit status), its member sequences
#' are automatically re-run individually to rescue healthy queries and
#' attribute the error to the offending ones, which are then retried up
#' to `retry_times` times. Per-query BLAST warnings (e.g. empty or
#' malformed records inside an otherwise successful batch) are captured
#' and exposed through [exit_codes()].
#'
#' @param query_seqs Character vector with sequences to be searched.
#' @param db_path Path to the formatted BLAST database.
#' @param total_cores Number of parallel BLAST processes to run. If
#'   [mirai::daemons()] are already set for the session, the existing
#'   pool is used as-is and this argument only influences chunking.
#' @param num_threads Number of threads/cores to run each BLAST process
#'   on. Passed on to BLAST+ `-num_threads`. Note that the effective
#'   maximum CPU usage is `total_cores * num_threads`.
#' @param blast_type BLAST+ executable to be used on search. One of:
#'   `c("blastn", "blastp", "blastx", "tblastn", "tblastx")`.
#' @param perc_id Lowest identity percentage cutoff.
#'   Passed on to BLAST+ `-perc_identity`.
#' @param perc_qcov_hsp Lowest query coverage per HSP percentage cutoff.
#'   Passed on to BLAST+ `-qcov_hsp_perc`.
#' @param num_alignments Number of alignments to retrieve for each query
#'   sequence. Passed on to BLAST+ `-num_alignments`. Defaults to `4`.
#' @param retry_times Number of times to retry failed BLAST jobs.
#'   Defaults to `3` attempts.
#' @param mt_mode Multithreading mode to be used by BLAST+.
#'  One of: `c("2", "1", "0")`. See BLAST+ manual for details.
#' @param chunk_size Number of query sequences per BLAST+ invocation.
#'   Defaults to `NULL`, which targets about four chunks per core
#'   (capped at 500 sequences per chunk).
#' @param verbose Verbosity level. One of `"progress"` (default),
#'   `"silent"`, `"cmd"`, `"output"`, or `"full"`. `"progress"` shows a
#'   progress bar in interactive sessions and is otherwise equivalent to
#'   `"silent"`; the remaining levels are passed on to the underlying
#'   command execution.
#' @param env_name Name of the conda environment used to run the
#'   command-line tools. Defaults to `"blastr-blast-env"`.
#'
#' @param asvs Deprecated. Same as `query_seqs`. Use `query_seqs` instead.
#' @param out_file Deprecated. Path to output `.csv` file on an existing
#' directory.
#' @param out_RDS Deprecated. Path to output `RDS` file on an existing
#' directory.
#'
#' @inheritParams rlang::args_dots_empty
#'
#' @returns A tibble with one row per unique query sequence and the BLAST
#'   tabular output spread into `1_`–`<num_alignments>_` prefixed column
#'   groups. Per-query exit codes and error messages are stored in the
#'   `BLASTr_metadata` attribute (see [exit_codes()]).
#'
#' @examples
#' \dontrun{
#' dna_fasta_path <- fs::path_package(
#'   "BLASTr", "extdata", "minimal_db_blast",
#'   ext = "fasta"
#' )
#' temp_db_path <- fs::path_temp("minimal_db_blast")
#' make_blast_db(fasta_path = dna_fasta_path, db_path = temp_db_path)
#' query_seqs_string <- c(
#'   "CTAGCCATAAACTTAAATGAAGCTATACTAA",
#'   "ACTCGTTCGCCAGAGTACTACAAGCGAAAG"
#' )
#' blast_res <- parallel_blast(
#'   query_seqs = query_seqs_string,
#'   db_path = temp_db_path
#' )
#' blast_res
#' }
#'
#' @importFrom lifecycle deprecated
#'
#' @export
parallel_blast <- function(
  query_seqs,
  db_path,
  ...,
  total_cores = 1L,
  num_threads = 1L,
  blast_type = "blastn",
  perc_id = 80L,
  perc_qcov_hsp = 80L,
  num_alignments = 4L,
  retry_times = 3L,
  mt_mode = c("2", "1", "0"),
  chunk_size = NULL,
  verbose = c("progress", "silent", "cmd", "output", "full"),
  env_name = "blastr-blast-env",
  asvs = deprecated(), # nolint: object_name_linter
  out_file = deprecated(), # nolint: object_name_linter
  out_RDS = deprecated() # nolint: object_name_linter
) {
  rlang::check_dots_empty()

  if (lifecycle::is_present(asvs)) {
    lifecycle::deprecate_warn(
      "0.1.7",
      "parallel_blast(asvs)",
      "parallel_blast(query_seqs)"
    )
    if (rlang::is_missing(query_seqs)) {
      query_seqs <- asvs
    } else {
      cli::cli_warn(
        "Both {.arg asvs} and {.arg query_seqs} were provided. Using {.arg query_seqs}." # nolint: line_length_linter
      )
    }
  }
  if (lifecycle::is_present(out_file)) {
    lifecycle::deprecate_soft(
      "0.1.7",
      "parallel_blast(out_file)"
    )
  }
  if (lifecycle::is_present(out_RDS)) {
    lifecycle::deprecate_soft(
      "0.1.7",
      "parallel_blast(out_RDS)"
    )
  }

  rlang::check_required(query_seqs)
  rlang::check_required(db_path)
  mt_mode <- rlang::arg_match(mt_mode)
  verbose <- rlang::arg_match(verbose)
  blast_type <- rlang::arg_match(
    blast_type,
    values = c("blastn", "blastp", "blastx", "tblastn", "tblastx")
  )

  if (
    rlang::is_interactive() &&
      isTRUE(verbose %in% c("progress", "full", "output"))
  ) {
    progress_var <- TRUE
  } else {
    progress_var <- FALSE
  }
  if (identical(verbose, "progress")) {
    verbose <- "silent"
  }

  # Check for query_seqs
  if (
    rlang::is_null(query_seqs) ||
      isTRUE(length(query_seqs) == 0L) ||
      isTRUE(all(rlang::are_na(query_seqs)))
  ) {
    cli::cli_abort(
      c(
        `x` = "No query sequences were provided to {.fun parallel_blast}."
      ),
      class = "blastr_no_query_seqs_error"
    )
  }

  # Check for db_path
  if (
    rlang::is_null(db_path) ||
      isTRUE(length(db_path) == 0L) ||
      rlang::is_na(db_path)
  ) {
    cli::cli_abort(
      c(
        `x` = "{.pkg BLASTr}: No database path was provided to {.fun parallel_blast}." # nolint: line_length_linter
      ),
      class = "blastr_no_db_path_error"
    )
  }

  check_cmd(blast_type, env_name = env_name, verbose = verbose)

  # Normalize queries: strip whitespace, drop empty/NA entries, deduplicate.
  seqs_clean <- stringr::str_replace_all(query_seqs, "\\s", "")
  invalid_lgl <- rlang::are_na(seqs_clean) | !nzchar(seqs_clean)
  if (isTRUE(any(invalid_lgl))) {
    cli::cli_warn(
      "Dropping {sum(invalid_lgl)} empty or NA quer{?y/ies} from {.arg query_seqs}." # nolint: line_length_linter
    )
    seqs_clean <- seqs_clean[!invalid_lgl]
  }
  seqs_to_run <- unique(seqs_clean)
  if (isTRUE(length(seqs_to_run) == 0L)) {
    cli::cli_abort(
      c(
        `x` = "No query sequences were provided to {.fun parallel_blast}."
      ),
      class = "blastr_no_query_seqs_error"
    )
  }

  # Parallel dispatch: a pre-existing daemon pool is adopted regardless
  # of `total_cores` (which then only influences chunk sizing);
  # otherwise a pool is created when `total_cores > 1`, with guaranteed
  # teardown.
  parallel_var <- FALSE
  effective_cores <- total_cores
  if (isTRUE(length(seqs_to_run) > 1L)) {
    if (isTRUE(mirai::daemons_set())) {
      parallel_var <- TRUE
      effective_cores <- max(
        total_cores,
        mirai::status()$connections,
        1L
      )
    } else if (isTRUE(total_cores > 1L)) {
      mirai::daemons(n = total_cores)
      withr::defer(
        expr = {
          mirai::daemons(n = 0L)
        }
      )
      parallel_var <- TRUE
    }
  }

  if (
    isTRUE(verbose %in% c("output", "full")) ||
      isTRUE(progress_var)
  ) {
    cli::cli_inform(
      c(
        `i` = "Running {.fun parallel_blast} for {length(seqs_to_run)} unique query sequences.", # nolint: line_length_linter
        `*` = "Using {total_cores} total processes with {num_threads} threads each." # nolint: line_length_linter
      )
    )
  }

  engine_res <- blast_engine(
    query_seqs = seqs_to_run,
    db_path = db_path,
    total_cores = effective_cores,
    num_threads = num_threads,
    blast_type = blast_type,
    perc_id = perc_id,
    perc_qcov_hsp = perc_qcov_hsp,
    num_alignments = num_alignments,
    retry_times = retry_times,
    mt_mode = mt_mode,
    chunk_size = chunk_size,
    verbose = verbose,
    progress = progress_var,
    parallel = parallel_var,
    env_name = env_name
  )

  blast_res <- assemble_blast_wide(
    query_seqs = seqs_to_run,
    engine_res = engine_res
  )

  if (
    lifecycle::is_present(out_file) &&
      !rlang::is_null(out_file) &&
      !rlang::is_na(out_file)
  ) {
    readr::write_csv(
      x = blast_res,
      file = out_file,
      append = FALSE
    )
  }

  if (
    lifecycle::is_present(out_RDS) &&
      !rlang::is_null(out_RDS) &&
      !rlang::is_na(out_RDS)
  ) {
    readr::write_rds(
      x = blast_res,
      file = out_RDS
    )
  }

  # NOTE: set metadata attribute last, so no further dplyr operations can
  # drop it.
  attributes(blast_res)$BLASTr_metadata <- list(
    db_path = db_path,
    num_alignments = num_alignments,
    perc_id = perc_id,
    perc_qcov_hsp = perc_qcov_hsp,
    blast_type = blast_type,
    exit_codes = tibble::tibble(
      query_seq = seqs_to_run,
      exit_code = engine_res$status$exit_code,
      stderr = engine_res$status$stderr
    )
  )

  return(blast_res)
}
