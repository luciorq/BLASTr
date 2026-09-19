# Retrieve Exit Codes and Standard Error from BLASTr Results

This function extracts the per-query exit codes and standard error
messages from the results of a BLAST search performed with
[`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
or
[`get_blast_results()`](https://heronoh.github.io/BLASTr/reference/get_blast_results.md)
(stored in the `BLASTr_metadata` attribute of the returned tibble).

## Usage

``` r
exit_codes(blast_res)
```

## Arguments

- blast_res:

  A tibble returned by
  [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  or
  [`get_blast_results()`](https://heronoh.github.io/BLASTr/reference/get_blast_results.md).

## Value

A tibble with columns `query_seq`, `exit_code`, and `stderr`.
`exit_code` is `0` for successful queries, the BLAST+ exit status for
tool failures, or `-1` when the R-level parallel worker itself failed
(e.g. a crashed daemon). `stderr` holds the full standard error output
of the BLAST+ invocation that produced the query's result - including
non-fatal per-query warnings such as `"Sequence contains no data"` - or
`NA` when the run produced no diagnostic output.

## Examples

``` r
if (FALSE) { # \dontrun{
blast_res <- parallel_blast(
  query_seqs = "CTAGCCATAAACTTAAATGAAGCTATACTAA",
  db_path = "path/to/blast_db"
)
exit_codes(blast_res)
} # }
```
