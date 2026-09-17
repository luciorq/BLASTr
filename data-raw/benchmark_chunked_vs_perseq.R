# Benchmark: batched (chunked) BLAST engine vs legacy per-sequence runs.
#
# Reference numbers (2026-08-11, Linux x86_64, BLAST 2.16, minimal db,
# 200 unique 100 bp queries):
#   per-seq serial (old behavior)       131.65s
#   batched serial (auto chunk)           2.92s   (~45x)
#   per-seq 4 cores (old parallel)       34.44s
#   batched 4 cores (new default)         4.50s
# All four modes produce identical result tables.
# NOTE: on a tiny database with a ~3s total workload, daemon dispatch
# overhead makes batched-parallel slightly slower than batched-serial;
# with real-world databases (nt/core_nt) the database-load amortization
# and parallelism gains compound instead.

devtools::load_all()

db_path <- fs::file_temp("bench_db_")
make_blast_db(
  fasta_path = fs::path_package(
    "BLASTr", "extdata", "minimal_db_blast",
    ext = "fasta"
  ),
  db_path = db_path,
  db_type = "nucl",
  verbose = "silent"
)

# Build a realistic unique query set: sliding windows over the reference
# sequences (guaranteed hits, all unique).
ref_seqs <- parse_fasta(
  fs::path_package("BLASTr", "extdata", "minimal_db_blast", ext = "fasta")
)
ref_seqs <- ref_seqs[nchar(ref_seqs) >= 120]
windows <- unlist(lapply(ref_seqs, function(s) {
  starts <- seq(1, max(1, nchar(s) - 100), by = 3)
  vapply(starts, function(i) substr(s, i, i + 99), "")
}))
windows <- windows[nchar(windows) == 100]
queries <- unique(windows)
if (length(queries) > 200) queries <- queries[seq_len(200)]
cat("queries:", length(queries), "\n")

run_one <- function(label, ...) {
  t <- system.time(
    res <- parallel_blast(
      query_seqs = queries, db_path = db_path,
      retry_times = 0, verbose = "silent", ...
    )
  )
  cat(sprintf("%-34s %7.2fs  (rows=%d)\n", label, t[["elapsed"]], nrow(res)))
  invisible(res)
}

r_old <- run_one("per-seq serial (old behavior)", chunk_size = 1)
r_new <- run_one("batched serial (auto chunk)")
r_par1 <- run_one("per-seq 4 cores (old parallel)", chunk_size = 1, total_cores = 4)
r_par <- run_one("batched 4 cores (new default)", total_cores = 4)

stopifnot(
  isTRUE(all.equal(
    as.data.frame(r_old), as.data.frame(r_new),
    check.attributes = FALSE
  )),
  isTRUE(all.equal(
    as.data.frame(r_new), as.data.frame(r_par),
    check.attributes = FALSE
  ))
)
