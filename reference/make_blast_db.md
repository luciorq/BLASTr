# Make BLAST Database

Create a BLAST database from a FASTA file.

## Usage

``` r
make_blast_db(
  fasta_path,
  db_path = NULL,
  db_type = "nucl",
  taxid_map = NULL,
  parse_seqids = TRUE,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = "blastr-blast-env"
)
```

## Arguments

- fasta_path:

  Path to the input FASTA file.

- db_path:

  Path prefix for the output BLAST database files. Defaults to `NULL`,
  which creates the database alongside the input FASTA file (BLAST+
  `makeblastdb` default). Provide a path in a writable directory when
  the FASTA file lives in a read-only location (e.g. an installed
  package directory).

- db_type:

  Type of database to create, either `"nucl"` or `"prot"`.

- taxid_map:

  Optional path to a file mapping sequence IDs to NCBI Taxonomy IDs,
  passed to `makeblastdb -taxid_map`. The file must have one
  `<SequenceId> <TaxonomyId>` pair per line. Requires
  `parse_seqids = TRUE`.

- parse_seqids:

  Whether to parse sequence IDs (`-parse_seqids`).

- verbose:

  Verbosity level. One of `"silent"` (default), `"cmd"`, `"output"`, or
  `"full"`.

- env_name:

  Name of the conda environment used to run the command-line tools.
  Defaults to `"blastr-blast-env"`.

## Value

Invisibly returns the result of the `makeblastdb` command.

## Examples

``` r
if (FALSE) { # \dontrun{
make_blast_db(
  fasta_path = fs::path_package(
    "BLASTr", "extdata", "minimal_db_blast",
    ext = "fasta"
  ),
  db_path = fs::path_temp("minimal_db_blast"),
  db_type = "nucl"
)
} # }
```
