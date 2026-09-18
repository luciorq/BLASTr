# Internal engine shared by `parallel_blast()`, `get_blast_results()`,
# `run_blast()`, and `blast_cmd()`.
#
# Design:
# - Query sequences are deduplicated and batched into multi-record FASTA
#   chunks (`>BLASTrQ<i>` headers), so each BLAST+ process is started once
#   per chunk instead of once per sequence, amortizing process startup and
#   database index loading.
# - Chunks are dispatched with `mirai::mirai_map()` on pre-set daemons.
#   When the `mori` package is installed, the deduplicated sequence vector
#   is placed in OS shared memory with `mori::share()` so daemons receive a
#   tiny reference instead of a full copy of the payload.
# - A failed chunk (non-zero exit status) is salvaged by re-running its
#   members individually (same attempt), isolating poison queries without
#   losing results for healthy ones. Failed single queries are then retried
#   up to `retry_times` additional rounds.

# Column names used for `-outfmt "6 std qcovhsp staxid stitle"` output.
blast_result_col_names <- c(
  "query",
  "subject",
  "identity",
  "length",
  "mismatches",
  "gaps",
  "query start",
  "query end",
  "subject start",
  "subject end",
  "e-value",
  "bitscore",
  "qcovhsp",
  "staxid",
  "subject header"
)

blast_outfmt_string <- "6 std qcovhsp staxid stitle"

# Order of the per-hit value columns in the wide output
# (first column of each `<res>_` group is the subject header).
blast_wide_value_cols <- c(
  "subject header",
  "subject",
  "identity",
  "length",
  "mismatches",
  "gaps",
  "query start",
  "query end",
  "subject start",
  "subject end",
  "e-value",
  "bitscore",
  "qcovhsp",
  "staxid"
)

# Typed NA prototype of one hit-rank column group: the wide output
# always carries at least the `1_` group so downstream code can rely on
# `1_subject`, `1_staxid`, etc. existing even when no query has hits.
blast_wide_na_prototype <- tibble::tibble(
  `subject header` = NA_character_,
  `subject` = NA_character_,
  `identity` = NA_real_,
  `length` = NA_integer_,
  `mismatches` = NA_integer_,
  `gaps` = NA_integer_,
  `query start` = NA_integer_,
  `query end` = NA_integer_,
  `subject start` = NA_integer_,
  `subject end` = NA_integer_,
  `e-value` = NA_real_,
  `bitscore` = NA_real_,
  `qcovhsp` = NA_real_,
  `staxid` = NA_character_
)

#' Split indices into chunks of at most `chunk_size` elements
#' @keywords internal
#' @noRd
chunk_indices <- function(idx, chunk_size) {
  unname(split(idx, ceiling(seq_along(idx) / chunk_size)))
}

#' Default chunk size targeting ~4 chunks per core, capped for retry cost
#' @keywords internal
#' @noRd
auto_chunk_size <- function(n_seqs, total_cores) {
  chunk_size <- ceiling(n_seqs / (max(total_cores, 1L) * 4L))
  max(1L, min(500L, chunk_size))
}

