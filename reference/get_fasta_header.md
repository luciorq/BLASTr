# Get Sequence Headers from Subject IDs

Retrieve the complete sequence titles stored in a BLAST database for one
or more subject IDs.

## Usage

``` r
get_fasta_header(
  id,
  db_path,
  env_name = "blastr-blast-env",
  verbose = c("silent", "cmd", "output", "full")
)
```

## Arguments

- id:

  One or more SubjectIDs from BLAST results (any identifier present in
  the database). Multiple IDs are fetched in a single `blastdbcmd` call.

- db_path:

  Path to the formatted BLAST database.

- env_name:

  Name of the conda environment used to run the command-line tools.
  Defaults to `"blastr-blast-env"`.

- verbose:

  Verbosity level. One of `"silent"` (default), `"cmd"`, `"output"`, or
  `"full"`.

## Value

Character vector with the complete title for each SubjectID as stored in
the database.

## Examples

``` r
if (FALSE) { # \dontrun{
dna_fasta_path <- fs::path_package(
  "BLASTr", "extdata", "minimal_db_blast",
  ext = "fasta"
)
temp_db_path <- fs::path_temp("minimal_db_blast")
make_blast_db(fasta_path = dna_fasta_path, db_path = temp_db_path)
get_fasta_header(id = "AP011979.1", db_path = temp_db_path)
} # }
```
