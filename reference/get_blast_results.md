# Get Formatted BLAST Results

Retrieve BLAST results as a tibble for one or more query sequences,
running serially in the current process. For parallel execution over
many sequences, use
[`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md) -
both functions share the same engine and return the same format.

## Usage

``` r
get_blast_results(
  query_seqs,
  db_path,
  num_threads = 1L,
  blast_type = "blastn",
  perc_id = 80L,
  perc_qcov_hsp = 80L,
  num_alignments = 4L,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = "blastr-blast-env"
)
```

## Arguments

- query_seqs:

  Character vector with sequences to be searched.

- db_path:

  Path to the formatted BLAST database.

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

- num_alignments:

  Number of alignments to retrieve for each query sequence. Passed on to
  BLAST+ `-num_alignments`. Defaults to `4`.

- verbose:

  Verbosity level. One of `"silent"` (default), `"cmd"`, `"output"`, or
  `"full"`.

- env_name:

  Name of the conda environment used to run the command-line tools.
  Defaults to `"blastr-blast-env"`.

## Value

A `tibble` with one row per unique query sequence and the BLAST tabular
output spread into `1_`-`<num_alignments>_` prefixed column groups.

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

get_blast_results(query_seqs = query_seqs_string, db_path = temp_db_path)
} # }
```
