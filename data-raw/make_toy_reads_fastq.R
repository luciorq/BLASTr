# Builds `inst/extdata/toy_reads.fastq.gz`, a small synthetic amplicon
# library used by the `search_primers_on_fq()` examples, tests and the
# vignette. Deterministic (fixed seed). Composition (300 reads, 150 bp):
#   * reads   1-150: MiFish-U forward primer at the 5' end, forward strand
#   * reads 151-250: the same construct, reverse-complemented (reverse
#                    strand): found only when both strands are searched
#   * reads 251-300: one concrete instance of the degenerate COI primer
#                    mlCOIintF at the 5' end, forward strand
set.seed(20260918)

mifish_f <- "GTCGGTAAAACTCGTGCCAGC"
# mlCOIintF (Leray et al. 2013): GGWACWGGWTGAACWGTWTAYCCYCC
coi_degenerate <- "GGWACWGGWTGAACWGTWTAYCCYCC"
iupac_choices <- list(W = c("A", "T"), Y = c("C", "T"))

random_dna <- function(n) {
  paste(sample(c("A", "C", "G", "T"), n, replace = TRUE), collapse = "")
}
instantiate <- function(primer) {
  bases <- strsplit(primer, "")[[1]]
  paste(
    vapply(
      bases,
      \(b) if (b %in% names(iupac_choices)) sample(iupac_choices[[b]], 1) else b,
      character(1)
    ),
    collapse = ""
  )
}
reverse_complement <- function(x) {
  chartr("ACGT", "TGCA", paste(rev(strsplit(x, "")[[1]]), collapse = ""))
}
read_len <- 150L

fwd_reads <- vapply(
  seq_len(150),
  \(i) paste0(mifish_f, random_dna(read_len - nchar(mifish_f))),
  character(1)
)
rev_reads <- vapply(
  seq_len(100),
  \(i) reverse_complement(paste0(mifish_f, random_dna(read_len - nchar(mifish_f)))),
  character(1)
)
coi_reads <- vapply(
  seq_len(50),
  \(i) {
    primer_instance <- instantiate(coi_degenerate)
    paste0(primer_instance, random_dna(read_len - nchar(primer_instance)))
  },
  character(1)
)
reads <- c(fwd_reads, rev_reads, coi_reads)

fastq_lines <- unlist(lapply(seq_along(reads), function(i) {
  c(paste0("@toy_read_", i), reads[i], "+", strrep("I", nchar(reads[i])))
}))
out_path <- fs::path("inst", "extdata", "toy_reads.fastq.gz")
con <- gzfile(out_path, open = "wb")
writeLines(fastq_lines, con)
close(con)
cat("Wrote", out_path, "with", length(reads), "reads\n")
