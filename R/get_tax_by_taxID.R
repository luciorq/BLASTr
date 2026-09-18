#' Retrieve Taxonomic Ranks Using NCBI Taxonomy Tax IDs
#'
#' Retrieves complete taxonomy information for given NCBI Taxonomy Tax IDs
#' by querying the NCBI E-utilities (`efetch`) directly over HTTPS - no
#' command-line tool is required. Multiple Tax IDs are fetched in a single
#' batched request. Each record in the
#' response is matched back to its Tax ID through the XML `<TaxId>`
#' element, so results are correct regardless of response order.
#'
#' Note: NCBI Taxonomy replaced the `superkingdom` rank with `domain` in
#' its 2024/2025 restructure; both are returned
#' (`Domain (NCBI)` / `Superkingdom (NCBI)`).
#'
#' @param organisms_taxIDs A character vector of NCBI Taxonomy Tax IDs for
#'   which to retrieve taxonomy information.
#' @param parse_result Logical indicating whether to parse the taxonomy
#'   information into a wide tibble (`TRUE`, default) or return the long
#'   lineage table (`FALSE`).
#' @param verbose Verbosity level. One of `"silent"` (default), `"cmd"`,
#'   `"output"`, or `"full"`.
#' @param env_name `r lifecycle::badge("deprecated")` No longer used:
#'   NCBI is queried directly over HTTPS. See [parallel_get_tax()] for
#'   NCBI rate limits and the `NCBI_API_KEY` environment variable.
#'
#' @returns A tibble containing the taxonomic ranks for the given Tax IDs.
#'   Tax IDs that cannot be retrieved are absent from the result.
#'
#' @examples
#' \dontrun{
#' # Retrieve taxonomy for a single Tax ID
#' tax_info <- get_tax_by_taxID("9606") # Human
#'
#' # Retrieve taxonomy for multiple Tax IDs (single batched request)
#' tax_ids <- c("9606", "10090", "10116") # Human, Mouse, Rat
#' tax_info <- get_tax_by_taxID(tax_ids)
#'
#' # Get unparsed (long) taxonomy result
#' raw_tax_info <- get_tax_by_taxID("9606", parse_result = FALSE)
#'
#' # Enable verbose output
#' tax_info <- get_tax_by_taxID("9606", verbose = "output")
#' }
#' @export
get_tax_by_taxID <- function(
  organisms_taxIDs, # nolint: object_name_linter
  parse_result = TRUE,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = deprecated()
) {
  rlang::check_required(organisms_taxIDs)
  verbose <- rlang::arg_match(verbose)
  warn_env_name_deprecated(env_name, "get_tax_by_taxID")
  organisms_taxIDs <- stringr::str_trim(as.character(organisms_taxIDs)) # nolint: object_name_linter

  tax_xml_res <- fetch_tax_xml(
    taxids = organisms_taxIDs,
    verbose = verbose
  )

  tax_long_tbl <- NULL
  if (isTRUE(tax_xml_res$status == 0L)) {
    tax_long_tbl <- parse_tax_xml(tax_xml_res$stdout)
  }
  if (!rlang::is_null(tax_long_tbl)) {
    # Keep only requested IDs (merged-ID records are emitted under both
    # their old and new Tax IDs by the parser).
    tax_long_tbl <- dplyr::filter(
      tax_long_tbl,
      .data$query_taxID %in% organisms_taxIDs
    )
    if (isTRUE(nrow(tax_long_tbl) == 0L)) {
      tax_long_tbl <- NULL
    }
  }

  if (rlang::is_null(tax_long_tbl)) {
    if (isFALSE(identical(verbose, "silent"))) {
      cli::cli_inform(
        c(
          `!` = "Unable to retrieve taxonomy for: {.val {organisms_taxIDs}}."
        )
      )
    }
    return(format_tax_tbl(NULL, parse_result = parse_result))
  }

  if (isFALSE(identical(verbose, "silent"))) {
    retrieved_ids <- unique(tax_long_tbl$query_taxID)
    cli::cli_inform(
      c(
        `v` = "Taxonomy data retrieved successfully for {.val {retrieved_ids}}." # nolint: line_length_linter
      )
    )
    missing_ids <- setdiff(organisms_taxIDs, retrieved_ids)
    if (isTRUE(length(missing_ids) > 0L)) {
      cli::cli_inform(
        c(
          `!` = "Unable to retrieve taxonomy for: {.val {missing_ids}}."
        )
      )
    }
  }

  return(format_tax_tbl(tax_long_tbl, parse_result = parse_result))
}
