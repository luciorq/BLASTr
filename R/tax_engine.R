# Internal engine shared by `get_tax_by_taxID()`, `get_tax_by_name()`,
# and `parallel_get_tax()`.
#
# NOTE: NCBI Taxonomy replaced the `superkingdom` rank with `domain`
# (and introduced `cellular root` / `acellular root`) in the 2024/2025
# taxonomy restructure. Both `domain` and the legacy `superkingdom` are
# parsed so results are correct for current and archived data.

# Lineage ranks retained in parsed output, in taxonomic order.
tax_ranks_keep <- c(
  "domain",
  "superkingdom",
  "kingdom",
  "phylum",
  "subphylum",
  "class",
  "subclass",
  "order",
  "suborder",
  "family",
  "subfamily",
  "genus"
)

# Output column names for the parsed (wide) schema.
tax_rank_col_names <- paste0(
  stringr::str_to_title(tax_ranks_keep),
  " (NCBI)"
)

#' Empty tibble with the parsed taxonomy schema
#' @keywords internal
#' @noRd
empty_tax_parsed_tbl <- function() {
  col_names <- c("Sci_name", "query_taxID", tax_rank_col_names)
  tbl <- tibble::as_tibble(
    stats::setNames(
      rep(list(character(0L)), length(col_names)),
      col_names
    )
  )
  return(tbl)
}

#' Empty tibble with the unparsed (long) taxonomy schema
#' @keywords internal
#' @noRd
empty_tax_long_tbl <- function() {
  tibble::tibble(
    "Rank" = character(0L),
    "ScientificName" = character(0L),
    "query_taxID" = character(0L),
    "Sci_name" = character(0L)
  )
}

#' Build a self-contained worker fetching taxonomy XML for Tax IDs
#'
#' Equivalent to `efetch -db taxonomy -id <id1,id2,...> -format xml`,
#' issued directly to the NCBI E-utilities (`efetch.fcgi`).
#' Invalid Tax IDs are silently omitted from the response by NCBI
#' (the request still succeeds for the valid ones).
#' Returned as a `carrier::crate()` so the same worker serves both the
#' serial path and `mirai` daemons.
#'
#' @returns `function(taxids)` giving `list(status, stdout, stderr)`:
#'   `status` is `0L` on success, `stdout` the XML body, `stderr` the
#'   error message (`NA` on success).
#' @keywords internal
#' @noRd
make_tax_fetch_worker <- function(verbose = "silent", rate_share = 1L) {
  carrier::crate(
    function(taxids) {
      fetch_res <- eutils_worker(
        "efetch.fcgi",
        list(
          db = "taxonomy",
          id = base::paste(taxids, collapse = ","),
          retmode = "xml"
        )
      )
      list(
        status = fetch_res$status,
        stdout = fetch_res$body,
        stderr = fetch_res$error
      )
    },
    eutils_worker = make_eutils_worker(
      verbose = verbose,
      rate_share = rate_share
    )
  )
}

#' Is an `efetch` taxonomy body a well-formed `TaxaSet` document?
#'
#' NCBI answers a batch whose IDs are all unknown with HTTP 200 and an
#' empty `<TaxaSet/>`; unknown IDs in a mixed batch are simply omitted.
#' A well-formed `TaxaSet` therefore means every ID it does not mention
#' is definitively unknown (no point retrying), whereas an unparsable
#' body (e.g. an HTML error page served with 200) is transient.
#'
#' @keywords internal
#' @noRd
tax_xml_is_valid <- function(xml_string) {
  if (rlang::is_null(xml_string) || isFALSE(nzchar(xml_string))) {
    return(FALSE)
  }
  xml_doc <- tryCatch(
    xml2::read_xml(xml_string),
    error = function(e) NULL
  )
  if (rlang::is_null(xml_doc)) {
    return(FALSE)
  }
  identical(xml2::xml_name(xml_doc), "TaxaSet")
}

#' Fetch taxonomy XML from NCBI for a set of Tax IDs
#' @keywords internal
#' @noRd
fetch_tax_xml <- function(taxids, verbose = "silent") {
  fetch_worker <- make_tax_fetch_worker(verbose = verbose)
  fetch_worker(taxids)
}

