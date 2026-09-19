# Retrieve Taxonomic Ranks Using NCBI Taxonomy Tax IDs

Retrieves complete taxonomy information for given NCBI Taxonomy Tax IDs
by querying the NCBI E-utilities (`efetch`) directly over HTTPS - no
command-line tool is required. Multiple Tax IDs are fetched in a single
batched request. Each record in the response is matched back to its Tax
ID through the XML `<TaxId>` element, so results are correct regardless
of response order.

## Usage

``` r
get_tax_by_taxID(
  organisms_taxIDs,
  parse_result = TRUE,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = deprecated()
)
```

## Arguments

- organisms_taxIDs:

  A character vector of NCBI Taxonomy Tax IDs for which to retrieve
  taxonomy information.

- parse_result:

  Logical indicating whether to parse the taxonomy information into a
  wide tibble (`TRUE`, default) or return the long lineage table
  (`FALSE`).

- verbose:

  Verbosity level. One of `"silent"` (default), `"cmd"`, `"output"`, or
  `"full"`.

- env_name:

  **\[deprecated\]** No longer used: NCBI is queried directly over
  HTTPS. See
  [`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md)
  for NCBI rate limits and the `NCBI_API_KEY` environment variable.

## Value

A tibble containing the taxonomic ranks for the given Tax IDs. Tax IDs
that cannot be retrieved are absent from the result.

## Details

Note: NCBI Taxonomy replaced the `superkingdom` rank with `domain` in
its 2024/2025 restructure; both are returned (`Domain (NCBI)` /
`Superkingdom (NCBI)`).

## Examples

``` r
if (FALSE) { # \dontrun{
# Retrieve taxonomy for a single Tax ID
tax_info <- get_tax_by_taxID("9606") # Human

# Retrieve taxonomy for multiple Tax IDs (single batched request)
tax_ids <- c("9606", "10090", "10116") # Human, Mouse, Rat
tax_info <- get_tax_by_taxID(tax_ids)

# Get unparsed (long) taxonomy result
raw_tax_info <- get_tax_by_taxID("9606", parse_result = FALSE)

# Enable verbose output
tax_info <- get_tax_by_taxID("9606", verbose = "output")
} # }
```
