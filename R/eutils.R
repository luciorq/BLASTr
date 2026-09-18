# Minimal NCBI E-utilities client (https://www.ncbi.nlm.nih.gov/books/NBK25501/)
#
# Replaces the Entrez Direct command-line tools: the only two operations
# BLASTr needs - fetching NCBI Taxonomy records by Tax ID (`efetch`) and
# resolving organism names to Tax IDs (`esearch`) - are single HTTPS
# requests, so no conda environment (and no Perl) is required.
#
# NCBI etiquette implemented here:
# * `tool` (and optional `email`, via `options(blastr.ncbi.email = )`)
#   identify the client.
# * `NCBI_API_KEY` is sent as `api_key` when set.
# * Requests are throttled to 3/s (10/s with a key). The throttle state
#   lives in the worker's crate, which `mirai` copies per daemon, so a
#   pool of N workers is given `rate_share = N`: each worker then uses
#   an N-times longer interval and the aggregate stays within the limit.
# * HTTP 429 / 5xx and network errors are retried with backoff.

eutils_base_url <- "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/"

# Per-process throttle state (shared by every worker in this process).
eutils_state <- new.env(parent = emptyenv())

# `eutils_worker` is bound inside the taxonomy crate (see
# `make_tax_fetch_worker()`), not in the namespace; tell codetools.
globalVariables("eutils_worker")

#' NCBI API key from the environment (`NULL` when unset)
#' @keywords internal
#' @noRd
eutils_api_key <- function() {
  api_key <- Sys.getenv("NCBI_API_KEY", unset = "")
  if (isTRUE(nzchar(api_key))) {
    return(api_key)
  }
  NULL
}

#' Build a self-contained E-utilities request worker
#'
#' Returns a `carrier::crate()` - `function(endpoint, params)` - that
#' POSTs to `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/<endpoint>`
#' and returns `list(status, body, error)`, where `status` is `0L` on
#' HTTP 200, the HTTP status code otherwise, or `-1L` for a transport
#' error. Being crated, the same worker runs unchanged on `mirai`
#' daemons (only `base`, `curl`, and `cli` are used inside).
#'
#' @param rate_share Number of workers sharing NCBI's per-second budget.
#'   Each worker spaces its requests `rate_share` times wider, so `N`
#'   daemons running copies of the worker together stay within the
#'   limit. `1` (default) for the serial path.
#'
#' @keywords internal
#' @noRd
make_eutils_worker <- function(
  api_key = eutils_api_key(),
  email = getOption("blastr.ncbi.email", default = NULL),
  retry_times = 3L,
  timeout = 120,
  verbose = "silent",
  state = eutils_state,
  base_url = eutils_base_url,
  rate_share = 1L
) {
  carrier::crate(
    function(endpoint, params) {
      params <- c(params, list(tool = "BLASTr"))
      if (!base::is.null(api_key)) {
        params$api_key <- api_key
      }
      if (!base::is.null(email)) {
        params$email <- email
      }
      request_url <- base::paste0(base_url, endpoint)
      body <- base::paste0(
        base::names(params),
        "=",
        curl::curl_escape(base::as.character(params)),
        collapse = "&"
      )
      # NCBI limit: 3 requests/s without an API key, 10/s with one,
      # shared by `rate_share` concurrent workers.
      min_interval <- (if (base::is.null(api_key)) 1 / 3 else 1 / 10) *
        rate_share

      if (isTRUE(verbose %in% c("cmd", "full"))) {
        shown <- params[base::setdiff(base::names(params), "api_key")]
        cli::cli_inform(
          c(
            `i` = "NCBI E-utilities request: {.url {request_url}} [{base::paste0(base::names(shown), '=', base::substr(base::as.character(shown), 1L, 60L), collapse = ' ')}]" # nolint: line_length_linter
          )
        )
      }

      attempt <- 0L
      repeat {
        last_request <- state$last_request
        if (!base::is.null(last_request)) {
          wait <- min_interval -
            (base::as.numeric(base::Sys.time()) - last_request)
          if (isTRUE(wait > 0)) {
            base::Sys.sleep(wait)
          }
        }
        state$last_request <- base::as.numeric(base::Sys.time())

        handle <- curl::new_handle()
        curl::handle_setopt(
          handle,
          post = TRUE,
          postfields = body,
          timeout = timeout,
          useragent = "BLASTr (R package; https://github.com/heronoh/BLASTr)"
        )
        curl::handle_setheaders(
          handle,
          `Content-Type` = "application/x-www-form-urlencoded"
        )
        res <- base::tryCatch(
          curl::curl_fetch_memory(request_url, handle = handle),
          error = function(e) e
        )

        if (base::inherits(res, "error")) {
          status <- -1L
          body_text <- ""
          error_text <- base::conditionMessage(res)
          retriable <- TRUE
        } else {
          status <- base::as.integer(res$status_code)
          body_text <- base::rawToChar(res$content)
          base::Encoding(body_text) <- "UTF-8"
          if (isTRUE(status == 200L)) {
            return(list(status = 0L, body = body_text, error = NA_character_))
          }
          error_text <- base::paste0("HTTP ", status, " from ", endpoint)
          retriable <- isTRUE(status == 429L) || isTRUE(status >= 500L)
        }

        if (isFALSE(retriable) || isTRUE(attempt >= retry_times)) {
          return(list(status = status, body = body_text, error = error_text))
        }
        attempt <- attempt + 1L
        if (isTRUE(verbose %in% c("output", "full"))) {
          cli::cli_inform(
            c(
              `!` = "NCBI request failed ({error_text}); retry {attempt} of {retry_times}." # nolint: line_length_linter
            )
          )
        }
        base::Sys.sleep(base::min(2^attempt, 10))
      }
    },
    base_url = base_url,
    api_key = api_key,
    email = email,
    retry_times = as.integer(retry_times),
    timeout = timeout,
    verbose = verbose,
    state = state,
    rate_share = max(1, as.numeric(rate_share))
  )
}

