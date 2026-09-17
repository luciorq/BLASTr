#' @title Get Sequence Headers from Subject IDs
#'
#' @description Retrieve the complete sequence titles stored in a BLAST
#'   database for one or more subject IDs.
#'
#' @inheritParams run_blast
#'
#' @param id One or more SubjectIDs from BLAST results (any identifier
#'   present in the database). Multiple IDs are fetched in a single
#'   `blastdbcmd` call.
#'
#' @returns Character vector with the complete title for each SubjectID
#'   as stored in the database.
#'
#' @examples
#' \dontrun{
#' dna_fasta_path <- fs::path_package(
#'   "BLASTr", "extdata", "minimal_db_blast",
#'   ext = "fasta"
#' )
#' temp_db_path <- fs::path_temp("minimal_db_blast")
#' make_blast_db(fasta_path = dna_fasta_path, db_path = temp_db_path)
#' get_fasta_header(id = "AP011979.1", db_path = temp_db_path)
#' }
#' @export
get_fasta_header <- function(
  id,
  db_path,
  env_name = "blastr-blast-env",
  verbose = c("silent", "cmd", "output", "full")
) {
  rlang::check_required(id)
  rlang::check_required(db_path)
  if (rlang::is_null(db_path)) {
    cli::cli_abort(
      message = "No BLAST database provided.",
      class = "blastr_missing_blast_db"
    )
  }
  verbose <- rlang::arg_match(verbose)

  withr::local_envvar(
    .new = list(
      BLAST_USAGE_REPORT = "false",
      NCBI_DONT_USE_NCBIRC = "true",
      NCBI_DONT_USE_LOCAL_CONFIG = "true"
    ),
    action = "replace"
  )

  # Fetch accession alongside title so results can be aligned to the
  # requested IDs: blastdbcmd outputs entries in database order, and a
  # bare title stream can misalign when titles are empty.
  blastdbcmd_res <- condathis::run_bin(
    "blastdbcmd",
    "-db",
    db_path,
    "-entry",
    paste(id, collapse = ","),
    "-outfmt",
    "%a\t%t",
    env_name = env_name,
    verbose = verbose
  )

  header_lines <- strsplit(
    stringr::str_trim(blastdbcmd_res$stdout),
    "\n",
    fixed = TRUE
  )[[1]]
  accession_vec <- stringr::str_remove(header_lines, "\t.*$")
  title_vec <- rlang::set_names(
    stringr::str_trim(
      stringr::str_remove(header_lines, "^[^\t]*\t?")
    ),
    accession_vec
  )
  if (isTRUE(all(id %in% accession_vec))) {
    # Return titles aligned to (and named by) the requested IDs.
    return(title_vec[as.character(id)])
  }
  return(title_vec)
}