#' Build a self-contained worker function for one BLAST chunk
#'
#' Returns a `carrier::crate()` so the function can be shipped to `mirai`
#' daemons without requiring the `BLASTr` namespace on the worker. The
#' worker receives a vector of sequence indices, writes a multi-record
#' FASTA (`>BLASTrQ<i>`), and returns the raw process result.
#'
#' @keywords internal
#' @noRd
make_blast_worker <- function(
  query_seqs,
  db_path,
  num_alignments,
  num_threads,
  blast_type,
  perc_id,
  perc_qcov_hsp,
  mt_mode,
  verbose,
  env_name,
  outfmt = blast_outfmt_string
) {
  carrier::crate(
    function(idx) {
      seq_chunk <- as.character(query_seqs[idx])
      query_path <- withr::local_tempfile(
        pattern = "blastr_query_",
        fileext = ".fasta"
      )
      base::writeLines(
        base::paste0(">BLASTrQ", idx, "\n", seq_chunk),
        con = query_path
      )
      withr::local_envvar(
        .new = list(
          BLAST_USAGE_REPORT = "false",
          NCBI_DONT_USE_NCBIRC = "true",
          NCBI_DONT_USE_LOCAL_CONFIG = "true"
        ),
        action = "replace"
      )
      blast_res <- condathis::run_bin(
        blast_type,
        "-db",
        db_path,
        "-query",
        query_path,
        "-outfmt",
        outfmt,
        "-max_hsps",
        "1",
        "-perc_identity",
        as.character(perc_id),
        "-qcov_hsp_perc",
        as.character(perc_qcov_hsp),
        "-num_alignments",
        as.character(num_alignments),
        "-num_threads",
        as.character(num_threads),
        "-mt_mode",
        mt_mode,
        env_name = env_name,
        verbose = verbose,
        error = "continue"
      )
      list(
        idx = idx,
        status = blast_res$status,
        stdout = blast_res$stdout,
        stderr = blast_res$stderr
      )
    },
    query_seqs = query_seqs,
    db_path = as.character(db_path),
    num_alignments = as.character(num_alignments),
    num_threads = as.character(num_threads),
    blast_type = blast_type,
    perc_id = as.character(perc_id),
    perc_qcov_hsp = as.character(perc_qcov_hsp),
    mt_mode = mt_mode,
    outfmt = outfmt,
    verbose = verbose,
    env_name = env_name
  )
}

#' Parse tabular BLAST output into a long tibble keyed by sequence index
#' @keywords internal
#' @noRd
parse_blast_stdout <- function(stdout) {
  if (isTRUE(is.null(stdout)) || isFALSE(nzchar(stdout))) {
    return(NULL)
  }
  # NOTE: outfmt-6 output has no comment lines and no quoting; readr's
  # defaults (comment = "#", quote = '"') silently truncate subject
  # titles containing "#" and can crash on titles starting with '"'.
  hits_tbl <- readr::read_delim(
    I(stdout),
    delim = "\t",
    quote = "",
    comment = "",
    col_names = blast_result_col_names,
    col_types = readr::cols(
      `query` = readr::col_character(),
      `subject` = readr::col_character(),
      `identity` = readr::col_double(),
      `length` = readr::col_integer(),
      `mismatches` = readr::col_integer(),
      `gaps` = readr::col_integer(),
      `query start` = readr::col_integer(),
      `query end` = readr::col_integer(),
      `subject start` = readr::col_integer(),
      `subject end` = readr::col_integer(),
      `e-value` = readr::col_double(),
      `bitscore` = readr::col_double(),
      `qcovhsp` = readr::col_double(),
      `staxid` = readr::col_character(),
      `subject header` = readr::col_character()
    ),
    trim_ws = TRUE
  )
  hits_tbl$seq_index <- as.integer(
    stringr::str_remove(hits_tbl$query, "^BLASTrQ")
  )
  hits_tbl
}

#' Are the current mirai daemons on the local machine?
#'
#' Shared memory (`mori::share()`) can only be dereferenced by processes
#' on the same machine. Local pools use `abstract://` (Linux) or
#' `ipc://` URLs; loopback TCP also qualifies. Anything else (including
#' an undeterminable state) is treated as remote.
#'
#' @keywords internal
#' @noRd
daemons_are_local <- function() {
  daemons_url <- tryCatch(
    mirai::status()$daemons,
    error = function(e) NULL
  )
  if (!rlang::is_character(daemons_url) || isTRUE(length(daemons_url) == 0L)) {
    return(FALSE)
  }
  all(
    stringr::str_detect(
      daemons_url,
      "^(abstract://|ipc://|tcp://127\\.|tcp://localhost)"
    )
  )
}

