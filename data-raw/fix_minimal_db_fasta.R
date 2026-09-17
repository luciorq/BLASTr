# Rebuild inst/extdata/minimal_db_blast.fasta as a well-formed FASTA and
# generate the matching inst/extdata/minimal_db_blast.txt taxid map.
#
# Defect fixed (2026-08-11): one line held three concatenated `>` headers
# (KX381515.1 / KX381584.1 / KX381638.1) followed by a single sequence;
# the two folded-in headers are dropped, keeping KX381515.1 with its own
# description. All sequences are preserved byte-identical and wrapped at
# 80 columns. Taxonomy IDs come from the curated map previously stored
# as inst/extdata/shortest_minimal_db_BLASTr.txt (now in data-raw/),
# converted from `lcl|<acc>_<v>` to `<acc>.<v>` identifiers.

fasta_path <- fs::path("inst", "extdata", "minimal_db_blast.fasta")
map_source_path <- fs::path("data-raw", "shortest_minimal_db_BLASTr.txt")
map_out_path <- fs::path("inst", "extdata", "minimal_db_blast.txt")

lines <- readr::read_lines(fasta_path)

records <- list()
current_header <- NULL
current_seq <- character(0L)
for (line in lines) {
  if (startsWith(line, ">")) {
    if (!is.null(current_header)) {
      records[[length(records) + 1L]] <- list(
        header = current_header,
        seq = paste(current_seq, collapse = "")
      )
    }
    # Keep only the first header when multiple are concatenated on one
    # line ("... >KX381584.1 ..." folded into the title).
    current_header <- paste0(">", sub(" *>.*$", "", substring(line, 2L)))
    current_seq <- character(0L)
  } else {
    current_seq <- c(current_seq, gsub("\\s", "", line))
  }
}
records[[length(records) + 1L]] <- list(
  header = current_header,
  seq = paste(current_seq, collapse = "")
)

stopifnot(length(records) == 47L)
stopifnot(all(vapply(records, function(r) nzchar(r$seq), TRUE)))

ids <- vapply(
  records,
  function(r) sub("^>(\\S+).*$", "\\1", r$header),
  ""
)
stopifnot(!anyDuplicated(ids))

wrap_seq <- function(seq_string, width = 80L) {
  starts <- seq(1L, nchar(seq_string), by = width)
  vapply(
    starts,
    function(i) substr(seq_string, i, i + width - 1L),
    ""
  )
}

out_lines <- unlist(lapply(records, function(r) {
  c(r$header, wrap_seq(r$seq))
}))
readr::write_lines(out_lines, fasta_path)

# Taxid map: `<SequenceId> <TaxonomyId>` per line, ids matching the FASTA.
map_lines <- readr::read_lines(map_source_path)
map_ids <- sub("^lcl\\|", "", sub(" .*$", "", map_lines))
map_ids <- sub("_([0-9]+)$", ".\\1", map_ids)
map_taxids <- sub("^\\S+ +", "", map_lines)
stopifnot(setequal(map_ids, ids), !anyDuplicated(map_ids))
readr::write_lines(paste(map_ids, map_taxids), map_out_path)

cat("records:", length(records), "\n")
cat("taxid map entries:", length(map_ids), "\n")
