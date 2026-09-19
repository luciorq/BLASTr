# Retrieve Taxonomic Ranks for a List of NCBI Taxonomy Tax IDs in Parallel

Retrieves taxonomy ranks for a list of NCBI Taxonomy Tax IDs from the
NCBI E-utilities (`efetch`), directly over HTTPS - no command-line tool
is required. Tax IDs are batched (up to `batch_size` per request) and
batches are dispatched to
[`mirai::daemons()`](https://mirai.r-lib.org/reference/daemons.html)
with
[`mirai::mirai_map()`](https://mirai.r-lib.org/reference/mirai_map.html)
when `total_cores > 1`. Batches that fail (HTTP errors, network errors,
malformed responses) are retried up to `retry_times` times; Tax IDs that
NCBI reports as unknown (omitted from an otherwise valid response) are
not retried.

## Usage

``` r
parallel_get_tax(
  organisms_taxIDs,
  parse_result = TRUE,
  total_cores = 1L,
  retry_times = 10L,
  batch_size = 100L,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = deprecated()
)
```

## Arguments

- organisms_taxIDs:

  A character vector of NCBI Taxonomy Tax IDs to retrieve taxonomy
  information for.

- parse_result:

  Logical indicating whether to parse the taxonomy information into a
  wide tibble (`TRUE`, default) or return the long lineage table
  (`FALSE`).

- total_cores:

  Integer specifying the number of parallel requests. Defaults to `1`.
  If
  [`mirai::daemons()`](https://mirai.r-lib.org/reference/daemons.html)
  are already set for the session, the existing pool is used as-is.

- retry_times:

  Integer specifying the number of times to retry fetching taxonomy
  information if it fails. Defaults to `10`.

- batch_size:

  Maximum number of Tax IDs per `efetch` request. Defaults to `100`.

- verbose:

  Verbosity level. One of `"silent"` (default), `"cmd"`, `"output"`, or
  `"full"`.

- env_name:

  **\[deprecated\]** No longer used: NCBI is queried directly over
  HTTPS.

## Value

A tibble containing the taxonomic ranks for the given Tax IDs.

## NCBI etiquette

NCBI enforces API rate limits: 3 requests per second without an API key,
10 with one. Set the `NCBI_API_KEY` environment variable to use a key
(it is sent with every request); `options(blastr.ncbi.email = )`
optionally identifies you to NCBI. Requests are throttled so that the
whole worker pool stays within the limit (each of `total_cores` workers
spaces its requests `total_cores` times wider), and transient failures
(HTTP 429/5xx, network errors) are retried with backoff. Because each
request already carries up to `batch_size` Tax IDs and the NCBI rate
limit is the bottleneck, `total_cores > 1` rarely speeds things up; it
mainly overlaps network latency.

## Examples

``` r
if (FALSE) { # \dontrun{
# Retrieve taxonomy for multiple Tax IDs using 2 processes
tax_ids <- c("9606", "10090", "10116") # Human, Mouse, Rat
tax_info <- parallel_get_tax(tax_ids, total_cores = 2)

# Retrieve unparsed taxonomy result
tax_info_unparsed <- parallel_get_tax(tax_ids, parse_result = FALSE)

# Change the number of retry attempts
tax_info <- parallel_get_tax(tax_ids, retry_times = 2)

# Enable verbose output
tax_info <- parallel_get_tax(tax_ids, verbose = "output")
} # }
```