#' Run BLAST for a set of unique sequences with batching, salvage and retry
#'
#' @param query_seqs Character vector of unique, whitespace-free sequences.
#' @param parallel Logical: dispatch chunks with `mirai::mirai_map()`
#'   (requires daemons already set) instead of running serially.
#' @param progress Logical: show a progress bar while collecting results.
#'
#' @returns A list with `hits` (long tibble of parsed hits with `seq_index`
#'   and `res` rank columns) and `status` (per-sequence tibble with
#'   `seq_index`, `exit_code`, `stderr`). `exit_code` is `0` for
#'   success, the BLAST+ exit status for tool failures, or `-1L` when
#'   the R-level worker itself failed (e.g. daemon crash). `stderr`
#'   carries the full standard error output of the BLAST+ invocation
#'   that produced (or last attempted) the query.
#'
#' @keywords internal
#' @noRd
blast_engine <- function(
  query_seqs,
  db_path,
  total_cores = 1L,
  num_threads = 1L,
  blast_type = "blastn",
  perc_id = 80L,
  perc_qcov_hsp = 80L,
  num_alignments = 4L,
  retry_times = 3L,
  mt_mode = "2",
  chunk_size = NULL,
  verbose = "silent",
  progress = FALSE,
  parallel = FALSE,
  env_name = "blastr-blast-env"
) {
  n_seqs <- length(query_seqs)
  if (rlang::is_null(chunk_size)) {
    chunk_size <- auto_chunk_size(n_seqs, total_cores)
  }
  chunk_size <- max(1L, as.integer(chunk_size))

  run_verbose <- ifelse(
    verbose %in% c("cmd", "output", "full"),
    verbose,
    "silent"
  )

  # Share the (potentially large) query vector across daemons with
  # zero-copy shared memory when `mori` is available - but only for
  # local pools: remote daemons cannot map the host's shared memory.
  seqs_payload <- query_seqs
  if (
    isTRUE(parallel) &&
      rlang::is_installed("mori") &&
      isTRUE(daemons_are_local())
  ) {
    seqs_payload <- mori::share(query_seqs)
  }

  worker <- make_blast_worker(
    query_seqs = seqs_payload,
    db_path = db_path,
    num_alignments = num_alignments,
    num_threads = num_threads,
    blast_type = blast_type,
    perc_id = perc_id,
    perc_qcov_hsp = perc_qcov_hsp,
    mt_mode = mt_mode,
    verbose = run_verbose,
    env_name = env_name
  )

  run_chunks <- function(chunk_list) {
    if (isTRUE(parallel) && isTRUE(mirai::daemons_set())) {
      map_res <- mirai::mirai_map(.x = chunk_list, .f = worker)
      collect_options <- if (isTRUE(progress)) ".progress" else NULL
      return(mirai::collect_mirai(map_res, options = collect_options))
    }
    purrr::map(.x = chunk_list, .f = worker, .progress = progress)
  }

  seq_status <- rep(NA_integer_, n_seqs)
  seq_stderr <- rep(NA_character_, n_seqs)
  hits_list <- list()

  pending <- chunk_indices(seq_len(n_seqs), chunk_size)
  retry_count <- 0L

  while (length(pending) > 0L) {
    chunk_results <- run_chunks(pending)
    salvage_queue <- list()

    for (chunk_i in seq_along(chunk_results)) {
      idx <- pending[[chunk_i]]
      chunk_res <- chunk_results[[chunk_i]]

      if (isTRUE(mirai::is_error_value(chunk_res))) {
        # R-level failure on the worker (not a BLAST exit code).
        # Recorded with the documented sentinel `-1L` so NA-unsafe QC
        # filters cannot silently pass a query that never ran.
        if (isTRUE(length(idx) > 1L)) {
          salvage_queue <- c(salvage_queue, as.list(idx))
        } else {
          seq_status[idx] <- -1L
          seq_stderr[idx] <- paste(
            "R worker error:",
            as.character(chunk_res)
          )
        }
        next
      }

      if (isTRUE(chunk_res$status == 0L)) {
        seq_status[idx] <- 0L
        # Preserve the full chunk stderr for every member (per-query
        # BLAST warnings such as "Sequence contains no data" or
        # "Examining 5 or more matches is recommended" appear within
        # it). A retried query that later succeeds overwrites any stale
        # stderr from earlier failed attempts.
        seq_stderr[idx] <- if (isTRUE(nzchar(chunk_res$stderr))) {
          chunk_res$stderr
        } else {
          NA_character_
        }
        hits_tbl <- parse_blast_stdout(chunk_res$stdout)
        if (!rlang::is_null(hits_tbl)) {
          hits_list <- c(hits_list, list(hits_tbl))
        }
        next
      }

      # Non-zero BLAST exit status.
      if (isTRUE(length(idx) > 1L)) {
        # Salvage: re-run members individually within the same attempt to
        # rescue healthy queries and attribute the error precisely.
        salvage_queue <- c(salvage_queue, as.list(idx))
      } else {
        seq_status[idx] <- chunk_res$status
        seq_stderr[idx] <- chunk_res$stderr
      }
    }

    if (isTRUE(length(salvage_queue) > 0L)) {
      pending <- salvage_queue
      next
    }

    failed_idx <- which(!(seq_status %in% 0L))
    if (isTRUE(length(failed_idx) > 0L) && isTRUE(retry_count < retry_times)) {
      retry_count <- retry_count + 1L
      if (isTRUE(progress)) {
        cli::cli_inform(
          c(
            `i` = "Retrying {length(failed_idx)} failed quer{?y/ies}.",
            `*` = "Retry attempt {retry_count} of {retry_times}."
          )
        )
      }
      pending <- as.list(failed_idx)
      next
    }
    pending <- list()
  }

  hits_long <- purrr::list_rbind(hits_list)
  if (isTRUE(nrow(hits_long) > 0L)) {
    hits_long <- hits_long |>
      dplyr::distinct() |>
      dplyr::arrange(.data$seq_index) |>
      dplyr::mutate(
        res = dplyr::row_number(),
        .by = "seq_index"
      )
  }

  list(
    hits = hits_long,
    status = tibble::tibble(
      seq_index = seq_len(n_seqs),
      exit_code = seq_status,
      stderr = seq_stderr
    )
  )
}

