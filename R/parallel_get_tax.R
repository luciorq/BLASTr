#' Retrieve Taxonomic Ranks for a List of NCBI Taxonomy Tax IDs in Parallel
#'
#' Retrieves taxonomy ranks for a list of NCBI Taxonomy Tax IDs from the
#' NCBI E-utilities (`efetch`), directly over HTTPS - no command-line
#' tool is required. Tax IDs are batched (up to `batch_size` per request)
#' and batches are dispatched to [mirai::daemons()] with
#' [mirai::mirai_map()] when `total_cores > 1`. Batches that fail
#' (HTTP errors, network errors, malformed responses) are retried up to
#' `retry_times` times; Tax IDs that NCBI reports as unknown (omitted
#' from an otherwise valid response) are not retried.
#'
#' @section NCBI etiquette:
#' NCBI enforces API rate limits: 3 requests per second without an API
#' key, 10 with one. Set the `NCBI_API_KEY` environment variable to use a
#' key (it is sent with every request); `options(blastr.ncbi.email = )`
#' optionally identifies you to NCBI. Requests are throttled so that the
#' whole worker pool stays within the limit (each of `total_cores`
#' workers spaces its requests `total_cores` times wider), and transient
#' failures (HTTP 429/5xx, network errors) are retried with backoff.
#' Because each request already carries up to `batch_size` Tax IDs and
#' the NCBI rate limit is the bottleneck, `total_cores > 1` rarely speeds
#' things up; it mainly overlaps network latency.
#'
#' @param organisms_taxIDs A character vector of NCBI Taxonomy Tax IDs to
#'   retrieve taxonomy information for.
#' @param parse_result Logical indicating whether to parse the taxonomy
#'   information into a wide tibble (`TRUE`, default) or return the long
#'   lineage table (`FALSE`).
#' @param total_cores Integer specifying the number of parallel requests.
#'   Defaults to `1`. If [mirai::daemons()] are already set for the
#'   session, the existing pool is used as-is.
#' @param retry_times Integer specifying the number of times to retry
#'   fetching taxonomy information if it fails. Defaults to `10`.
#' @param batch_size Maximum number of Tax IDs per `efetch` request.
#'   Defaults to `100`.
#' @param verbose Verbosity level. One of `"silent"` (default), `"cmd"`,
#'   `"output"`, or `"full"`.
#' @param env_name `r lifecycle::badge("deprecated")` No longer used:
#'   NCBI is queried directly over HTTPS.
#'
#' @returns A tibble containing the taxonomic ranks for the given Tax IDs.
#'
#' @examples
#' \dontrun{
#' # Retrieve taxonomy for multiple Tax IDs using 2 processes
#' tax_ids <- c("9606", "10090", "10116") # Human, Mouse, Rat
#' tax_info <- parallel_get_tax(tax_ids, total_cores = 2)
#'
#' # Retrieve unparsed taxonomy result
#' tax_info_unparsed <- parallel_get_tax(tax_ids, parse_result = FALSE)
#'
#' # Change the number of retry attempts
#' tax_info <- parallel_get_tax(tax_ids, retry_times = 2)
#'
#' # Enable verbose output
#' tax_info <- parallel_get_tax(tax_ids, verbose = "output")
#' }
#' @export
parallel_get_tax <- function(
  organisms_taxIDs, # nolint: object_name_linter
  parse_result = TRUE,
  total_cores = 1L,
  retry_times = 10L,
  batch_size = 100L,
  verbose = c("silent", "cmd", "output", "full"),
  env_name = deprecated()
) {
  rlang::check_required(organisms_taxIDs)
  verbose <- rlang::arg_match(verbose)
  warn_env_name_deprecated(env_name, "parallel_get_tax")
  taxids_to_run <- unique(
    stringr::str_trim(as.character(organisms_taxIDs))
  )
  taxids_to_run <- taxids_to_run[
    !rlang::are_na(taxids_to_run) & nzchar(taxids_to_run)
  ]

  run_verbose <- ifelse(
    verbose %in% c("cmd", "output", "full"),
    verbose,
    "silent"
  )

  # A pre-existing daemon pool is adopted regardless of `total_cores`;
  # otherwise a pool is created when the workload spans multiple batches
  # and `total_cores > 1`, with guaranteed teardown.
  parallel_var <- FALSE
  if (isTRUE(mirai::daemons_set())) {
    parallel_var <- TRUE
  } else if (
    isTRUE(total_cores > 1L) &&
      isTRUE(length(taxids_to_run) > batch_size)
  ) {
    mirai::daemons(n = total_cores)
    withr::defer(
      expr = {
        mirai::daemons(n = 0L)
      }
    )
    parallel_var <- TRUE
  }

  # NCBI's per-second budget is shared by every worker in the pool: each
  # daemon gets its own copy of the throttle state, so the worker is told
  # how many peers it has and spaces its requests accordingly.
  n_workers <- 1L
  if (isTRUE(parallel_var)) {
    n_workers <- max(1L, as.integer(mirai::status()$connections))
  }

  # Standalone worker: fetches raw XML on the daemon; parsing happens in
  # the main process (cheap relative to the network round-trip).
  fetch_worker <- make_tax_fetch_worker(
    verbose = run_verbose,
    rate_share = n_workers
  )

  run_batches <- function(batch_list) {
    if (isTRUE(parallel_var) && isTRUE(mirai::daemons_set())) {
      map_res <- mirai::mirai_map(.x = batch_list, .f = fetch_worker)
      return(mirai::collect_mirai(map_res))
    }
    purrr::map(.x = batch_list, .f = fetch_worker)
  }

  tax_long_list <- list()
  pending_ids <- taxids_to_run
  unknown_ids <- character(0L)
  retry_count <- 0L

  while (isTRUE(length(pending_ids) > 0L)) {
    batch_list <- chunk_indices(pending_ids, batch_size)
    batch_results <- run_batches(batch_list)

    for (batch_i in seq_along(batch_results)) {
      batch_res <- batch_results[[batch_i]]
      if (isTRUE(mirai::is_error_value(batch_res))) {
        next
      }
      if (isFALSE(batch_res$status == 0L)) {
        next
      }
      if (isFALSE(tax_xml_is_valid(batch_res$stdout))) {
        # HTTP 200 with a body that is not a TaxaSet (e.g. an HTML error
        # page): treat as transient and retry the whole batch.
        next
      }
      batch_long_tbl <- parse_tax_xml(batch_res$stdout)
      batch_found_ids <- character(0L)
      if (!rlang::is_null(batch_long_tbl)) {
        # Keep only requested IDs (merged-ID records are emitted under
        # both their old and new Tax IDs by the parser).
        batch_long_tbl <- dplyr::filter(
          batch_long_tbl,
          .data$query_taxID %in% taxids_to_run
        )
        tax_long_list <- c(tax_long_list, list(batch_long_tbl))
        batch_found_ids <- unique(batch_long_tbl$query_taxID)
      }
      # A well-formed response that omits an ID means NCBI does not know
      # it: definitive, so it is reported once and never retried.
      unknown_ids <- c(
        unknown_ids,
        setdiff(batch_list[[batch_i]], batch_found_ids)
      )
    }

    retrieved_ids <- character(0L)
    if (isTRUE(length(tax_long_list) > 0L)) {
      retrieved_ids <- unique(
        purrr::list_rbind(tax_long_list)$query_taxID
      )
    }
    pending_ids <- taxids_to_run[
      !(taxids_to_run %in% c(retrieved_ids, unknown_ids))
    ]

    if (isTRUE(length(pending_ids) > 0L)) {
      if (isTRUE(retry_count >= retry_times)) {
        break
      }
      retry_count <- retry_count + 1L
      if (isFALSE(identical(verbose, "silent"))) {
        cli::cli_inform(
          c(
            `i` = "Retrying {length(pending_ids)} Tax ID{?s}: attempt {retry_count} of {retry_times}." # nolint: line_length_linter
          )
        )
      }
      # Increasing backoff between retry rounds: be polite to NCBI and
      # give transient failures time to clear.
      Sys.sleep(min(retry_count, 5L))
    }
  }

  if (isFALSE(identical(verbose, "silent"))) {
    if (isTRUE(length(unknown_ids) > 0L)) {
      cli::cli_inform(
        c(
          `!` = "{length(unknown_ids)} Tax ID{?s} unknown to NCBI Taxonomy (not retried): {.val {unique(unknown_ids)}}." # nolint: line_length_linter
        )
      )
    }
    if (isTRUE(length(pending_ids) > 0L)) {
      cli::cli_inform(
        c(
          `!` = "The following Tax ID{?s} could not be retrieved after {retry_times} attempt{?s}: {.val {pending_ids}}." # nolint: line_length_linter
        )
      )
    }
  }

  tax_long_tbl <- NULL
  if (isTRUE(length(tax_long_list) > 0L)) {
    tax_long_tbl <- dplyr::distinct(purrr::list_rbind(tax_long_list))
  }

  return(format_tax_tbl(tax_long_tbl, parse_result = parse_result))
}
