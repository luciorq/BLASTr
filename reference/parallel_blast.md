# Run Parallelized BLAST

Run parallel BLAST for a set of sequences.

Unique query sequences are batched into multi-record FASTA chunks so
that each BLAST+ process handles many queries at once (amortizing
process startup and database loading), and chunks are dispatched to
[`mirai::daemons()`](https://mirai.r-lib.org/reference/daemons.html)
with
[`mirai::mirai_map()`](https://mirai.r-lib.org/reference/mirai_map.html).
When the `mori` package is installed, the query set is placed in shared
memory ([`mori::share()`](https://rdrr.io/pkg/mori/man/share.html)) so
parallel workers receive a zero-copy reference instead of a full copy of
the sequences.

If a chunk fails (non-zero BLAST exit status), its member sequences are
automatically re-run individually to rescue healthy queries and
attribute the error to the offending ones, which are then retried up to
`retry_times` times. Per-query BLAST warnings (e.g. empty or malformed
records inside an otherwise successful batch) are captured and exposed
through
[`exit_codes()`](https://heronoh.github.io/BLASTr/reference/exit_codes.md).

## Usage

``` r
parallel_blast(
  query_seqs,
  db_path,
  ...,
  total_cores = 1L,
  num_threads = 1L,
  blast_type = "blastn",
  perc_id = 80L,
  perc_qcov_hsp = 80L,
  num_alignments = 4L,
  retry_times = 3L,
  mt_mode = c("2", "1", "0"),
  chunk_size = NULL,
  verbose = c("progress", "silent", "cmd", "output", "full"),
  env_name = "blastr-blast-env",
  asvs = deprecated(),
  out_file = deprecated(),
  out_RDS = deprecated()
)
```

## Arguments

- query_seqs:

  Character vector with sequences to be searched.

- db_path:

  Path to the formatted BLAST database.

- ...:

  These dots are for future extensions and must be empty.

- total_cores:

  Number of parallel BLAST processes to run. If
  [`mirai::daemons()`](https://mirai.r-lib.org/reference/daemons.html)
  are already set for the session, the existing pool is used as-is and
  this argument only influences chunking.

- num_threads:

  Number of threads/cores to run each BLAST process on. Passed on to
  BLAST+ `-num_threads`. Note that the effective maximum CPU usage is
  `total_cores * num_threads`.

- blast_type:

  BLAST+ executable to be used on search. One of:
  `c("blastn", "blastp", "blastx", "tblastn", "tblastx")`.

- perc_id:

  Lowest identity percentage cutoff. Passed on to BLAST+
  `-perc_identity`.

- perc_qcov_hsp:

  Lowest query coverage per HSP percentage cutoff. Passed on to BLAST+
  `-qcov_hsp_perc`.

- num_alignments:

  Number of alignments to retrieve for each query sequence. Passed on to
  BLAST+ `-num_alignments`. Defaults to `4`.

- retry_times:

  Number of times to retry failed BLAST jobs. Defaults to `3` attempts.

- mt_mode:

  Multithreading mode to be used by BLAST+. One of: `c("2", "1", "0")`.
  See BLAST+ manual for details.

- chunk_size:

  Number of query sequences per BLAST+ invocation. Defaults to `NULL`,
  which targets about four chunks per core (capped at 500 sequences per
  chunk).

- verbose:

  Verbosity level. One of `"progress"` (default), `"silent"`, `"cmd"`,
  `"output"`, or `"full"`. `"progress"` shows a progress bar in
  interactive sessions and is otherwise equivalent to `"silent"`; the
  remaining levels are passed on to the underlying command execution.

- env_name:

  Name of the conda environment used to run the command-line tools.
  Defaults to `"blastr-blast-env"`.

- asvs:

  Deprecated. Same as `query_seqs`. Use `query_seqs` instead.

- out_file:

  Deprecated. Path to output `.csv` file on an existing directory.

- out_RDS:

  Deprecated. Path to output `RDS` file on an existing directory.

## Value

A tibble with one row per unique query sequence and the BLAST tabular
output spread into `1_`-`<num_alignments>_` prefixed column groups.
Per-query exit codes and error messages are stored in the
`BLASTr_metadata` attribute (see
[`exit_codes()`](https://heronoh.github.io/BLASTr/reference/exit_codes.md)).

## Examples

``` r
if (FALSE) { # \dontrun{
dna_fasta_path <- fs::path_package(
  "BLASTr", "extdata", "minimal_db_blast",
  ext = "fasta"
)
temp_db_path <- fs::path_temp("minimal_db_blast")
make_blast_db(fasta_path = dna_fasta_path, db_path = temp_db_path)
query_seqs_string <- c(
  "CTAGCCATAAACTTAAATGAAGCTATACTAA",
  "ACTCGTTCGCCAGAGTACTACAAGCGAAAG"
)
blast_res <- parallel_blast(
  query_seqs = query_seqs_string,
  db_path = temp_db_path
)
blast_res
} # }
```
