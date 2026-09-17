# Development notes (kept as comments so package-wide tooling can parse
# this file).

# source("~/prjcts/ecomol/R/extract_taxonomy_name.R")
# extract_taxonomy_name(organism_name = "Mazama gouazoubira") %>% View()

# NOTE (translated): update the BLASTr function so that it can search by
# Sci_name, since only that may have had its taxonomy corrected.
# -> Addressed in 0.2.0: `get_tax_by_name()` searches NCBI Taxonomy by
#    organism name via `esearch | efetch`.
