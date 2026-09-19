# Package index

## BLAST searches

Run BLAST+ searches for query sequences, in parallel or serially, and
inspect per-query exit codes.

- [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  : Run Parallelized BLAST
- [`get_blast_results()`](https://heronoh.github.io/BLASTr/reference/get_blast_results.md)
  : Get Formatted BLAST Results
- [`run_blast()`](https://heronoh.github.io/BLASTr/reference/run_blast.md)
  : Run BLAST
- [`exit_codes()`](https://heronoh.github.io/BLASTr/reference/exit_codes.md)
  : Retrieve Exit Codes and Standard Error from BLASTr Results

## BLAST databases

Build and query local BLAST databases.

- [`make_blast_db()`](https://heronoh.github.io/BLASTr/reference/make_blast_db.md)
  : Make BLAST Database
- [`get_fasta_header()`](https://heronoh.github.io/BLASTr/reference/get_fasta_header.md)
  : Get Sequence Headers from Subject IDs
- [`parse_fasta()`](https://heronoh.github.io/BLASTr/reference/parse_fasta.md)
  : Parse FASTA File into Sequences

## Taxonomy

Resolve NCBI Taxonomy IDs or organism names into full taxonomic lineages
via the NCBI E-utilities (no command-line tool needed).

- [`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md)
  : Retrieve Taxonomic Ranks for a List of NCBI Taxonomy Tax IDs in
  Parallel
- [`get_tax_by_taxID()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_taxID.md)
  : Retrieve Taxonomic Ranks Using NCBI Taxonomy Tax IDs
- [`get_tax_by_name()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_name.md)
  : Retrieve Taxonomic Ranks Using Organism Names

## Sequence quality control

Primer checks on raw FASTQ reads (pure R, no external tool).

- [`search_primers_on_fq()`](https://heronoh.github.io/BLASTr/reference/search_primers_on_fq.md)
  : Count Primer Occurrences in FASTQ Files

## Setup and utilities

- [`install_dependencies()`](https://heronoh.github.io/BLASTr/reference/install_dependencies.md)
  : Install Required Command-line Tool Dependencies
- [`get_blastr_cache()`](https://heronoh.github.io/BLASTr/reference/get_blastr_cache.md)
  : Retrieve System-Dependent Cache Path for BLASTr
