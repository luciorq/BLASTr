# Parse FASTA File into Sequences

Extract the sequences from a FASTA file, dropping headers and joining
multi-line records.

## Usage

``` r
parse_fasta(file_path)
```

## Arguments

- file_path:

  Path to the FASTA file.

## Value

A character vector containing the sequences.

## Examples

``` r
fasta_path <- fs::path_package("BLASTr", "extdata", "minimal_db_blast", ext = "fasta")
seqs <- parse_fasta(file_path = fasta_path)
```