#' Parse NCBI taxonomy XML into a long tibble
#'
#' Each `<Taxon>` record is mapped through its own `<TaxId>` element, so
#' results are correct regardless of the order NCBI returns records in
#' (which does not necessarily match the request order).
#'
#' @returns A tibble with columns `Rank`, `ScientificName`,
#'   `query_taxID`, `Sci_name`, or `NULL` if the XML cannot be parsed.
#'
#' @keywords internal
#' @noRd
parse_tax_xml <- function(xml_string) {
  if (
    rlang::is_null(xml_string) ||
      isFALSE(nzchar(xml_string)) ||
      isFALSE(stringr::str_detect(xml_string, "TaxId"))
  ) {
    return(NULL)
  }
  xml_doc <- tryCatch(
    xml2::read_xml(xml_string),
    error = function(e) NULL
  )
  if (rlang::is_null(xml_doc)) {
    return(NULL)
  }
  taxon_nodes <- xml2::xml_find_all(xml_doc, "./Taxon")
  if (isTRUE(length(taxon_nodes) == 0L)) {
    return(NULL)
  }
  taxon_tbl_list <- purrr::map(
    .x = taxon_nodes,
    .f = function(taxon_node) {
      tax_id <- xml2::xml_text(
        xml2::xml_find_first(taxon_node, "./TaxId")
      )
      # Merged/deprecated Tax IDs: NCBI returns the record under the
      # *new* TaxId, listing the queried (old) ID only in <AkaTaxIds>.
      # Emit the record under every ID it answers for, so requests by a
      # merged ID resolve instead of being retried and misreported.
      aka_ids <- xml2::xml_text(
        xml2::xml_find_all(taxon_node, "./AkaTaxIds/TaxId")
      )
      record_ids <- unique(c(tax_id, aka_ids))
      sci_name <- xml2::xml_text(
        xml2::xml_find_first(taxon_node, "./ScientificName")
      )
      own_rank <- xml2::xml_text(
        xml2::xml_find_first(taxon_node, "./Rank")
      )
      lineage_nodes <- xml2::xml_find_all(
        taxon_node,
        "./LineageEx/Taxon"
      )
      # The taxon's own rank entry completes the lineage (LineageEx only
      # contains ancestors).
      record_tbl <- tibble::tibble(
        `Rank` = c(
          xml2::xml_text(
            xml2::xml_find_first(lineage_nodes, "./Rank")
          ),
          own_rank
        ),
        `ScientificName` = c(
          xml2::xml_text(
            xml2::xml_find_first(lineage_nodes, "./ScientificName")
          ),
          sci_name
        ),
        `Sci_name` = sci_name
      )
      purrr::list_rbind(
        purrr::map(
          record_ids,
          \(record_id) {
            dplyr::mutate(record_tbl, `query_taxID` = record_id)
          }
        )
      )
    }
  )
  tax_long_tbl <- purrr::list_rbind(taxon_tbl_list)
  dplyr::relocate(tax_long_tbl, "query_taxID", .after = "ScientificName")
}

#' Format the long taxonomy tibble into the requested output schema
#' @keywords internal
#' @noRd
format_tax_tbl <- function(tax_long_tbl, parse_result = TRUE) {
  if (rlang::is_false(parse_result)) {
    if (rlang::is_null(tax_long_tbl)) {
      return(empty_tax_long_tbl())
    }
    return(
      dplyr::bind_rows(tax_long_tbl, empty_tax_long_tbl())
    )
  }
  if (rlang::is_null(tax_long_tbl) || isTRUE(nrow(tax_long_tbl) == 0L)) {
    return(empty_tax_parsed_tbl())
  }
  rank_rename_map <- stats::setNames(tax_ranks_keep, tax_rank_col_names)
  tax_wide_tbl <- tax_long_tbl |>
    dplyr::filter(.data$Rank %in% tax_ranks_keep) |>
    dplyr::distinct() |>
    tidyr::pivot_wider(
      id_cols = c("query_taxID", "Sci_name"),
      names_from = "Rank",
      values_from = "ScientificName",
      # Defensive: a duplicated rank within one lineage must not create
      # list columns.
      values_fn = \(x) paste(unique(x), collapse = ";")
    ) |>
    dplyr::bind_rows(
      empty_tax_parsed_tbl() |>
        dplyr::rename(dplyr::all_of(
          stats::setNames(tax_rank_col_names, tax_ranks_keep)
        ))
    ) |>
    dplyr::relocate(
      dplyr::all_of(c("Sci_name", "query_taxID", tax_ranks_keep))
    ) |>
    dplyr::rename(dplyr::all_of(rank_rename_map)) |>
    dplyr::filter(!dplyr::if_all(dplyr::everything(), rlang::are_na))
  return(tax_wide_tbl)
}
