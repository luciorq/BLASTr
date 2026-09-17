testthat::test_that("run_blast works", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  asvs_test <- readLines(fs::path_package(
    "BLASTr",
    "extdata",
    "asvs_test",
    ext = "txt"
  ))
  db_path <- tmp_blast_db_path

  blast_res <- run_blast(
    query_seqs = asvs_test[1],
    db_path = db_path,
    verbose = "silent"
  )

  testthat::expect_equal(blast_res$status, 0)
})

testthat::test_that("run_blast fails", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  asvs_test <- readLines(fs::path_package(
    "BLASTr",
    "extdata",
    "asvs_test",
    ext = "txt"
  ))
  db_path <- tmp_blast_db_path

  testthat::expect_error(
    run_blast(
      query_seqs = asvs_test[1],
      db_path = db_path,
      perc_id = "MISSING_VALUE_STRInG",
      verbose = "silent"
    ),
    class = "blastr_error_blast_run"
  )
})

testthat::test_that("run_blast searches multiple sequences as separate queries", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  asvs_test <- readLines(fs::path_package(
    "BLASTr",
    "extdata",
    "asvs_test",
    ext = "txt"
  ))
  db_path <- tmp_blast_db_path

  blast_res <- run_blast(
    query_seqs = asvs_test,
    db_path = db_path,
    verbose = "silent"
  )

  testthat::expect_equal(blast_res$status, 0)
  # Multiple distinct query ids must be present in the raw output.
  query_ids <- unique(sub("\t.*", "", strsplit(blast_res$stdout, "\n")[[1]]))
  testthat::expect_gt(length(query_ids), 1L)
  testthat::expect_true(all(grepl("^BLASTrQ", query_ids)))
})
