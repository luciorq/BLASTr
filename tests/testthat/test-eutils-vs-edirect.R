# Validation of the pure-R E-utilities client against the real NCBI
# Entrez Direct tools. Entrez Direct is installed into a dedicated conda
# environment for these tests only (it is no longer a package
# dependency), so they run on Linux/macOS with network access and are
# skipped on CRAN and on Windows (no Entrez Direct conda build there).

edirect_env_name <- "blastr-test-edirect-env"

skip_if_no_edirect <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  testthat::skip_if(
    stringr::str_detect(get_sys_arch(), "^Windows"),
    "Entrez Direct has no Windows conda build"
  )
  if (isFALSE(condathis::env_exists(edirect_env_name))) {
    condathis::create_env(
      packages = "bioconda::entrez-direct==24.0",
      channels = c("conda-forge", "bioconda"),
      env_name = edirect_env_name,
      verbose = "silent"
    )
  }
}

# `efetch -db taxonomy -id ... -format xml`
edirect_fetch_xml <- function(taxids) {
  condathis::run(
    "efetch",
    "-db",
    "taxonomy",
    "-id",
    paste(taxids, collapse = ","),
    "-format",
    "xml",
    env_name = edirect_env_name,
    verbose = "silent",
    error = "continue"
  )
}

# `esearch -db taxonomy -query <name> | efetch -format uid`
edirect_search_ids <- function(organism_name) {
  res <- condathis::run(
    "bash",
    "-c",
    paste0(
      "esearch -db taxonomy -query ",
      shQuote(organism_name),
      " | efetch -format uid"
    ),
    env_name = edirect_env_name,
    verbose = "silent",
    error = "continue"
  )
  if (isFALSE(res$status == 0L)) {
    return(character(0L))
  }
  ids <- stringr::str_trim(strsplit(res$stdout, "\n", fixed = TRUE)[[1]])
  ids[nzchar(ids)]
}

sort_tax_long <- function(tbl) {
  dplyr::arrange(tbl, .data$query_taxID, .data$Rank, .data$ScientificName)
}

validation_taxids <- c(
  "9606", # Homo sapiens
  "63221", # Homo sapiens neanderthalensis (subspecies)
  "7955", # Danio rerio
  "562", # Escherichia coli (Bacteria)
  "4932", # Saccharomyces cerevisiae (Fungi)
  "3702", # Arabidopsis thaliana (Viridiplantae)
  "2157", # Archaea (domain-level record, no lineage)
  "10000000" # invalid: omitted by NCBI in both clients
)

testthat::test_that("efetch: R client returns the same taxonomy records as Entrez Direct", {
  skip_if_no_edirect()

  edirect_res <- edirect_fetch_xml(validation_taxids)
  testthat::expect_equal(edirect_res$status, 0L)
  r_res <- fetch_tax_xml(validation_taxids)
  testthat::expect_equal(r_res$status, 0L)

  edirect_tbl <- sort_tax_long(parse_tax_xml(edirect_res$stdout))
  r_tbl <- sort_tax_long(parse_tax_xml(r_res$stdout))

  testthat::expect_equal(r_tbl, edirect_tbl)
  # Every valid ID is present, the invalid one is absent, in both.
  testthat::expect_setequal(
    unique(r_tbl$query_taxID),
    setdiff(validation_taxids, "10000000")
  )
})

testthat::test_that("esearch: R client resolves names to the same Tax IDs as Entrez Direct", {
  skip_if_no_edirect()

  organism_names <- c(
    "Danio rerio",
    "Homo sapiens",
    "Mazama gouazoubira",
    "Escherichia coli",
    "Gymnotus carapo",
    "Notarealtaxon xyzzyplugh"
  )
  edirect_map <- purrr::map(organism_names, \(x) sort(edirect_search_ids(x)))
  r_map <- purrr::map(organism_names, \(x) sort(ncbi_taxonomy_search(x)$ids))
  names(edirect_map) <- organism_names
  names(r_map) <- organism_names
  testthat::expect_equal(r_map, edirect_map)
  # Sanity: real names resolved, the fake one did not (in both clients).
  testthat::expect_true(length(r_map[["Danio rerio"]]) >= 1L)
  testthat::expect_equal(length(r_map[["Notarealtaxon xyzzyplugh"]]), 0L)
})

testthat::test_that("public API matches a reference built from Entrez Direct output", {
  skip_if_no_edirect()

  valid_ids <- setdiff(validation_taxids, "10000000")
  reference_tbl <- edirect_fetch_xml(valid_ids)$stdout |>
    parse_tax_xml() |>
    dplyr::filter(.data$query_taxID %in% valid_ids) |>
    dplyr::distinct() |>
    format_tax_tbl(parse_result = TRUE) |>
    dplyr::arrange(.data$query_taxID)

  by_taxid <- get_tax_by_taxID(valid_ids, verbose = "silent") |>
    dplyr::arrange(.data$query_taxID)
  testthat::expect_equal(by_taxid, reference_tbl)

  in_parallel <- parallel_get_tax(
    valid_ids,
    total_cores = 2,
    batch_size = 3,
    retry_times = 2,
    verbose = "silent"
  ) |>
    dplyr::arrange(.data$query_taxID)
  testthat::expect_equal(in_parallel, reference_tbl)

  # Name search end to end: same lineage as Entrez Direct's own
  # esearch | efetch pipeline for that name.
  name_ids <- edirect_search_ids("Gymnotus carapo")
  name_reference <- edirect_fetch_xml(name_ids)$stdout |>
    parse_tax_xml() |>
    dplyr::filter(.data$query_taxID %in% name_ids) |>
    dplyr::distinct() |>
    format_tax_tbl(parse_result = TRUE) |>
    dplyr::arrange(.data$query_taxID)
  by_name <- get_tax_by_name("Gymnotus carapo", verbose = "silent")
  testthat::expect_equal(unique(by_name$query_name), "Gymnotus carapo")
  by_name <- by_name |>
    dplyr::select(-"query_name") |>
    dplyr::arrange(.data$query_taxID)
  testthat::expect_equal(by_name, name_reference)
})
