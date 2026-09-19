# Introduction to BLASTr

``` r

library(BLASTr)
```

`BLASTr` runs BLAST+ searches from R, tailored for taxonomic
classification of Amplicon Sequence Variants (ASVs) from metabarcoding
and metagenomic experiments. All chunks below are not evaluated when the
package is built (they require network access and external tools), but
can be run interactively.

## Installing command-line dependencies

`BLASTr` manages its only command-line dependency, BLAST+, in a
dedicated conda environment through the `condathis` package. NCBI
Taxonomy lookups query the NCBI E-utilities directly over HTTPS, and the
primer check below runs in R, so neither needs a tool. The first call to
any function that needs a tool will install it automatically; you can
also install everything up front:

``` r

install_dependencies()
```

Pinned tool versions are installed for reproducibility. To upgrade the
environments later, run `install_dependencies(force = TRUE)`.

## Checking primers in raw reads

Before assembling ASVs it is worth confirming that a library really
carries the primers you expect.
[`search_primers_on_fq()`](https://heronoh.github.io/BLASTr/reference/search_primers_on_fq.md)
streams plain or gzip-compressed FASTQ files and counts, per primer, how
many reads contain it. IUPAC degenerate bases are supported and, by
default, both strands are searched. The check runs in R, so this chunk
is evaluated here on a small synthetic library shipped with the package
(300 reads: 150 with the MiFish-U forward primer on the forward strand,
100 with it on the reverse strand, and 50 with a COI primer instance).

``` r

fastq_path <- fs::path_package("BLASTr", "extdata", "toy_reads.fastq.gz")

primers <- c(
  `MiFish-U-F` = "GTCGGTAAAACTCGTGCCAGC",
  `mlCOIintF` = "GGWACWGGWTGAACWGTWTAYCCYCC"
)

search_primers_on_fq(primer_seqs = primers, fastq_paths = fastq_path)
#> # A tibble: 2 × 7
#>   file_name primer_name primer_sequence parsed_primer total_reads primer_matches
#>   <chr>     <chr>       <chr>           <chr>               <dbl>          <dbl>
#> 1 /home/ru… MiFish-U-F  GTCGGTAAAACTCG… GTCGGTAAAACT…         300            250
#> 2 /home/ru… mlCOIintF   GGWACWGGWTGAAC… GG[AT]AC[AT]…         300             50
#> # ℹ 1 more variable: percentage <dbl>
```

Restricting the search to the forward strand drops the 100
reverse-strand reads, which is a quick way to see the orientation of a
library. On real data expect roughly one million reads per 15 seconds
for two primers on both strands:

``` r

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

## Building a BLAST database

Any FASTA file with unique headers can be turned into a BLAST+ database:

``` r

fasta_path <- fs::path_package(
  "BLASTr", "extdata", "minimal_db_blast",
  ext = "fasta"
)
taxid_map <- fs::path_package(
  "BLASTr", "extdata", "minimal_db_blast",
  ext = "txt"
)
db_path <- fs::path_temp("minimal_db_blast")

make_blast_db(
  fasta_path = fasta_path,
  db_path = db_path,
  db_type = "nucl",
  taxid_map = taxid_map
)
```

The optional `taxid_map` file (one `<SequenceId> <TaxonomyId>` pair per
line) makes BLAST results include subject Tax IDs (`staxid`), which can
then be resolved to full lineages with
[`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md).

## Searching sequences in parallel

[`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
deduplicates the query sequences, groups them into multi-record FASTA
batches, and dispatches the batches to parallel workers (`mirai`
daemons). Failed batches are salvaged per-sequence and retried.

``` r

asvs <- readLines(
  fs::path_package("BLASTr", "extdata", "asvs_test", ext = "txt")
)

blast_res <- parallel_blast(
  query_seqs = asvs,
  db_path = db_path,
  total_cores = 2,
  num_alignments = 4
)

blast_res
```

The result has one row per unique query sequence, with the top
`num_alignments` hits spread into `1_`, `2_`, … column groups (subject
header, identity, alignment coordinates, e-value, bit score, query
coverage, and subject Tax ID).

Every query’s BLAST exit status and error/warning output is preserved:

``` r

exit_codes(blast_res)
```

## Retrieving taxonomy

Tax IDs from the BLAST hits can be resolved into full taxonomic lineages
from the NCBI E-utilities (`efetch`), directly over HTTPS. Requests are
batched (up to 100 Tax IDs per request):

``` r

tax_ids <- unique(blast_res$`1_staxid`)

tax_tbl <- parallel_get_tax(
  organisms_taxIDs = tax_ids,
  total_cores = 1
)

tax_tbl
```

You can also search NCBI Taxonomy by organism name:

``` r

get_tax_by_name("Danio rerio")
```

Note that NCBI enforces API rate limits (3 requests per second without
an API key, 10 with one). Set the `NCBI_API_KEY` environment variable to
use a key; `BLASTr` sends it with every request and throttles requests
accordingly.

## Performance notes

- **Batching** is the main speed lever: each BLAST+ process loads the
  database index once and searches many queries. Control it with
  `chunk_size` (default: automatic, targeting ~4 chunks per core).
- **`total_cores`** sets how many BLAST+ processes run concurrently;
  `num_threads` sets threads per process. Effective CPU usage is
  `total_cores * num_threads`.
- If the [mori](https://cran.r-project.org/package=mori) package is
  installed, the deduplicated query vector is shared with workers
  through OS shared memory (zero-copy), which matters for very large
  query sets.
- If your session already has
  [`mirai::daemons()`](https://mirai.r-lib.org/reference/daemons.html)
  set, `BLASTr` uses the existing pool instead of creating a new one.
