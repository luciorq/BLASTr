#' @title Make BLAST Database
#'
#' @description Create a BLAST database from a FASTA file.
#'
#' @param fasta_path Path to the input FASTA file.
#' @param db_path Path prefix for the output BLAST database files.
#'   Defaults to `NULL`, which creates the database alongside the input
#'   FASTA file (BLAST+ `makeblastdb` default). Provide a path in a
#'   writable directory when the FASTA file lives in a read-only location
#'   (e.g. an installed package directory).
#' @param db_type Type of database to create, either `"nucl"` or `"prot"`.
#' @param taxid_map Optional path to a file mapping sequence IDs to NCBI
#'   Taxonomy IDs, passed to `makeblastdb -taxid_map`. The file must have
#'   one `<SequenceId> <TaxonomyId>` pair per line. Requires
#'   `parse_seqids = TRUE`.
#' @param parse_seqids Whether to parse sequence IDs (`-parse_seqids`).
#' @param verbose Verbosity level. One of `"silent"` (default), `"cmd"`,
#'   `"output"`, or `"full"`.
#' @param env_name Name of the conda environment used to run the
#'   command-line tools. Defaults to `"blastr-blast-env"`.
#'
#' @returns Invisibly returns the result of the `makeblastdb` command.
#'
#' @examples
#' \dontrun{
#' make_blast_db(
#'   fasta_path = fs::path_package(
#'     "BLASTr", "extdata", "minimal_db_blast",
#'     ext = "fasta"
#'   ),
#'   db_path = fs::path_temp("minimal_db_blast"),
#'   db_type = "nucl"
#' )
#' }
#'
#' @export
make_blast_db <- function(
  fasta_path,
  db_path = NULL,
  db_type = "nucl",
  taxid_map = NULL,
  parse_seqids = TRUE,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = "blastr-blast-env"
) {
  rlang::check_required(fasta_path)
  verbose <- rlang::arg_match(verbose)
  check_cmd(cmd = "makeblastdb", env_name = env_name, verbose = verbose)

  if (isFALSE(fs::file_exists(fasta_path))) {
    cli::cli_abort(
      message = c(
        `x` = "Input FASTA file {.file {fasta_path}} does not exist."
      ),
      class = "blastr_fasta_file_not_readable"
    )
  }

  args <- c(
    "-in",
    fasta_path,
    "-dbtype",
    db_type
  )

  if (!rlang::is_null(db_path)) {
    args <- c(args, "-out", db_path)
  }

  if (isTRUE(parse_seqids)) {
    args <- c(args, "-parse_seqids")
  }

  if (!rlang::is_null(taxid_map)) {
    if (isFALSE(fs::file_exists(taxid_map))) {
      cli::cli_abort(
        message = c(
          `x` = "The {.arg taxid_map} file {.file {taxid_map}} does not exist." # nolint: line_length_linter
        ),
        class = "blastr_taxid_map_not_readable"
      )
    }
    if (isFALSE(parse_seqids)) {
      cli::cli_abort(
        message = c(
          `x` = "{.arg taxid_map} requires {.code parse_seqids = TRUE}."
        ),
        class = "blastr_taxid_map_requires_parse_seqids"
      )
    }
    args <- c(args, "-taxid_map", taxid_map)
  }

  if (isTRUE(verbose %in% c("cmd", "full"))) {
    cli::cli_inform(
      c(
        `i` = "Command used: {.code makeblastdb {paste(args, collapse = ' ')}}" # nolint: line_length_linter
      )
    )
  }

  # NOTE: Opt out of BLAST+ usage reporting ("phone home")
  withr::local_envvar(
    .new = list(
      BLAST_USAGE_REPORT = "false"
    ),
    action = "replace"
  )
  blast_db_res <- condathis::run(
    cmd = "makeblastdb",
    args,
    env_name = env_name,
    verbose = verbose,
    error = "continue"
  )

  if (isTRUE(blast_db_res$status != 0L)) {
    error_msg_list <- stringr::str_extract_all(blast_db_res$stderr, "Error:.*")

    if (isTRUE(length(unlist(error_msg_list)) > 0)) {
      error_msg_vector <- unlist(error_msg_list)
      names(error_msg_vector) <- c(rep("x", times = length(error_msg_vector)))
    } else {
      error_msg_vector <- blast_db_res$stderr
    }

    cli::cli_abort(
      message = c(
        `!` = "Status code: {.val {blast_db_res$status}}",
        error_msg_vector
      ),
      class = "blastr_error_make_blast_db"
    )
  }

  return(invisible(blast_db_res))
}
