# Retrieve Taxonomic Ranks Using Organism Names

Recover complete taxonomy for organism names by searching the NCBI
Taxonomy database (E-utilities `esearch`) and fetching the matching
records (`efetch`), directly over HTTPS - no command-line tool is
required. The output schema matches
[`get_tax_by_taxID()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_taxID.md),
with an additional `query_name` column mapping each result back to the
searched name.

## Usage

``` r
get_tax_by_name(
  organisms_names,
  parse_result = TRUE,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = deprecated()
)
```

## Arguments

- organisms_names:

  Character vector of organism names (e.g. scientific names) to retrieve
  taxonomy for.

- parse_result:

  Logical indicating whether to parse the taxonomy information into a
  wide tibble (`TRUE`, default) or return the long lineage table
  (`FALSE`).

- verbose:

  Verbosity level. One of `"silent"` (default), `"cmd"`, `"output"`, or
  `"full"`.

- env_name:

  **\[deprecated\]** No longer used: NCBI is queried directly over
  HTTPS.

## Value

A tibble with the taxonomic ranks for the matching organisms. Names with
no match in NCBI Taxonomy are absent from the result.

## Examples

``` r
if (FALSE) { # \dontrun{
tax_info <- get_tax_by_name("Danio rerio")

tax_info <- get_tax_by_name(c("Homo sapiens", "Danio rerio"))
} # }
```
