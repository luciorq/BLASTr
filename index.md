# BLASTr: Parallel Taxonomic Classification of Metabarcoding Sequences

## Overview

`BLASTr` is an R package that seamlessly integrates BLAST+ searches into
your R workflow. It is specifically designed for the analysis of
Amplicon Sequence Variants (ASVs) from metabarcoding and metagenomic
studies. With `BLASTr`, you can efficiently perform taxonomic
classification of your sequences by leveraging the power of parallel
processing and automated dependency management.

## Features

- **Batched, Parallel BLAST Searches:** Query sequences are grouped into
  multi-record FASTA batches (amortizing BLAST+ startup and database
  loading) and batches run concurrently on
  [`mirai`](https://mirai.r-lib.org/) daemons. With the optional
  [`mori`](https://cran.r-project.org/package=mori) package installed,
  workers read the query set from shared memory with zero copying.
- **Resilient Execution:** Failed batches are automatically salvaged
  (healthy queries keep their results), failing queries are retried, and
  per-query exit codes and error messages are available via
  [`exit_codes()`](https://heronoh.github.io/BLASTr/reference/exit_codes.md).
- **Automated Dependency Management:** `BLASTr` automatically installs
  and manages BLAST+ using `condathis`, ensuring a hassle-free setup.
  Taxonomy lookups and primer checks need no external tool.
- **Taxonomic Classification:** Retrieve detailed taxonomic information
  for your sequences using their NCBI Taxonomy IDs (batched NCBI
  E-utilities requests, no command-line tool needed), or search taxa by
  name.
- **Reproducible Research:** By managing dependencies in isolated Conda
  environments (with pinned versions), `BLASTr` helps ensure that your
  analyses are reproducible.

## Installation

You can install the development version of `BLASTr` from GitHub with:

``` r

# install.packages("devtools")
devtools::install_github("heronoh/BLASTr")
```

## Basic Usage

Here’s a simple example of how to use `BLASTr` to perform a BLAST search
and retrieve taxonomic information:

## Obtain NCBI databases

To obtain complete NCBI BLAST formatted databases, proceed as follows

``` bash
#suggestion: use screen or tmux to emulate a terminal. The downloads usually takes long.
#          tmux: https://tmuxcheatsheet.com/
#          screen: https://kapeli.com/cheat_sheets/screen.docset/Contents/Resources/Documents/index

# download volumes and md5 check files 
seq -w 000 150 | parallel wget https://ftp.ncbi.nlm.nih.gov/blast/db/nt.{}.tar.gz -t 0 --show-progress;
seq -w 000 150 | parallel wget https://ftp.ncbi.nlm.nih.gov/blast/db/nt.{}.tar.gz.md5 -t 0 --show-progress;
wget https://ftp.ncbi.nlm.nih.gov/blast/db/taxdb.tar.gz -t 0 --show-progress;
wget https://ftp.ncbi.nlm.nih.gov/blast/db/taxdb.tar.gz.md5 -t 0 --show-progress;
wget https://ftp.ncbi.nlm.nih.gov/blast/db/taxdb-metadata.json -t 0 --show-progress;
     # where 000 is the first volume and 150, the last (up to now).
     
ls *5 | parallel md5sum -c {} >> check.txt
sort check.txt > check_sort.txt

ls *tar.gz | parallel tar -xvzf {} 



  
```

## Making local custom databases

You can turn any *.fasta* file with unique headers into a BLAST+
formatted database using the
[`make_blast_db()`](https://heronoh.github.io/BLASTr/reference/make_blast_db.md)
function. Optionally, provide a `taxid_map` file mapping each sequence
identifier to an NCBI Taxonomy ID (one `<SequenceId> <TaxonomyId>` pair
per line, passed to `makeblastdb -taxid_map`), so that BLAST results
include the subject Tax ID (`staxid`).

If you want to retrieve the *subject Scientific name* in the results,
you can download and extract the *taxdb* files from NCBI, as mentioned
above, and point the `BLASTDB` environment variable to the directory
containing them.

``` r

library(BLASTr)

# First, make sure you have the necessary dependencies installed
install_dependencies()

# A vector of ASV sequences
asvs <- c(
  "CTAGCCATAAACTTAAATGAAGCTATACTAAACTCGTTCGCCAGAGTACTACAAGCGAAAGCTTAAAACTCATAGGACTTGGCGGTGTTTCAGACCCAC",
  "CTAGCCATAAACTTAAATGAAGCTATACTAAACTCGTTCGCCAGAGTACTACAAGTGAAAGCTTAAAACTCATAGGACTTGGCGGTGTTTCAGACCCAC",
  "GCCAAATTTGTGTTTTGTCCTTCGTTTTTAGTTAATTGTTACTGGCAAATGACTAACGACAAATGATAAATTACTAATAC",
  "AACATTGTATTTTGTCTTTGGGGCCTGGGCAGGTGCAGTAGGAACTTCACTTAGAATAATTATTCGTACTGAGCTTGGGCATCCAGGAAGACTTATCGGGGATGATCAAATCTATAATGTAATTGTTACAGCACATGCATTTGTGATAATTTTTTTTATAGTAATACCTATTATGATT",
  "ACTATACCTATTATTCGGCGCATGAGCTGGAGTCCTAGGCACAGCTCTAAGCCTCCTTATTCGAGCCGAGCTGGGCCAGCCAGGCAACCTTCTAGGTAACGACCACATCTACAACGTTATCGTCACAGCCCATGCATTTGTAATAATCTTCTTCATAGTAATACCCATCATAATCGGAGGCTTTGGCAACTGACTAGTTCCCCTAATAATCGGTGCCCCCGATATG",
  "TTAGCCATAAACATAAAAGTTCACATAACAAGAACTTTTGCCCGAGAACTACTAGCAACAGCTTAAAACTCAAAGGACTTGGCGGTGCTTTATATCCAC"
)

# Path to your local FASTA file
fasta_path <- fs::path_package("BLASTr", "extdata", "minimal_db_blast", ext = "fasta")
# Optional: taxid map with one "<SequenceId> <TaxonomyId>" pair per line,
# so BLAST results include the subject Tax ID (staxid)
taxid_map <- fs::path_package("BLASTr", "extdata", "minimal_db_blast", ext = "txt")
# Path prefix for the database to be created
db_path <- fs::path_temp("minimal_db_blast")

make_blast_db(
  fasta_path = fasta_path,
  db_path = db_path,
  db_type = "nucl",
  taxid_map = taxid_map
)

file.exists(paste0(db_path, ".ndb"))
```

``` r

# Run BLAST in parallel
blast_results <- parallel_blast(
  query_seqs = asvs,
  db_path = db_path,
  total_cores = 2 # Number of BLAST processes to use
)

blast_results
```

BLASTr keeps track of any errors that may occur during the BLAST
searches. You can retrieve the exit codes and STDERR messages using the
[`exit_codes()`](https://heronoh.github.io/BLASTr/reference/exit_codes.md)
function.

``` r

# Check for any errors during BLAST searches
exit_code_df <- exit_codes(blast_results)
print(exit_code_df[c("exit_code", "stderr")])
```

``` r

# Extract the taxonomy IDs from the top BLAST hit for each query sequence.
tax_ids <- blast_results$`1_staxid`

# Retrieve taxonomic information in parallel
taxonomic_info <- parallel_get_tax(
  organisms_taxIDs = tax_ids,
  total_cores = 2,
  retry_times = 0
)

print(taxonomic_info)
```

## Main Functions

- [`install_dependencies()`](https://heronoh.github.io/BLASTr/reference/install_dependencies.md):
  Installs BLAST+ if it is not found on your system.
- [`make_blast_db()`](https://heronoh.github.io/BLASTr/reference/make_blast_db.md):
  Creates a BLAST database from a FASTA file.
- [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md):
  Runs BLAST searches for multiple sequences in parallel (batched).
- [`exit_codes()`](https://heronoh.github.io/BLASTr/reference/exit_codes.md):
  Retrieve the exit codes and STDERR messages from BLAST searches.
- [`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md):
  Retrieves taxonomic information for multiple NCBI Taxonomy IDs in
  parallel (batched).
- [`get_tax_by_taxID()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_taxID.md):
  Retrieves taxonomic ranks for NCBI Taxonomy IDs.
- [`get_tax_by_name()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_name.md):
  Searches NCBI Taxonomy by organism name and retrieves taxonomic ranks.
- [`get_blast_results()`](https://heronoh.github.io/BLASTr/reference/get_blast_results.md):
  Runs BLAST serially and returns the same formatted tibble as
  [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md).
- [`run_blast()`](https://heronoh.github.io/BLASTr/reference/run_blast.md):
  A lower-level function to run a BLAST search and return the raw
  output.
- [`parse_fasta()`](https://heronoh.github.io/BLASTr/reference/parse_fasta.md):
  Extracts sequences from a FASTA file.
- [`get_fasta_header()`](https://heronoh.github.io/BLASTr/reference/get_fasta_header.md):
  Retrieves the full header of a sequence from a BLAST database.
- [`search_primers_on_fq()`](https://heronoh.github.io/BLASTr/reference/search_primers_on_fq.md):
  Counts reads carrying each (degenerate) primer in FASTQ files, a quick
  library QC that runs in R.

## Dependency Management

`BLASTr` uses the `condathis` package to manage its only command-line
dependency, BLAST+. NCBI Taxonomy lookups query the NCBI E-utilities
directly over HTTPS, and primer checks on FASTQ files run in R, so
neither needs a tool. When you run a function that requires one of these
tools, `BLASTr` will automatically check if it’s installed. If not, it
will create a Conda environment and install the necessary software (with
pinned versions for reproducibility). This ensures that you always have
the correct versions of the dependencies without having to install them
manually.

You can control the installation process with the `force` and `verbose`
arguments in the
[`install_dependencies()`](https://heronoh.github.io/BLASTr/reference/install_dependencies.md)
function (`force = TRUE` also serves as the upgrade path).

BLAST+ is installed from the `blast` package on the [prefix.dev universe
channel](https://prefix.dev/universe), which is built uniformly for
Linux, macOS, and Windows, so the whole package works on all three.

Advanced: the conda package specifications can be overridden per tool
family, e.g. `options(blastr.conda.blast = "<package>==<version>")`
(similarly `blastr.conda.blast_channels`, `blastr.conda.blast_fallback`,
`blastr.conda.fallback_channels`, and `blastr.conda.channels`), which is
also the hook for testing candidate BLAST+ builds.

## Contributing

Contributions are welcome! Please see the [contributing
guide](https://heronoh.github.io/BLASTr/CONTRIBUTING.md) for more
details.

## License

This project is licensed under the MIT License - see the
[LICENSE.md](https://heronoh.github.io/BLASTr/LICENSE.md) file for
details.
