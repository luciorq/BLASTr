make_toy_fastq <- function(dir_path) {
  # 6 reads: 3 contain the degenerate primer motif ACWGGT
  # (as ACAGGT/ACTGGT), 1 contains its reverse complement, 2 neither.
  reads <- c(
    "TTTTACAGGTTTTTTTTTTT",
    "TTTTACTGGTTTTTTTTTTT",
    "GGGGACAGGTGGGGGGGGGG",
    "CCCCACCTGTCCCCCCCCCC",
    "AAAAAAAAAAAAAAAAAAAA",
    "CCCCCCCCCCCCCCCCCCCC"
  )
  fq_lines <- unlist(lapply(seq_along(reads), function(i) {
    c(paste0("@read_", i), reads[i], "+", strrep("I", nchar(reads[i])))
  }))
  fq_path <- fs::path(dir_path, "toy.fastq")
  writeLines(fq_lines, fq_path)
  gz_path <- fs::path(dir_path, "toy.fastq.gz")
  gz_con <- gzfile(gz_path, "w")
  writeLines(fq_lines, gz_con)
  close(gz_con)
  c(fq_path, gz_path)
}

testthat::test_that("search_primers_on_fq counts degenerate matches", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  fq_dir <- withr::local_tempdir("primer-fq")
  fq_paths <- make_toy_fastq(fq_dir)

  res <- search_primers_on_fq(
    primer_seqs = c(TEST = "ACWGGT"),
    fastq_paths = fq_paths
  )

  testthat::expect_s3_class(res, "tbl_df")
  testthat::expect_equal(nrow(res), 2L)
  testthat::expect_equal(res$total_reads, c(6, 6))
  # Both strands by default: 3 forward + 1 reverse-complement match.
  testthat::expect_equal(res$primer_matches, c(4, 4))
  testthat::expect_equal(res$percentage, c(4, 4) / 6 * 100)

  res_pos <- search_primers_on_fq(
    primer_seqs = c(TEST = "ACWGGT"),
    fastq_paths = fq_paths[1],
    only_positive_strand = TRUE
  )
  testthat::expect_equal(res_pos$primer_matches, 3)
})

testthat::test_that("search_primers_on_fq validates inputs", {
  fq_dir <- withr::local_tempdir("primer-fq")
  fq_paths <- make_toy_fastq(fq_dir)

  search_primers_on_fq(
    primer_seqs = c(BAD = "AC!XGT"),
    fastq_paths = fq_paths[1]
  ) |>
    testthat::expect_error(class = "blastr_invalid_primer_error")

  search_primers_on_fq(
    primer_seqs = c(OK = "ACGT"),
    fastq_paths = "does-not-exist.fastq"
  ) |>
    testthat::expect_error(class = "blastr_fastq_file_not_readable")
})

testthat::test_that("duplicated primer names are repaired and all searched", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  fq_dir <- withr::local_tempdir("primer-fq")
  fq_paths <- make_toy_fastq(fq_dir)

  # Regression: indexing by name always fetched the first `V3` primer,
  # silently never searching the second.
  testthat::expect_warning(
    res <- search_primers_on_fq(
      primer_seqs = c(V3 = "ACWGGT", V3 = "AAAAAAAAAAAAAAAAAAAA"),
      fastq_paths = fq_paths[1]
    ),
    regexp = "Duplicated primer names"
  )
  testthat::expect_equal(res$primer_name, c("V3", "V3_1"))
  testthat::expect_equal(
    res$primer_sequence,
    c("ACWGGT", "AAAAAAAAAAAAAAAAAAAA")
  )
  # Distinct primers must yield their own counts (4 vs 1 matches).
  testthat::expect_equal(res$primer_matches, c(4, 1))
})
