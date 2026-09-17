testthat::test_that("`make_blast_db()` works", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  fasta_path <- fs::path_package(
    "BLASTr",
    "extdata",
    "minimal_db_blast",
    ext = "fasta"
  )
  db_path <- fs::file_temp("minimal_db_blast_")

  db_res <- make_blast_db(
    fasta_path = fasta_path,
    db_path = db_path,
    db_type = "nucl",
    verbose = "silent"
  )

  testthat::expect_equal(db_res$status, 0)
  testthat::expect_true(fs::file_exists(paste0(db_path, ".nsq")))
})

testthat::test_that("`make_blast_db()` fails with wrong db_type", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  fasta_path <- fs::path_package(
    "BLASTr",
    "extdata",
    "minimal_db_blast",
    ext = "fasta"
  )
  db_path <- fs::file_temp("minimal_db_blast_")

  testthat::expect_error(
    make_blast_db(
      fasta_path = fasta_path,
      db_path = db_path,
      db_type = "INVALID_DB_TYPE",
      verbose = "silent"
    ),
    class = "blastr_error_make_blast_db"
  )
})

testthat::test_that("`make_blast_db()` works with `taxid_map`", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  fasta_path <- fs::path_package(
    "BLASTr",
    "extdata",
    "minimal_db_blast",
    ext = "fasta"
  )
  db_path <- fs::file_temp("minimal_db_blast_")
  taxid_map_path <- fs::file_temp("taxid_map_", ext = "tsv")
  write("AY882416	2759", taxid_map_path)

  db_res <- make_blast_db(
    fasta_path = fasta_path,
    db_path = db_path,
    db_type = "nucl",
    taxid_map = taxid_map_path,
    verbose = "silent"
  )

  testthat::expect_equal(db_res$status, 0)
  testthat::expect_true(fs::file_exists(paste0(db_path, ".nsq")))
})

testthat::test_that("`make_blast_db()` works with `parse_seqids`", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  fasta_path <- fs::path_package(
    "BLASTr",
    "extdata",
    "minimal_db_blast",
    ext = "fasta"
  )
  db_path <- fs::file_temp("minimal_db_blast_")
  taxid_map_path <- fs::file_temp("taxid_map_", ext = "tsv")
  write("AY882416	2759", taxid_map_path)

  db_res <- make_blast_db(
    fasta_path = fasta_path,
    db_path = db_path,
    db_type = "nucl",
    taxid_map = taxid_map_path,
    verbose = "silent"
  )

  testthat::expect_equal(db_res$status, 0)
  testthat::expect_true(fs::file_exists(paste0(db_path, ".nsq")))
})

testthat::test_that("`make_blast_db()` with taxid_map yields staxid in results", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  fasta_path <- fs::path_package(
    "BLASTr",
    "extdata",
    "minimal_db_blast",
    ext = "fasta"
  )
  taxid_map_path <- fs::path_package(
    "BLASTr",
    "extdata",
    "minimal_db_blast",
    ext = "txt"
  )
  db_path <- fs::file_temp("minimal_db_taxid_")

  db_res <- make_blast_db(
    fasta_path = fasta_path,
    db_path = db_path,
    db_type = "nucl",
    taxid_map = taxid_map_path,
    verbose = "silent"
  )

  testthat::expect_equal(db_res$status, 0)
  testthat::expect_true(fs::file_exists(paste0(db_path, ".nsq")))

  asvs_test <- readLines(
    fs::path_package("BLASTr", "extdata", "asvs_test", ext = "txt")
  )

  blast_res <- parallel_blast(
    query_seqs = asvs_test,
    db_path = db_path,
    retry_times = 0,
    verbose = "silent"
  )

  top_taxids <- blast_res$`1_staxid`
  top_taxids <- top_taxids[!is.na(top_taxids)]
  # Every top hit must carry a real Tax ID from the map (not "N/A").
  testthat::expect_gt(length(top_taxids), 0L)
  testthat::expect_false(any(top_taxids == "N/A"))
  # Known mapping from the packaged taxid map: the Gymnotus carapo query
  # (first test ASV) hits AP011979.1 -> taxid 94172.
  testthat::expect_equal(blast_res$`1_staxid`[1], "94172")

  # Round-trip: resolve the Tax IDs to taxonomy.
  tax_res <- parallel_get_tax(
    organisms_taxIDs = unique(top_taxids),
    retry_times = 2,
    verbose = "silent"
  )
  testthat::expect_true(is.data.frame(tax_res))
  testthat::expect_setequal(tax_res$query_taxID, unique(top_taxids))
})

testthat::test_that("get_fasta_header aligns titles to requested IDs", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Request in reverse database order: titles must follow request order.
  headers <- get_fasta_header(
    id = c("CP030121.1", "AP011979.1"),
    db_path = tmp_blast_db_path,
    verbose = "silent"
  )
  testthat::expect_equal(names(headers), c("CP030121.1", "AP011979.1"))
  testthat::expect_true(
    stringr::str_detect(headers[["AP011979.1"]], "Gymnotus carapo")
  )
  testthat::expect_true(
    stringr::str_detect(headers[["CP030121.1"]], "Brasilonema")
  )
})