#' Perform one E-utilities request in the current process
#' @keywords internal
#' @noRd
eutils_request <- function(endpoint, params, verbose = "silent") {
  eutils_worker <- make_eutils_worker(verbose = verbose)
  eutils_worker(endpoint, params)
}

#' Parse the `<IdList>` of an `esearch` XML response
#' @returns Character vector of UIDs (empty when none / unparsable).
#' @keywords internal
#' @noRd
parse_esearch_ids <- function(xml_string) {
  if (rlang::is_null(xml_string) || isFALSE(nzchar(xml_string))) {
    return(character(0L))
  }
  xml_doc <- tryCatch(
    xml2::read_xml(xml_string),
    error = function(e) NULL
  )
  if (rlang::is_null(xml_doc)) {
    return(character(0L))
  }
  ids <- xml2::xml_text(
    xml2::xml_find_all(xml_doc, "/eSearchResult/IdList/Id")
  )
  ids <- stringr::str_trim(ids)
  ids[nzchar(ids)]
}

#' Resolve an organism name to NCBI Taxonomy Tax IDs (`esearch`)
#'
#' Equivalent to `esearch -db taxonomy -query <term> | efetch -format uid`.
#'
#' @returns `list(status, ids, error)`; `ids` is a character vector,
#'   empty when there is no match or the request failed.
#' @keywords internal
#' @noRd
ncbi_taxonomy_search <- function(term, verbose = "silent") {
  res <- eutils_request(
    endpoint = "esearch.fcgi",
    params = list(
      db = "taxonomy",
      term = term,
      retmax = "10000",
      retmode = "xml"
    ),
    verbose = verbose
  )
  if (isFALSE(res$status == 0L)) {
    return(list(status = res$status, ids = character(0L), error = res$error))
  }
  list(status = 0L, ids = parse_esearch_ids(res$body), error = NA_character_)
}

#' Deprecation shim for the removed `env_name` argument
#'
#' Taxonomy functions no longer shell out to Entrez Direct, so the conda
#' environment argument has no effect.
#' @keywords internal
#' @noRd
warn_env_name_deprecated <- function(env_name, fn_name) {
  if (isTRUE(lifecycle::is_present(env_name))) {
    lifecycle::deprecate_warn(
      when = "0.2.0",
      what = paste0(fn_name, "(env_name)"),
      details = "NCBI Taxonomy is now queried directly over HTTPS (E-utilities); no conda environment is needed." # nolint: line_length_linter
    )
  }
  invisible(NULL)
}
