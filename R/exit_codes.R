#' Retrieve Exit Codes and Standard Error from BLASTr Results
#'
#' @description
#' This function extracts the per-query exit codes and standard error
#' messages from the results of a BLAST search performed with
#' [parallel_blast()] or [get_blast_results()] (stored in the
#' `BLASTr_metadata` attribute of the returned tibble).
#'
#' @param blast_res A tibble returned by [parallel_blast()] or
#'   [get_blast_results()].
#'
#' @returns A tibble with columns `query_seq`, `exit_code`, and
#'   `stderr`. `exit_code` is `0` for successful queries, the BLAST+
#'   exit status for tool failures, or `-1` when the R-level parallel
#'   worker itself failed (e.g. a crashed daemon). `stderr` holds the
#'   full standard error output of the BLAST+ invocation that produced
#'   the query's result — including non-fatal per-query warnings such
#'   as `"Sequence contains no data"` — or `NA` when the run produced
#'   no diagnostic output.
#'
#' @examples
#' \dontrun{
#' blast_res <- parallel_blast(
#'   query_seqs = "CTAGCCATAAACTTAAATGAAGCTATACTAA",
#'   db_path = "path/to/blast_db"
#' )
#' exit_codes(blast_res)
#' }
#'
#' @export
exit_codes <- function(blast_res) {
  if (isFALSE("BLASTr_metadata" %in% names(attributes(blast_res)))) {
    cli::cli_abort(
      message = c(
        `x` = "The provided results do not contain {.field BLASTr_metadata}."
      ),
      class = "blastr_missing_metadata_error"
    )
  }
  metadata <- attributes(blast_res)$BLASTr_metadata

  if (is.null(metadata$exit_codes)) {
    cli::cli_abort(
      message = c(
        `x` = "No exit codes found in the provided BLAST results metadata."
      ),
      class = "blastr_missing_exit_codes_error"
    )
  }
  return(metadata$exit_codes) # nolint: return_linter
}
