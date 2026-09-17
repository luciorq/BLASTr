# Benchmark parallel_blast() against a realistically sized reference
# database (NCBI preformatted 16S ribosomal RNA BLAST database, ~100 MB)
# for the BLASTr paper. Run interactively on the paper's hardware and
# record machine details alongside the results.
#
# Downloads go to the BLASTr cache directory and are reused on re-runs.

devtools::load_all()

db_cache_dir <- get_blastr_cache("benchmark_dbs")
fs::dir_create(db_cache_dir)
db_archive <- fs::path(db_cache_dir, "16S_ribosomal_RNA.tar.gz")
db_path <- fs::path(db_cache_dir, "16S_ribosomal_RNA")

if (!fs::file_exists(paste0(db_path, ".nsq"))) {
  curl::curl_download(
    "https://ftp.ncbi.nlm.nih.gov/blast/db/16S_ribosomal_RNA.tar.gz",
    db_archive,
    quiet = FALSE
  )
  utils::untar(db_archive, exdir = db_cache_dir)
}

# Sample query sequences from the database itself: export entries with
# blastdbcmd, then take 150 bp windows (guaranteed hits, all unique).
export_res <- condathis::run_bin(
  "blastdbcmd",
  "-db",
  db_path,
  "-entry",
  "all",
  "-outfmt",
  "%s",
  env_name = "blastr-blast-env",
  verbose = "silent"
)
db_seqs <- strsplit(export_res$stdout, "\n")[[1]]
set.seed(20260811)
db_seqs <- sample(db_seqs, 500)
queries <- unique(vapply(
  db_seqs,
  function(s) substr(s, 1, 150),
  "",
  USE.NAMES = FALSE
))
cat("queries:", length(queries), "\n")

bench_grid <- expand.grid(
  total_cores = c(1L, 4L, 8L),
  chunk_size = c(1L, NA_integer_), # NA = automatic batching
  stringsAsFactors = FALSE
)

bench_results <- purrr::pmap(
  bench_grid,
  function(total_cores, chunk_size) {
    chunk_arg <- if (is.na(chunk_size)) NULL else chunk_size
    timing <- system.time(
      res <- parallel_blast(
        query_seqs = queries,
        db_path = db_path,
        total_cores = total_cores,
        chunk_size = chunk_arg,
        retry_times = 0,
        verbose = "silent"
      )
    )
    tibble::tibble(
      total_cores = total_cores,
      chunk_size = ifelse(is.na(chunk_size), "auto", as.character(chunk_size)),
      n_queries = length(queries),
      elapsed_s = timing[["elapsed"]],
      n_rows = nrow(res)
    )
  }
) |>
  purrr::list_rbind()

print(bench_results)
readr::write_csv(
  bench_results,
  fs::path("data-raw", "benchmark_16S_results.csv")
)
