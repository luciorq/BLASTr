#' Count Primer Occurrences in FASTQ Files
#'
#' Searches (possibly degenerate) primer sequences in FASTQ files and
#' reports, for each file/primer combination, the number and percentage
#' of reads containing the primer. This is a quick quality-control step
#' for amplicon libraries: it tells you whether the reads really carry
#' the primers you expect, and on which strand.
#'
#' The implementation is pure R: files are streamed in chunks of
#' `chunk_size` reads (plain or gzip-compressed, any operating system),
#' IUPAC degenerate bases in the primers are expanded into character
#' classes, and matching is case-insensitive. By default both strands are
#' searched, i.e. a read matches when it contains the primer or its
#' reverse complement; set `only_positive_strand = TRUE` to restrict
#' matching to the forward strand.
#'
#' Throughput is roughly one million 250-base reads per 15 seconds for two
#' primers on both strands (single core; gzip input adds little), so
#' typical amplicon libraries are checked in seconds to a few minutes.
#'
#' @param primer_seqs Named character vector of primer sequences (IUPAC
#'   degenerate bases allowed). Names are used as primer identifiers;
#'   unnamed primers are labeled `primer_<i>`.
#' @param fastq_paths Character vector of paths to FASTQ files
#'   (optionally gzip-compressed).
#' @param only_positive_strand Logical, search only the forward strand.
#'   Defaults to `FALSE` (both strands).
#' @param chunk_size Number of reads held in memory at a time while
#'   streaming each file. Defaults to `100000`.
#' @param verbose Verbosity level. One of `"silent"` (default), `"cmd"`,
#'   `"output"`, or `"full"`. Levels other than `"silent"` report the
#'   per-file counts as they are computed.
#' @param env_name `r lifecycle::badge("deprecated")` No longer used: the
#'   search runs in R and needs no external tool.
#'
#' @inheritParams rlang::args_dots_empty
#'
#' @returns A tibble with one row per file/primer combination and columns
#'   `file_name`, `primer_name`, `primer_sequence`, `parsed_primer` (the
#'   regular expression the primer expands to), `total_reads`,
#'   `primer_matches`, and `percentage`.
#'
#' @examples
#' # Toy amplicon library shipped with the package: 300 reads of which
#' # 150 carry the MiFish-U forward primer on the forward strand, 100 on
#' # the reverse strand, and 50 carry a COI primer (degenerate bases).
#' fastq_path <- fs::path_package("BLASTr", "extdata", "toy_reads.fastq.gz")
#'
#' primers <- c(
#'   `MiFish-U-F` = "GTCGGTAAAACTCGTGCCAGC",
#'   `mlCOIintF` = "GGWACWGGWTGAACWGTWTAYCCYCC"
#' )
#'
#' # Both strands (default)
#' search_primers_on_fq(primer_seqs = primers, fastq_paths = fastq_path)
#'
#' # Forward strand only: the 100 reverse-strand reads no longer count
#' search_primers_on_fq(
#'   primer_seqs = primers,
#'   fastq_paths = fastq_path,
#'   only_positive_strand = TRUE
#' )
#'
#' @export
search_primers_on_fq <- function(
  primer_seqs,
  fastq_paths,
  ...,
  only_positive_strand = FALSE,
  chunk_size = 100000L,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = deprecated()
) {
  rlang::check_dots_empty()
  rlang::check_required(primer_seqs)
  rlang::check_required(fastq_paths)
  verbose <- rlang::arg_match(verbose)
  if (isTRUE(lifecycle::is_present(env_name))) {
    lifecycle::deprecate_warn(
      when = "0.2.0",
      what = "search_primers_on_fq(env_name)",
      details = "Primer search now runs in R; no conda environment is needed." # nolint: line_length_linter
    )
  }
  if (
    isFALSE(rlang::is_scalar_integerish(chunk_size)) || isFALSE(chunk_size >= 1)
  ) {
    cli::cli_abort(
      message = c(`x` = "{.arg chunk_size} must be a single positive integer."),
      class = "blastr_invalid_argument"
    )
  }

  primer_seqs <- toupper(
    as.character(primer_seqs) |>
      rlang::set_names(names(primer_seqs))
  )
  if (rlang::is_null(names(primer_seqs))) {
    names(primer_seqs) <- paste0("primer_", seq_along(primer_seqs))
  }
  empty_names_lgl <- !nzchar(names(primer_seqs))
  names(primer_seqs)[empty_names_lgl] <- paste0(
    "primer_",
    seq_along(primer_seqs)
  )[empty_names_lgl]
  if (isTRUE(anyDuplicated(names(primer_seqs)) > 0L)) {
    cli::cli_warn(
      "Duplicated primer names found; renaming with {.fun make.unique} so every primer is searched." # nolint: line_length_linter
    )
    names(primer_seqs) <- make.unique(names(primer_seqs), sep = "_")
  }

  invalid_primers_lgl <- !stringr::str_detect(
    primer_seqs,
    "^[ACGTUWSMKRYBDHVN]+$"
  )
  if (isTRUE(any(invalid_primers_lgl))) {
    cli::cli_abort(
      message = c(
        `x` = "Primer{?s} {.val {names(primer_seqs)[invalid_primers_lgl]}} contain{?s/} non-IUPAC characters." # nolint: line_length_linter
      ),
      class = "blastr_invalid_primer_error"
    )
  }

  missing_files_lgl <- !fs::file_exists(fastq_paths)
  if (isTRUE(any(missing_files_lgl))) {
    cli::cli_abort(
      message = c(
        `x` = "FASTQ file{?s} not found: {.file {fastq_paths[missing_files_lgl]}}." # nolint: line_length_linter
      ),
      class = "blastr_fastq_file_not_readable"
    )
  }

  # One regex per primer (and one for its reverse complement).
  forward_patterns <- purrr::map_chr(primer_seqs, primer_to_regex)
  reverse_patterns <- purrr::map_chr(
    primer_seqs,
    \(primer) primer_to_regex(reverse_complement_iupac(primer))
  )

  results_list <- list()
  for (fastq_path in fastq_paths) {
    counts <- count_primer_matches_in_fastq(
      fastq_path = fastq_path,
      forward_patterns = forward_patterns,
      reverse_patterns = if (isTRUE(only_positive_strand)) {
        NULL
      } else {
        reverse_patterns
      },
      chunk_size = chunk_size
    )
    total_reads <- counts$total_reads
    percentage <- rep(0, length(primer_seqs))
    if (isTRUE(total_reads > 0)) {
      percentage <- (counts$primer_matches / total_reads) * 100
    }
    if (isFALSE(identical(verbose, "silent"))) {
      cli::cli_inform(
        c(
          `v` = "{.file {fastq_path}}: {total_reads} read{?s}; matches: {paste0(names(primer_seqs), '=', counts$primer_matches, collapse = ', ')}." # nolint: line_length_linter
        )
      )
    }
    results_list <- c(
      results_list,
      list(
        tibble::tibble(
          file_name = fastq_path,
          primer_name = names(primer_seqs),
          primer_sequence = unname(primer_seqs),
          parsed_primer = unname(forward_patterns),
          total_reads = total_reads,
          primer_matches = unname(counts$primer_matches),
          percentage = unname(percentage)
        )
      )
    )
  }

  return(purrr::list_rbind(results_list))
}

