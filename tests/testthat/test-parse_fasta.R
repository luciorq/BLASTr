testthat::test_that("parse_fasta extracts sequences", {
  fasta_path <- fs::path_package(
    "BLASTr",
    "extdata",
    "minimal_db_blast",
    ext = "fasta"
  )
  seqs <- parse_fasta(file_path = fasta_path)

  testthat::expect_type(seqs, "character")
  testthat::expect_gt(length(seqs), 0L)
  # Sequences only: no FASTA headers, no empty entries.
  testthat::expect_false(any(startsWith(seqs, ">")))
  testthat::expect_true(all(nzchar(seqs)))
})

testthat::test_that("parse_fasta joins multi-line records", {
  fasta_path <- withr::local_tempfile(fileext = ".fasta")
  writeLines(
    c(">seq1", "ACGT", "ACGT", ">seq2", "TTTT"),
    fasta_path
  )
  seqs <- parse_fasta(file_path = fasta_path)
  testthat::expect_equal(seqs, c("ACGTACGT", "TTTT"))
})

testthat::test_that("parse_fasta errors on missing file", {
  parse_fasta(file_path = "does-not-exist.fasta") |>
    testthat::expect_error(class = "blastr_fasta_file_not_readable")
})
