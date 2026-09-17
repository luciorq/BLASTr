#' @title Get Formatted BLAST Results
#'
#' @description Retrieve BLAST results as a tibble for one or more query
#'   sequences, running serially in the current process. For parallel
#'   execution over many sequences, use [parallel_blast()] — both
#'   functions share the same engine and return the same format.
#'
#' @inheritParams run_blast
#'
#' @returns A `tibble` with one row per unique query sequence and the
#'   BLAST tabular output spread into `1_`–`<num_alignments>_` prefixed
#'   column groups.
#'
#' @examples
#' \dontrun{
#' dna_fasta_path <- fs::path_package(
#'   "BLASTr", "extdata", "minimal_db_blast",
#'   ext = "fasta"
#' )
#' temp_db_path <- fs::path_temp("minimal_db_blast")
#' make_blast_db(fasta_path = dna_fasta_path, db_path = temp_db_path)
#' query_seqs_string <- "CTAGCCATAAACTTAAATGAAGCTATACTAAACTCGTTCGCCAG
#' AGTACTACAAGCGAAAGCTTAAAACTCATAGGACTTGGCGGTGTTTCAGACCCAC"
#'
#' get_blast_results(query_seqs = query_seqs_string, db_path = temp_db_path)
#' }
#' @export
get_blast_results <- function(
  query_seqs,
  db_path,
  num_threads = 1L,
  blast_type = "blastn",
  perc_id = 80L,
  perc_qcov_hsp = 80L,
  num_alignments = 4L,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = "blastr-blast-env"
) {
  rlang::check_required(query_seqs)
  rlang::check_required(db_path)
  verbose <- rlang::arg_match(verbose)

  blast_res <- parallel_blast(
    query_seqs = query_seqs,
    db_path = db_path,
    total_cores = 1L,
    num_threads = num_threads,
    blast_type = blast_type,
    perc_id = perc_id,
    perc_qcov_hsp = perc_qcov_hsp,
    num_alignments = num_alignments,
    retry_times = 0L,
    verbose = verbose,
    env_name = env_name
  )

  # Fail loudly when nothing ran successfully (e.g. mistyped db_path):
  # an all-failed result must not be mistaken for "no hits".
  exit_codes_df <- exit_codes(blast_res)
  if (isTRUE(all(!(exit_codes_df$exit_code %in% 0L)))) {
    first_stderr <- exit_codes_df$stderr[
      !rlang::are_na(exit_codes_df$stderr)
    ][1]
    cli::cli_abort(
      message = c(
        `x` = "All {nrow(exit_codes_df)} BLAST quer{?y/ies} failed.",
        `!` = "First error: {first_stderr}"
      ),
      class = "blastr_run_blast_error"
    )
  }

  return(blast_res)
}
