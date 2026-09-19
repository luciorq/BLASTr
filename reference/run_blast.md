# Run BLAST

Run BLAST for one or more sequences and return the raw process results.
For results formatted as a tibble, use
[`get_blast_results()`](https://heronoh.github.io/BLASTr/reference/get_blast_results.md)
or
[`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md).

Each sequence is written as its own FASTA record (with generated
`BLASTrQ<i>` headers), so multiple sequences are searched as separate
queries in a single BLAST+ invocation.

## Usage

``` r
run_blast(
  query_seqs,
  db_path,
  num_alignments = 4L,
  num_threads = 1L,
  blast_type = "blastn",
  perc_id = 80L,
  perc_qcov_hsp = 80L,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = "blastr-blast-env"
)
```

## Arguments

- query_seqs:

  Character vector with sequences to be searched.

- db_path:

  Path to the formatted BLAST database.

- num_alignments:

  Number of alignments to retrieve for each query sequence. Passed on to
  BLAST+ `-num_alignments`. Defaults to `4`.

- num_threads:

  Number of threads to run BLAST on. Passed on to BLAST+ argument
  `-num_threads`.

- blast_type:

  BLAST+ executable to be used on search. One of:
  `c("blastn", "blastp", "blastx", "tblastn", "tblastx")`.

- perc_id:

  Lowest identity percentage cutoff. Passed on to BLAST+
  `-perc_identity`.

- perc_qcov_hsp:

  Lowest query coverage per HSP percentage cutoff. Passed on to BLAST+
  `-qcov_hsp_perc`.

- verbose:

  Verbosity level. One of `"silent"` (default), `"cmd"`, `"output"`, or
  `"full"`.

- env_name:

  Name of the conda environment used to run the command-line tools.
  Defaults to `"blastr-blast-env"`.

## Value

Unformatted BLAST results (the raw process result, with `status`,
`stdout`, and `stderr`). `stdout` is BLAST+ tabular output in format
`"6 std qcovhsp staxid stitle"` - 15 tab-separated fields: the 12
standard outfmt-6 columns followed by `qcovhsp`, `staxid`, and `stitle`
(subject title), with query IDs in the generated `BLASTrQ<i>` form.
(Before version 0.2.0, the output had 14 fields and no `stitle`.) For
results formatted as a tibble, please use
[`get_blast_results()`](https://heronoh.github.io/BLASTr/reference/get_blast_results.md).

## Examples

``` r
if (FALSE) { # \dontrun{

dna_fasta_path <- fs::path_package(
  "BLASTr", "extdata", "minimal_db_blast",
  ext = "fasta"
)
temp_db_path <- fs::path_temp("minimal_db_blast")
make_blast_db(fasta_path = dna_fasta_path, db_path = temp_db_path)
query_seqs_string <- "CTAGCCATAAACTTAAATGAAGCTATACTAAACTCGTTCGCCAG
AGTACTACAAGCGAAAGCTTAAAACTCATAGGACTTGGCGGTGTTTCAGACCCAC"
blast_res <- run_blast(
  query_seqs = query_seqs_string,
  db_path = temp_db_path
)
} # }
```
