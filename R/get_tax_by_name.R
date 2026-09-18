#' @title Retrieve Taxonomic Ranks Using Organism Names
#'
#' @description Recover complete taxonomy for organism names by searching
#'   the NCBI Taxonomy database (E-utilities `esearch`) and fetching the
#'   matching records (`efetch`), directly over HTTPS - no command-line
#'   tool is required. The output schema matches [get_tax_by_taxID()],
#'   with an additional `query_name` column mapping each result back to
#'   the searched name.
#'
#' @param organisms_names Character vector of organism names (e.g.
#'   scientific names) to retrieve taxonomy for.
#' @param parse_result Logical indicating whether to parse the taxonomy
#'   information into a wide tibble (`TRUE`, default) or return the long
#'   lineage table (`FALSE`).
#' @param verbose Verbosity level. One of `"silent"` (default), `"cmd"`,
#'   `"output"`, or `"full"`.
#' @param env_name `r lifecycle::badge("deprecated")` No longer used:
#'   NCBI is queried directly over HTTPS.
#'
#' @returns A tibble with the taxonomic ranks for the matching organisms.
#'   Names with no match in NCBI Taxonomy are absent from the result.
#'
#' @examples
#' \dontrun{
#' tax_info <- get_tax_by_name("Danio rerio")
#'
#' tax_info <- get_tax_by_name(c("Homo sapiens", "Danio rerio"))
#' }
#'
#' @export
get_tax_by_name <- function(
  organisms_names,
  parse_result = TRUE,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = deprecated()
) {
  rlang::check_required(organisms_names)
  verbose <- rlang::arg_match(verbose)
  warn_env_name_deprecated(env_name, "get_tax_by_name")
  organisms_names <- stringr::str_trim(as.character(organisms_names))

  # Step 1 (per name, unavoidable): resolve each organism name to its
  # matching Tax IDs with `esearch` - a tiny response compared to the
  # full XML records.
  name_map_list <- list()
  for (organism_name in organisms_names) {
    search_res <- ncbi_taxonomy_search(
      term = organism_name,
      verbose = verbose
    )
    if (isFALSE(search_res$status == 0L)) {
      if (isFALSE(identical(verbose, "silent"))) {
        cli::cli_inform(
          c(
            `!` = "Unable to retrieve taxonomy for {.val {organism_name}}: {search_res$error}." # nolint: line_length_linter
          )
        )
      }
      next
    }
    name_taxids <- search_res$ids
    if (isTRUE(length(name_taxids) == 0L)) {
      if (isFALSE(identical(verbose, "silent"))) {
        cli::cli_inform(
          c(
            `!` = "No NCBI Taxonomy match for {.val {organism_name}}."
          )
        )
      }
      next
    }
    name_map_list <- c(
      name_map_list,
      list(
        tibble::tibble(
          `query_name` = organism_name,
          `query_taxID` = name_taxids
        )
      )
    )
  }

  if (isTRUE(length(name_map_list) == 0L)) {
    empty_tbl <- format_tax_tbl(NULL, parse_result = parse_result)
    empty_tbl$query_name <- character(0L)
    return(dplyr::relocate(empty_tbl, "query_name"))
  }
  name_map_tbl <- purrr::list_rbind(name_map_list)

  # Step 2 (single batched request, with retries): fetch all lineages at
  # once through the same machinery as parallel_get_tax().
  tax_long_tbl <- parallel_get_tax(
    organisms_taxIDs = unique(name_map_tbl$query_taxID),
    parse_result = FALSE,
    verbose = verbose
  )

  if (isTRUE(nrow(tax_long_tbl) == 0L)) {
    empty_tbl <- format_tax_tbl(NULL, parse_result = parse_result)
    empty_tbl$query_name <- character(0L)
    return(dplyr::relocate(empty_tbl, "query_name"))
  }

  tax_long_tbl <- dplyr::inner_join(
    name_map_tbl,
    tax_long_tbl,
    by = "query_taxID",
    relationship = "many-to-many"
  )

  if (isFALSE(identical(verbose, "silent"))) {
    retrieved_names <- unique(tax_long_tbl$query_name)
    cli::cli_inform(
      c(
        `v` = "Taxonomy retrieved successfully for {.val {retrieved_names}}."
      )
    )
  }

  if (rlang::is_false(parse_result)) {
    return(dplyr::relocate(tax_long_tbl, "query_name"))
  }

  # Format each name group separately so `query_name` survives the pivot.
  tax_final_tbl <- tax_long_tbl |>
    dplyr::group_split(.data$query_name) |>
    purrr::map(
      .f = \(name_tbl) {
        name_value <- unique(name_tbl$query_name)
        parsed_tbl <- format_tax_tbl(
          dplyr::select(name_tbl, -"query_name"),
          parse_result = TRUE
        )
        parsed_tbl$query_name <- name_value
        parsed_tbl
      }
    ) |>
    purrr::list_rbind() |>
    dplyr::relocate("query_name")

  return(tax_final_tbl)
}
