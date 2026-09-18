# Unit tests for the internal NCBI E-utilities client (R/eutils.R).
# Network-free tests mock the fetch layer; the live ones are skipped
# offline/on CRAN. Equivalence with the real Entrez Direct tools is
# covered separately in test-eutils-vs-edirect.R.

canned_tax_xml <- function() {
  paste0(
    "<TaxaSet><Taxon>",
    "<TaxId>7955</TaxId>",
    "<ScientificName>Danio rerio</ScientificName>",
    "<Rank>species</Rank>",
    "<LineageEx>",
    "<Taxon><TaxId>2759</TaxId><ScientificName>Eukaryota</ScientificName><Rank>domain</Rank></Taxon>",
    "<Taxon><TaxId>7954</TaxId><ScientificName>Danio</ScientificName><Rank>genus</Rank></Taxon>",
    "</LineageEx>",
    "</Taxon><Taxon>",
    "<TaxId>9606</TaxId>",
    "<ScientificName>Homo sapiens</ScientificName>",
    "<Rank>species</Rank>",
    "<LineageEx>",
    "<Taxon><TaxId>2759</TaxId><ScientificName>Eukaryota</ScientificName><Rank>domain</Rank></Taxon>",
    "<Taxon><TaxId>9605</TaxId><ScientificName>Homo</ScientificName><Rank>genus</Rank></Taxon>",
    "</LineageEx>",
    "</Taxon></TaxaSet>"
  )
}

testthat::test_that("parse_esearch_ids extracts the IdList", {
  xml_string <- paste0(
    "<eSearchResult><Count>2</Count><RetMax>2</RetMax>",
    "<IdList><Id>7955</Id><Id> 7954 </Id></IdList>",
    "</eSearchResult>"
  )
  testthat::expect_equal(parse_esearch_ids(xml_string), c("7955", "7954"))
  # No match: empty IdList (NCBI also emits <ErrorList>).
  testthat::expect_equal(
    parse_esearch_ids(
      "<eSearchResult><Count>0</Count><IdList/></eSearchResult>"
    ),
    character(0L)
  )
  testthat::expect_equal(parse_esearch_ids(""), character(0L))
  testthat::expect_equal(parse_esearch_ids(NULL), character(0L))
  testthat::expect_equal(parse_esearch_ids("<not xml"), character(0L))
})

testthat::test_that("eutils worker is a self-contained crate", {
  worker <- make_eutils_worker()
  testthat::expect_s3_class(worker, "crate")
  # Only explicitly passed objects are captured (safe to ship to daemons).
  testthat::expect_true(
    identical(parent.env(environment(worker)), baseenv())
  )
  testthat::expect_setequal(
    ls(environment(worker), all.names = TRUE),
    c(
      "base_url",
      "api_key",
      "email",
      "retry_times",
      "timeout",
      "verbose",
      "state",
      "rate_share"
    )
  )
})

testthat::test_that("eutils_api_key reads NCBI_API_KEY", {
  withr::local_envvar(list(NCBI_API_KEY = ""))
  testthat::expect_null(eutils_api_key())
  withr::local_envvar(list(NCBI_API_KEY = "abc123"))
  testthat::expect_equal(eutils_api_key(), "abc123")
})

testthat::test_that("eutils worker reports transport errors without hanging", {
  state <- new.env(parent = emptyenv())
  worker <- make_eutils_worker(
    base_url = "http://127.0.0.1:9/",
    retry_times = 0L,
    timeout = 5,
    state = state
  )
  res <- worker("efetch.fcgi", list(db = "taxonomy", id = "9606"))
  testthat::expect_equal(res$status, -1L)
  testthat::expect_true(nzchar(res$error))
  testthat::expect_equal(res$body, "")
  # Throttle bookkeeping happened.
  testthat::expect_true(is.numeric(state$last_request))
})

