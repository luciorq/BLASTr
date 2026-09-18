#' @title Run BLAST
#'
#' @description Run BLAST for one or more sequences and return the raw
#'   process results. For results formatted as a tibble, use
#'   [get_blast_results()] or [parallel_blast()].
#'
#' Each sequence is written as its own FASTA record (with generated
#' `BLASTrQ<i>` headers), so multiple sequences are searched as separate
#' queries in a single BLAST+ invocation.
#'
#' @param query_seqs Character vector with sequences to be searched.
#' @param db_path Path to the formatted BLAST database.
#' @param num_threads Number of threads to run BLAST on.
#'   Passed on to BLAST+ argument `-num_threads`.
#' @param perc_id Lowest identity percentage cutoff.
#'   Passed on to BLAST+ `-perc_identity`.
#' @param perc_qcov_hsp Lowest query coverage per HSP percentage cutoff.
#'   Passed on to BLAST+ `-qcov_hsp_perc`.
#' @param num_alignments Number of alignments to retrieve for each query
#'   sequence. Passed on to BLAST+ `-num_alignments`. Defaults to `4`.
#' @param blast_type BLAST+ executable to be used on search. One of:
#'   `c("blastn", "blastp", "blastx", "tblastn", "tblastx")`.
#' @param verbose Verbosity level. One of `"silent"` (default), `"cmd"`,
#'   `"output"`, or `"full"`.
#' @param env_name Name of the conda environment used to run the
#'   command-line tools. Defaults to `"blastr-blast-env"`.
#'
#' @returns Unformatted BLAST results (the raw process result, with
#'   `status`, `stdout`, and `stderr`). `stdout` is BLAST+ tabular
#'   output in format `"6 std qcovhsp staxid stitle"` - 15
#'   tab-separated fields: the 12 standard outfmt-6 columns followed by
#'   `qcovhsp`, `staxid`, and `stitle` (subject title), with query IDs
#'   in the generated `BLASTrQ<i>` form. (Before version 0.2.0, the
#'   output had 14 fields and no `stitle`.) For results formatted as a
#'   tibble, please use [get_blast_results()].
#'
#' @examples
#' \dontrun{
#'
#' dna_fasta_path <- fs::path_package(
#'   "BLASTr", "extdata", "minimal_db_blast",
#'   ext = "fasta"
#' )
#' temp_db_path <- fs::path_temp("minimal_db_blast")
#' make_blast_db(fasta_path = dna_fasta_path, db_path = temp_db_path)
#' query_seqs_string <- "CTAGCCATAAACTTAAATGAAGCTATACTAAACTCGTTCGCCAG
#' AGTACTACAAGCGAAAGCTTAAAACTCATAGGACTTGGCGGTGTTTCAGACCCAC"
#' blast_res <- run_blast(
#'   query_seqs = query_seqs_string,
#'   db_path = temp_db_path
#' )
#' }
#'
#' @export
run_blast <- function(
  query_seqs,
  db_path,
  num_alignments = 4L,
  num_threads = 1L,
  blast_type = "blastn",
  perc_id = 80L,
  perc_qcov_hsp = 80L,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = "blastr-blast-env"
) {
  rlang::check_required(query_seqs)
  rlang::check_required(db_path)
  verbose <- rlang::arg_match(verbose)
  blast_type <- rlang::arg_match(
    blast_type,
    values = c("blastn", "blastp", "blastx", "tblastn", "tblastx")
  )
  check_cmd(cmd = blast_type, env_name = env_name, verbose = verbose)

  seqs_clean <- stringr::str_replace_all(query_seqs, "\\s", "")

  worker <- make_blast_worker(
    query_seqs = seqs_clean,
    db_path = db_path,
    num_alignments = num_alignments,
    num_threads = num_threads,
    blast_type = blast_type,
    perc_id = perc_id,
    perc_qcov_hsp = perc_qcov_hsp,
    mt_mode = "0",
    verbose = verbose,
    env_name = env_name
  )
  worker_res <- worker(seq_along(seqs_clean))

  if (isTRUE(worker_res$status != 0L)) {
    error_msg_list <- stringr::str_extract_all(worker_res$stderr, "Error:.*")

    if (isTRUE(length(unlist(error_msg_list)) > 0)) {
      error_msg_vector <- unlist(error_msg_list)
      names(error_msg_vector) <- c(rep("x", times = length(error_msg_vector)))
    } else {
      error_msg_vector <- worker_res$stderr
    }

    cli::cli_abort(
      message = c(
        `!` = "Status code: {.val {worker_res$status}}",
        error_msg_vector
      ),
      class = "blastr_error_blast_run"
    )
  }

  return(worker_res)
}
