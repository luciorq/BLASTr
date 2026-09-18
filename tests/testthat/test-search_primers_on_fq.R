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

testthat::test_that("IUPAC helpers expand and reverse-complement primers", {
  testthat::expect_equal(primer_to_regex("ACWGGT"), "AC[AT]GGT")
  testthat::expect_equal(primer_to_regex("nRy"), "[ACGT][AG][CT]")
  testthat::expect_equal(reverse_complement_iupac("ACWGGT"), "ACCWGT")
  # Complement pairs: M<->K, R<->Y, B<->V, D<->H; W/S/N are their own.
  testthat::expect_equal(reverse_complement_iupac("MKRYBVDHWSN"), "NSWDHBVRYMK")
  testthat::expect_equal(reverse_complement_iupac("U"), "A")
})

testthat::test_that("search_primers_on_fq counts degenerate matches on both strands", {
  fq_dir <- withr::local_tempdir("primer-fq")
  fq_paths <- make_toy_fastq(fq_dir)

  res <- search_primers_on_fq(
    primer_seqs = c(TEST = "ACWGGT"),
    fastq_paths = fq_paths
  )

  testthat::expect_s3_class(res, "tbl_df")
  testthat::expect_equal(
    colnames(res),
    c(
      "file_name",
      "primer_name",
      "primer_sequence",
      "parsed_primer",
      "total_reads",
      "primer_matches",
      "percentage"
    )
  )
  testthat::expect_equal(nrow(res), 2L)
  testthat::expect_equal(res$parsed_primer, rep("AC[AT]GGT", 2L))
  testthat::expect_equal(res$total_reads, c(6, 6))
  # Both strands by default: 3 forward + 1 reverse-complement match, and
  # identical counts for the plain and gzip-compressed copies.
  testthat::expect_equal(res$primer_matches, c(4, 4))
  testthat::expect_equal(res$percentage, c(4, 4) / 6 * 100)

  res_pos <- search_primers_on_fq(
    primer_seqs = c(TEST = "ACWGGT"),
    fastq_paths = fq_paths[1],
    only_positive_strand = TRUE
  )
  testthat::expect_equal(res_pos$primer_matches, 3)
})

testthat::test_that("search_primers_on_fq streams in chunks and ignores case", {
  fq_dir <- withr::local_tempdir("primer-fq")
  fq_paths <- make_toy_fastq(fq_dir)

  # chunk_size smaller than the file: counts must not depend on it.
  res_chunked <- search_primers_on_fq(
    primer_seqs = c(TEST = "ACWGGT"),
    fastq_paths = fq_paths[1],
    chunk_size = 1L
  )
  testthat::expect_equal(res_chunked$total_reads, 6)
  testthat::expect_equal(res_chunked$primer_matches, 4)

  # Lower-case primer and lower-case reads match all the same.
  lower_path <- fs::path(fq_dir, "lower.fastq")
  lower_lines <- readLines(fq_paths[1])
  seq_idx <- seq(2L, length(lower_lines), by = 4L)
  lower_lines[seq_idx] <- tolower(lower_lines[seq_idx])
  writeLines(lower_lines, lower_path)
  res_lower <- search_primers_on_fq(
    primer_seqs = c(test = "acwggt"),
    fastq_paths = lower_path
  )
  testthat::expect_equal(res_lower$primer_sequence, "ACWGGT")
  testthat::expect_equal(res_lower$primer_matches, 4)

  # Empty file: zero reads, zero matches, zero percentage.
  empty_path <- fs::path(fq_dir, "empty.fastq")
  fs::file_create(empty_path)
  res_empty <- search_primers_on_fq(c(TEST = "ACGT"), empty_path)
  testthat::expect_equal(res_empty$total_reads, 0)
  testthat::expect_equal(res_empty$primer_matches, 0)
  testthat::expect_equal(res_empty$percentage, 0)
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

  search_primers_on_fq(
    primer_seqs = c(OK = "ACGT"),
    fastq_paths = fq_paths[1],
    chunk_size = 0
  ) |>
    testthat::expect_error(class = "blastr_invalid_argument")

  # Truncated record (not a multiple of 4 lines) is reported, not
  # silently miscounted.
  broken_path <- fs::path(fq_dir, "broken.fastq")
  writeLines(c("@read_1", "ACGT", "+"), broken_path)
  search_primers_on_fq(c(OK = "ACGT"), broken_path) |>
    testthat::expect_error(class = "blastr_fastq_malformed")

  # A quality line starting with `@` is not a header (regression from
  # the grep-based prototype which counted it as a read).
  tricky_path <- fs::path(fq_dir, "tricky.fastq")
  writeLines(c("@read_1", "ACGTACGT", "+", "@IIIIIII"), tricky_path)
  res_tricky <- search_primers_on_fq(c(OK = "ACGT"), tricky_path)
  testthat::expect_equal(res_tricky$total_reads, 1)

  # env_name is deprecated and ignored.
  search_primers_on_fq(
    primer_seqs = c(OK = "ACGT"),
    fastq_paths = fq_paths[1],
    env_name = "blastr-seqkit-env"
  ) |>
    lifecycle::expect_deprecated()
})

testthat::test_that("duplicated primer names are repaired and all searched", {
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

testthat::test_that("packaged toy library gives the documented counts", {
  fastq_path <- fs::path_package("BLASTr", "extdata", "toy_reads.fastq.gz")
  primers <- c(
    `MiFish-U-F` = "GTCGGTAAAACTCGTGCCAGC",
    `mlCOIintF` = "GGWACWGGWTGAACWGTWTAYCCYCC"
  )
  both <- search_primers_on_fq(primers, fastq_path)
  testthat::expect_equal(both$total_reads, c(300, 300))
  testthat::expect_equal(both$primer_matches, c(250, 50))
  testthat::expect_equal(both$percentage, c(250, 50) / 3)
  forward <- search_primers_on_fq(
    primers,
    fastq_path,
    only_positive_strand = TRUE
  )
  testthat::expect_equal(forward$primer_matches, c(150, 50))
})