testthat::test_that("eutils worker spaces requests by rate_share", {
  # Unreachable host: each attempt fails in milliseconds, so the elapsed
  # time between calls is the throttle alone. Three workers sharing the
  # 3 req/s budget must wait >= 1 s between requests.
  withr::local_envvar(list(NCBI_API_KEY = ""))
  state <- new.env(parent = emptyenv())
  worker <- make_eutils_worker(
    base_url = "http://127.0.0.1:9/",
    retry_times = 0L,
    timeout = 5,
    state = state,
    rate_share = 3L
  )
  worker("efetch.fcgi", list(db = "taxonomy", id = "1"))
  t0 <- Sys.time()
  worker("efetch.fcgi", list(db = "taxonomy", id = "2"))
  elapsed <- as.numeric(Sys.time() - t0, units = "secs")
  testthat::expect_gte(elapsed, 0.95)
  testthat::expect_lt(elapsed, 3)
})

testthat::test_that("tax_xml_is_valid distinguishes empty TaxaSet from garbage", {
  testthat::expect_true(tax_xml_is_valid("<TaxaSet></TaxaSet>"))
  testthat::expect_true(tax_xml_is_valid(canned_tax_xml()))
  testthat::expect_false(tax_xml_is_valid("<html><body>Error</body></html>"))
  testthat::expect_false(tax_xml_is_valid("<not xml"))
  testthat::expect_false(tax_xml_is_valid(""))
  testthat::expect_false(tax_xml_is_valid(NULL))
})

testthat::test_that("parallel_get_tax does not retry IDs unknown to NCBI", {
  calls <- 0L
  requested <- list()
  testthat::local_mocked_bindings(
    make_tax_fetch_worker = function(verbose = "silent", rate_share = 1L) {
      function(taxids) {
        calls <<- calls + 1L
        requested[[calls]] <<- taxids
        # NCBI answers with the known records only (unknown IDs omitted).
        list(status = 0L, stdout = canned_tax_xml(), stderr = NA_character_)
      }
    }
  )
  res <- parallel_get_tax(
    organisms_taxIDs = c("9606", "999999999", "7955"),
    retry_times = 10,
    verbose = "silent"
  )
  testthat::expect_equal(calls, 1L)
  testthat::expect_setequal(res$query_taxID, c("9606", "7955"))

  # An all-unknown batch (empty TaxaSet) is likewise final.
  calls <- 0L
  testthat::local_mocked_bindings(
    make_tax_fetch_worker = function(verbose = "silent", rate_share = 1L) {
      function(taxids) {
        calls <<- calls + 1L
        list(
          status = 0L,
          stdout = "<TaxaSet></TaxaSet>",
          stderr = NA_character_
        )
      }
    }
  )
  res_none <- parallel_get_tax(
    "999999999",
    retry_times = 10,
    verbose = "silent"
  )
  testthat::expect_equal(calls, 1L)
  testthat::expect_equal(nrow(res_none), 0L)

  # A 200 with a non-TaxaSet body is transient and IS retried.
  calls <- 0L
  testthat::local_mocked_bindings(
    make_tax_fetch_worker = function(verbose = "silent", rate_share = 1L) {
      function(taxids) {
        calls <<- calls + 1L
        if (isTRUE(calls == 1L)) {
          return(list(
            status = 0L,
            stdout = "<html>Service Unavailable</html>",
            stderr = NA_character_
          ))
        }
        list(status = 0L, stdout = canned_tax_xml(), stderr = NA_character_)
      }
    }
  )
  res_retry <- parallel_get_tax("9606", retry_times = 2, verbose = "silent")
  testthat::expect_equal(calls, 2L)
  testthat::expect_equal(res_retry$query_taxID, "9606")
})