#' Assemble the wide (one row per query) BLASTr result table
#'
#' @param query_seqs Character vector of unique sequences (row order).
#' @param engine_res Result list from `blast_engine()`.
#'
#' @keywords internal
#' @noRd
assemble_blast_wide <- function(query_seqs, engine_res) {
  hits_long <- engine_res$hits
  base_tbl <- tibble::tibble(
    seq_index = seq_along(query_seqs),
    `Sequence` = query_seqs
  )

  if (isTRUE(is.null(hits_long)) || isTRUE(nrow(hits_long) == 0L)) {
    # No hits anywhere: still guarantee the `1_` column group (all NA).
    na_group <- rlang::set_names(
      blast_wide_na_prototype,
      paste0("1_", colnames(blast_wide_na_prototype))
    )
    blast_res <- dplyr::bind_cols(
      dplyr::select(base_tbl, "Sequence"),
      na_group[rep(1L, nrow(base_tbl)), ]
    )
    return(blast_res)
  }

  wide_tbl <- hits_long |>
    dplyr::select(
      dplyr::all_of(c("seq_index", "res", blast_wide_value_cols))
    ) |>
    tidyr::pivot_wider(
      id_cols = "seq_index",
      names_from = "res",
      values_from = dplyr::all_of(blast_wide_value_cols),
      names_glue = "{res}_{.value}"
    )

  # Order hit columns by rank (1_, 2_, ...), each rank keeping the
  # canonical value-column order.
  max_res <- max(hits_long$res)
  ordered_cols <- as.vector(
    t(outer(
      seq_len(max_res),
      blast_wide_value_cols,
      FUN = \(res_rank, col_name) paste0(res_rank, "_", col_name)
    ))
  )
  ordered_cols <- ordered_cols[ordered_cols %in% colnames(wide_tbl)]

  blast_res <- base_tbl |>
    dplyr::left_join(wide_tbl, by = "seq_index") |>
    dplyr::select(
      dplyr::all_of(c("Sequence", ordered_cols))
    )

  return(blast_res)
}
