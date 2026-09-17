# Internal single-query wrapper around the shared BLAST engine worker.
# Kept for backwards compatibility with internal callers and tests;
# returns the raw process result without raising on non-zero exit status.
blast_cmd <- function(
  query_str,
  db_path,
  num_alignments = "4",
  num_threads = "1",
  blast_type = "blastn",
  perc_id = "80",
  perc_qcov_hsp = "80",
  mt_mode = "2",
  verbose = "silent",
  env_name = "blastr-blast-env"
) {
  seqs_clean <- stringr::str_replace_all(query_str, "\\s", "")
  worker <- make_blast_worker(
    query_seqs = seqs_clean,
    db_path = db_path,
    num_alignments = num_alignments,
    num_threads = num_threads,
    blast_type = blast_type,
    perc_id = perc_id,
    perc_qcov_hsp = perc_qcov_hsp,
    mt_mode = mt_mode,
    verbose = verbose,
    env_name = env_name
  )
  worker_res <- worker(seq_along(seqs_clean))
  return(worker_res)
}