testthat::test_that("get_tax_by_taxID parses a mocked efetch response offline", {
  testthat::local_mocked_bindings(
    fetch_tax_xml = function(taxids, verbose = "silent") {
      list(status = 0L, stdout = canned_tax_xml(), stderr = NA_character_)
    }
  )
  res <- get_tax_by_taxID(c("9606", "7955"), verbose = "silent")
  testthat::expect_equal(nrow(res), 2L)
  testthat::expect_equal(ncol(res), 14L)
  testthat::expect_setequal(res$query_taxID, c("9606", "7955"))
  testthat::expect_equal(
    res$`Genus (NCBI)`[res$query_taxID == "7955"],
    "Danio"
  )
  # Only requested IDs are kept.
  res_one <- get_tax_by_taxID("9606", verbose = "silent")
  testthat::expect_equal(res_one$query_taxID, "9606")
  # A failed request yields the empty schema.
  testthat::local_mocked_bindings(
    fetch_tax_xml = function(taxids, verbose = "silent") {
      list(status = 500L, stdout = "", stderr = "HTTP 500 from efetch.fcgi")
    }
  )
  res_fail <- get_tax_by_taxID("9606", verbose = "silent")
  testthat::expect_equal(nrow(res_fail), 0L)
  testthat::expect_equal(ncol(res_fail), 14L)
})

testthat::test_that("parallel_get_tax retries transient failures offline", {
  calls <- 0L
  testthat::local_mocked_bindings(
    make_tax_fetch_worker = function(verbose = "silent", rate_share = 1L) {
      function(taxids) {
        calls <<- calls + 1L
        if (isTRUE(calls == 1L)) {
          return(list(status = 429L, stdout = "", stderr = "HTTP 429"))
        }
        list(status = 0L, stdout = canned_tax_xml(), stderr = NA_character_)
      }
    }
  )
  res <- parallel_get_tax(
    organisms_taxIDs = c("9606", "7955"),
    retry_times = 2,
    verbose = "silent"
  )
  testthat::expect_equal(calls, 2L)
  testthat::expect_setequal(res$query_taxID, c("9606", "7955"))
})

testthat::test_that("get_tax_by_name joins mocked esearch and efetch offline", {
  testthat::local_mocked_bindings(
    ncbi_taxonomy_search = function(term, verbose = "silent") {
      id_map <- c("Danio rerio" = "7955", "Homo sapiens" = "9606")
      ids <- unname(id_map[names(id_map) == term])
      list(status = 0L, ids = ids, error = NA_character_)
    },
    make_tax_fetch_worker = function(verbose = "silent", rate_share = 1L) {
      function(taxids) {
        list(status = 0L, stdout = canned_tax_xml(), stderr = NA_character_)
      }
    }
  )
  res <- get_tax_by_name(
    c("Danio rerio", "Notarealtaxon xyzzyplugh", "Homo sapiens"),
    verbose = "silent"
  )
  testthat::expect_equal(colnames(res)[[1]], "query_name")
  testthat::expect_setequal(res$query_name, c("Danio rerio", "Homo sapiens"))
  testthat::expect_equal(
    res$`Genus (NCBI)`[res$query_name == "Homo sapiens"],
    "Homo"
  )
})

testthat::test_that("env_name is deprecated in the taxonomy functions", {
  testthat::local_mocked_bindings(
    fetch_tax_xml = function(taxids, verbose = "silent") {
      list(status = 0L, stdout = canned_tax_xml(), stderr = NA_character_)
    },
    make_tax_fetch_worker = function(verbose = "silent", rate_share = 1L) {
      function(taxids) {
        list(status = 0L, stdout = canned_tax_xml(), stderr = NA_character_)
      }
    },
    ncbi_taxonomy_search = function(term, verbose = "silent") {
      list(status = 0L, ids = "7955", error = NA_character_)
    }
  )
  get_tax_by_taxID("9606", env_name = "blastr-entrez-env") |>
    lifecycle::expect_deprecated()
  parallel_get_tax("9606", env_name = "blastr-entrez-env") |>
    lifecycle::expect_deprecated()
  get_tax_by_name("Danio rerio", env_name = "blastr-entrez-env") |>
    lifecycle::expect_deprecated()
})

testthat::test_that("eutils worker runs on a mirai daemon (live)", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  mirai::daemons(n = 1L)
  withr::defer(mirai::daemons(n = 0L))
  worker <- make_tax_fetch_worker()
  m <- mirai::mirai(worker(taxids), worker = worker, taxids = "9606")
  res <- m[]
  testthat::expect_false(mirai::is_error_value(res))
  testthat::expect_equal(res$status, 0L)
  testthat::expect_true(stringr::str_detect(res$stdout, "Homo sapiens"))
})
