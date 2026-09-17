testthat::test_that("Get single taxid", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  res <- get_tax_by_taxID(organisms_taxIDs = "63221", verbose = "silent")

  testthat::expect_s3_class(res, "tbl_df")

  testthat::expect_equal(res$query_taxID, "63221")

  testthat::expect_true(stringr::str_detect(res$Sci_name, "Homo sapiens"))

  # 14 columns since 0.2.0: NCBI replaced `superkingdom` with `domain`,
  # both are returned.
  testthat::expect_equal(ncol(res), 14L)
  testthat::expect_equal(res$`Domain (NCBI)`, "Eukaryota")
  testthat::expect_equal(res$`Genus (NCBI)`, "Homo")
})

testthat::test_that("Get single taxid empty df", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  res <- get_tax_by_taxID(organisms_taxIDs = "10000000", verbose = "silent")

  testthat::expect_s3_class(res, "tbl_df")

  testthat::expect_equal(nrow(res), 0L)

  testthat::expect_equal(ncol(res), 14L)
})

testthat::test_that("Batched multiple taxids map by TaxId, not position", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  res <- get_tax_by_taxID(
    organisms_taxIDs = c("9606", "7955"),
    verbose = "silent"
  )

  testthat::expect_equal(nrow(res), 2L)
  testthat::expect_setequal(res$query_taxID, c("9606", "7955"))
  testthat::expect_equal(
    res$`Genus (NCBI)`[res$query_taxID == "7955"],
    "Danio"
  )
  testthat::expect_equal(
    res$`Genus (NCBI)`[res$query_taxID == "9606"],
    "Homo"
  )
})

testthat::test_that("Get parallel Single taxid", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  res <- parallel_get_tax(organisms_taxIDs = "63221", verbose = "silent")

  testthat::expect_equal(res$query_taxID, "63221")

  testthat::expect_true(stringr::str_detect(res$Sci_name, "Homo sapiens"))
})

testthat::test_that("Get parallel Multiple taxid", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  res <- parallel_get_tax(
    organisms_taxIDs = c("63221", "10000000"),
    total_cores = 1,
    retry_times = 2,
    verbose = "silent"
  )

  testthat::expect_equal(res$query_taxID, "63221")

  testthat::expect_true(stringr::str_detect(res$Sci_name, "Homo sapiens"))
})


testthat::test_that("Get parallel multi-core Multiple taxid", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  res <- parallel_get_tax(
    organisms_taxIDs = c("63221", "10000000"),
    total_cores = 2,
    retry_times = 2,
    verbose = "silent"
  )

  testthat::expect_equal(res$query_taxID, "63221")

  testthat::expect_true(stringr::str_detect(res$Sci_name, "Homo sapiens"))
})


testthat::test_that("`parallel_get_tax()` with `retry_times = 0` ", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  res <- parallel_get_tax(
    organisms_taxIDs = c("63221", "10000000"),
    total_cores = 1,
    retry_times = 0,
    verbose = "silent"
  )

  testthat::expect_equal(res$query_taxID, "63221")

  testthat::expect_true(stringr::str_detect(res$Sci_name, "Homo sapiens"))
})

testthat::test_that("`get_tax_by_name()` retrieves taxonomy by name", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  res <- get_tax_by_name("Danio rerio", verbose = "silent")

  testthat::expect_s3_class(res, "tbl_df")
  testthat::expect_equal(nrow(res), 1L)
  testthat::expect_equal(res$query_name, "Danio rerio")
  testthat::expect_equal(res$query_taxID, "7955")
  testthat::expect_equal(res$`Genus (NCBI)`, "Danio")
})

testthat::test_that("`get_tax_by_name()` with unmatched name", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  res <- get_tax_by_name(
    "Notarealtaxon xyzzyplugh",
    verbose = "silent"
  )

  testthat::expect_s3_class(res, "tbl_df")
  testthat::expect_equal(nrow(res), 0L)
  testthat::expect_true("query_name" %in% colnames(res))
})

testthat::test_that("parse_tax_xml resolves merged Tax IDs via AkaTaxIds", {
  # Regression: records for merged/deprecated Tax IDs come back under
  # the NEW TaxId with the queried ID only in <AkaTaxIds>; pre-fix the
  # queried ID was retried forever and reported unretrievable.
  merged_xml <- paste0(
    "<TaxaSet><Taxon>",
    "<TaxId>562</TaxId>",
    "<ScientificName>Escherichia coli</ScientificName>",
    "<AkaTaxIds><TaxId>662101</TaxId></AkaTaxIds>",
    "<Rank>species</Rank>",
    "<LineageEx>",
    "<Taxon><TaxId>561</TaxId>",
    "<ScientificName>Escherichia</ScientificName>",
    "<Rank>genus</Rank></Taxon>",
    "</LineageEx>",
    "</Taxon></TaxaSet>"
  )
  tax_long_tbl <- parse_tax_xml(merged_xml)
  # The record answers for both the canonical and the merged ID.
  testthat::expect_setequal(
    unique(tax_long_tbl$query_taxID),
    c("562", "662101")
  )
  merged_rows <- tax_long_tbl[tax_long_tbl$query_taxID == "662101", ]
  testthat::expect_true("genus" %in% merged_rows$Rank)
  testthat::expect_equal(unique(merged_rows$Sci_name), "Escherichia coli")
})
