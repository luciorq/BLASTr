testthat::test_that("chunked, per-sequence, and parallel runs are equivalent", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  asvs_test <- readLines(
    fs::path_package("BLASTr", "extdata", "asvs_test", ext = "txt")
  )
  db_path <- tmp_blast_db_path

  res_chunked <- parallel_blast(
    query_seqs = asvs_test,
    db_path = db_path,
    retry_times = 0,
    verbose = "silent"
  )
  res_per_seq <- parallel_blast(
    query_seqs = asvs_test,
    db_path = db_path,
    chunk_size = 1,
    retry_times = 0,
    verbose = "silent"
  )
  res_parallel <- parallel_blast(
    query_seqs = asvs_test,
    db_path = db_path,
    total_cores = 2,
    retry_times = 0,
    verbose = "silent"
  )

  testthat::expect_equal(res_chunked, res_per_seq)
  testthat::expect_equal(res_chunked, res_parallel)

  # daemons created internally must be torn down
  testthat::expect_false(mirai::daemons_set())
})

testthat::test_that("malformed query inside a batch is salvaged", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  asvs_test <- readLines(
    fs::path_package("BLASTr", "extdata", "asvs_test", ext = "txt")
  )
  db_path <- tmp_blast_db_path

  blast_res <- parallel_blast(
    query_seqs = c(asvs_test[1], ">XAVADADAA"),
    db_path = db_path,
    chunk_size = 2,
    retry_times = 1,
    verbose = "silent"
  )

  testthat::expect_equal(nrow(blast_res), 2L)
  # The healthy query keeps its hits.
  testthat::expect_false(is.na(blast_res$`1_subject`[1]))

  exit_codes_df <- exit_codes(blast_res)
  # The malformed record is reported through stderr even when BLAST+
  # exits 0 for the batch.
  testthat::expect_true(
    stringr::str_detect(
      exit_codes_df$stderr[2],
      "Sequence contains no data"
    )
  )
})

testthat::test_that("failed queries produce a single row, not duplicates", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  db_path <- tmp_blast_db_path

  # Retried failures must not be duplicated in the output (regression
  # test: pre-0.2.0 appended one row per attempt).
  blast_res <- parallel_blast(
    query_seqs = ">XAVADADAA",
    db_path = db_path,
    retry_times = 3L,
    verbose = "silent"
  )
  testthat::expect_equal(nrow(blast_res), 1L)
  testthat::expect_equal(nrow(exit_codes(blast_res)), 1L)
})

testthat::test_that("duplicated input sequences are deduplicated", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  asvs_test <- readLines(
    fs::path_package("BLASTr", "extdata", "asvs_test", ext = "txt")
  )
  db_path <- tmp_blast_db_path

  blast_res <- parallel_blast(
    query_seqs = c(asvs_test[1], asvs_test[1], asvs_test[2]),
    db_path = db_path,
    retry_times = 0,
    verbose = "silent"
  )
  testthat::expect_equal(nrow(blast_res), 2L)
})

testthat::test_that("exit_codes errors without metadata", {
  df_no_meta <- tibble::tibble(x = 1)
  exit_codes(df_no_meta) |>
    testthat::expect_error(class = "blastr_missing_metadata_error")
})

testthat::test_that("parse_blast_stdout survives '#' and quote characters in titles", {
  # Regression: readr defaults (comment = '#', quote = '\"') truncated
  # titles at '#' and could crash on titles starting with '\"'.
  stdout_line <- paste(
    c(
      "BLASTrQ1",
      "seq1",
      "99.5",
      "100",
      "0",
      "0",
      "1",
      "100",
      "1",
      "100",
      "1e-50",
      "180",
      "100",
      "9606",
      "\"quoted\" clone #12 mitochondrial"
    ),
    collapse = "\t"
  )
  hits_tbl <- parse_blast_stdout(paste0(stdout_line, "\n"))
  testthat::expect_equal(nrow(hits_tbl), 1L)
  testthat::expect_equal(
    hits_tbl$`subject header`,
    "\"quoted\" clone #12 mitochondrial"
  )
  testthat::expect_equal(hits_tbl$seq_index, 1L)
})

testthat::test_that("zero-hit results keep the 1_ column group", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  no_hit_seq <- "AGAGTACTACAAGTGCTAGCCATAAACTTAAATGAAGCTATACTAAACTCGTTCGCCAAAGCTTAAAACTCATAGGACTTGGCGGTGTTTCAGACCCAC"

  blast_res <- parallel_blast(
    query_seqs = no_hit_seq,
    db_path = tmp_blast_db_path,
    retry_times = 0,
    verbose = "silent"
  )
  # Regression: pre-fix an all-miss batch returned only `Sequence`.
  for (col in c("1_subject", "1_staxid", "1_subject header", "1_identity")) {
    testthat::expect_true(col %in% colnames(blast_res))
  }
  testthat::expect_true(is.na(blast_res$`1_subject`[1]))
  testthat::expect_type(blast_res$`1_identity`, "double")
})

testthat::test_that("pre-existing daemons pool is adopted at default total_cores", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  asvs_test <- readLines(
    fs::path_package("BLASTr", "extdata", "asvs_test", ext = "txt")
  )

  mirai::daemons(2)
  withr::defer(mirai::daemons(0))

  blast_res <- parallel_blast(
    query_seqs = asvs_test,
    db_path = tmp_blast_db_path,
    retry_times = 0,
    verbose = "silent"
  )
  testthat::expect_equal(nrow(blast_res), length(asvs_test))
  # The externally-owned pool must survive (not be torn down).
  testthat::expect_true(mirai::daemons_set())
})

testthat::test_that("exit_codes stderr carries full BLAST warnings", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  asvs_test <- readLines(
    fs::path_package("BLASTr", "extdata", "asvs_test", ext = "txt")
  )

  blast_res <- parallel_blast(
    query_seqs = asvs_test[1],
    db_path = tmp_blast_db_path,
    num_alignments = 4,
    retry_times = 0,
    verbose = "silent"
  )
  exit_codes_df <- exit_codes(blast_res)
  # With num_alignments < 5 BLAST always warns "Examining 5 or more
  # matches is recommended"; that untagged process-level warning must
  # reach stderr (regression: only tagged warnings were kept).
  testthat::expect_true(
    stringr::str_detect(exit_codes_df$stderr[1], "Examining 5 or more")
  )
})