# IUPAC nucleotide codes -> regex character classes / complements.
iupac_regex_map <- c(
  A = "A",
  C = "C",
  G = "G",
  T = "T",
  U = "T",
  W = "[AT]",
  S = "[CG]",
  M = "[AC]",
  K = "[GT]",
  R = "[AG]",
  Y = "[CT]",
  B = "[CGT]",
  D = "[AGT]",
  H = "[ACT]",
  V = "[ACG]",
  N = "[ACGT]"
)

iupac_complement_map <- c(
  A = "T",
  C = "G",
  G = "C",
  T = "A",
  U = "A",
  W = "W",
  S = "S",
  M = "K",
  K = "M",
  R = "Y",
  Y = "R",
  B = "V",
  V = "B",
  D = "H",
  H = "D",
  N = "N"
)

#' Expand an IUPAC primer into a regular expression
#' @keywords internal
#' @noRd
primer_to_regex <- function(primer) {
  bases <- strsplit(toupper(primer), "", fixed = TRUE)[[1]]
  paste(iupac_regex_map[bases], collapse = "")
}

#' Reverse complement of an IUPAC (degenerate) sequence
#' @keywords internal
#' @noRd
reverse_complement_iupac <- function(primer) {
  bases <- strsplit(toupper(primer), "", fixed = TRUE)[[1]]
  paste(rev(iupac_complement_map[bases]), collapse = "")
}

#' Stream a FASTQ file and count reads matching each primer
#'
#' @param forward_patterns Named character vector of regexes.
#' @param reverse_patterns Same names as `forward_patterns`, or `NULL`
#'   to search the forward strand only.
#' @returns `list(total_reads, primer_matches)`; `primer_matches` is a
#'   named numeric vector aligned with `forward_patterns`.
#' @keywords internal
#' @noRd
count_primer_matches_in_fastq <- function(
  fastq_path,
  forward_patterns,
  reverse_patterns = NULL,
  chunk_size = 100000L
) {
  # `gzfile()` transparently reads both gzip-compressed and plain files.
  con <- gzfile(fastq_path, open = "rt")
  withr::defer(close(con))

  total_reads <- 0
  primer_matches <- rlang::set_names(
    rep(0, length(forward_patterns)),
    names(forward_patterns)
  )
  n_lines <- 4L * as.integer(chunk_size)

  repeat {
    lines <- readLines(con, n = n_lines, warn = FALSE)
    if (isTRUE(length(lines) == 0L)) {
      break
    }
    header_idx <- seq.int(1L, length(lines), by = 4L)
    if (
      isFALSE(length(lines) %% 4L == 0L) ||
        isFALSE(all(startsWith(lines[header_idx], "@")))
    ) {
      cli::cli_abort(
        message = c(
          `x` = "{.file {fastq_path}} is not a valid FASTQ file (records must be 4 lines starting with {.code @})." # nolint: line_length_linter
        ),
        class = "blastr_fastq_malformed"
      )
    }
    seqs <- lines[header_idx + 1L]
    total_reads <- total_reads + length(seqs)
    for (primer_i in seq_along(forward_patterns)) {
      hits <- grepl(
        forward_patterns[[primer_i]],
        seqs,
        ignore.case = TRUE,
        perl = TRUE
      )
      if (!rlang::is_null(reverse_patterns)) {
        hits <- hits |
          grepl(
            reverse_patterns[[primer_i]],
            seqs,
            ignore.case = TRUE,
            perl = TRUE
          )
      }
      primer_matches[[primer_i]] <- primer_matches[[primer_i]] + sum(hits)
    }
  }

  list(total_reads = total_reads, primer_matches = primer_matches)
}
