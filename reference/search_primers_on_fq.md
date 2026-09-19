# Count Primer Occurrences in FASTQ Files

Searches (possibly degenerate) primer sequences in FASTQ files and
reports, for each file/primer combination, the number and percentage of
reads containing the primer. This is a quick quality-control step for
amplicon libraries: it tells you whether the reads really carry the
primers you expect, and on which strand.

## Usage

``` r
search_primers_on_fq(
  primer_seqs,
  fastq_paths,
  ...,
  only_positive_strand = FALSE,
  chunk_size = 100000L,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = deprecated()
)
```

## Arguments

- primer_seqs:

  Named character vector of primer sequences (IUPAC degenerate bases
  allowed). Names are used as primer identifiers; unnamed primers are
  labeled `primer_<i>`.

- fastq_paths:

  Character vector of paths to FASTQ files (optionally gzip-compressed).

- ...:

  These dots are for future extensions and must be empty.

- only_positive_strand:

  Logical, search only the forward strand. Defaults to `FALSE` (both
  strands).

- chunk_size:

  Number of reads held in memory at a time while streaming each file.
  Defaults to `100000`.

- verbose:

  Verbosity level. One of `"silent"` (default), `"cmd"`, `"output"`, or
  `"full"`. Levels other than `"silent"` report the per-file counts as
  they are computed.

- env_name:

  **\[deprecated\]** No longer used: the search runs in R and needs no
  external tool.

## Value

A tibble with one row per file/primer combination and columns
`file_name`, `primer_name`, `primer_sequence`, `parsed_primer` (the
regular expression the primer expands to), `total_reads`,
`primer_matches`, and `percentage`.

## Details

The implementation is pure R: files are streamed in chunks of
`chunk_size` reads (plain or gzip-compressed, any operating system),
IUPAC degenerate bases in the primers are expanded into character
classes, and matching is case-insensitive. By default both strands are
searched, i.e. a read matches when it contains the primer or its reverse
complement; set `only_positive_strand = TRUE` to restrict matching to
the forward strand.

Throughput is roughly one million 250-base reads per 15 seconds for two
primers on both strands (single core; gzip input adds little), so
typical amplicon libraries are checked in seconds to a few minutes.

## Examples

``` r
# Toy amplicon library shipped with the package: 300 reads of which
# 150 carry the MiFish-U forward primer on the forward strand, 100 on
# the reverse strand, and 50 carry a COI primer (degenerate bases).
fastq_path <- fs::path_package("BLASTr", "extdata", "toy_reads.fastq.gz")

primers <- c(
  `MiFish-U-F` = "GTCGGTAAAACTCGTGCCAGC",
  `mlCOIintF` = "GGWACWGGWTGAACWGTWTAYCCYCC"
)

# Both strands (default)
search_primers_on_fq(primer_seqs = primers, fastq_paths = fastq_path)
#> # A tibble: 2 × 7
#>   file_name primer_name primer_sequence parsed_primer total_reads primer_matches
#>   <chr>     <chr>       <chr>           <chr>               <dbl>          <dbl>
#> 1 /home/ru… MiFish-U-F  GTCGGTAAAACTCG… GTCGGTAAAACT…         300            250
#> 2 /home/ru… mlCOIintF   GGWACWGGWTGAAC… GG[AT]AC[AT]…         300             50
#> # ℹ 1 more variable: percentage <dbl>

# Forward strand only: the 100 reverse-strand reads no longer count
search_primers_on_fq(
  primer_seqs = primers,
  fastq_paths = fastq_path,
  only_positive_strand = TRUE
)
#> # A tibble: 2 × 7
#>   file_name primer_name primer_sequence parsed_primer total_reads primer_matches
#>   <chr>     <chr>       <chr>           <chr>               <dbl>          <dbl>
#> 1 /home/ru… MiFish-U-F  GTCGGTAAAACTCG… GTCGGTAAAACT…         300            150
#> 2 /home/ru… mlCOIintF   GGWACWGGWTGAAC… GG[AT]AC[AT]…         300             50
#> # ℹ 1 more variable: percentage <dbl>
```
