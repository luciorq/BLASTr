# Changelog

## BLASTr 0.2.0

Development Changelog:
[dev](https://github.com/heronoh/BLASTr/compare/v0.1.7...v0.2.0)

### Added

- [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  now batches unique query sequences into multi-record FASTA chunks, so
  each BLAST+ process searches many queries at once. This amortizes
  process startup and database index loading and is dramatically faster
  on large reference databases. Chunk size is controlled by the new
  `chunk_size` argument (default: automatic).

- Parallel chunks are dispatched with
  [`mirai::mirai_map()`](https://mirai.r-lib.org/reference/mirai_map.html).
  When the suggested `mori` package is installed, the query set is
  placed in OS shared memory
  ([`mori::share()`](https://rdrr.io/pkg/mori/man/share.html)) so
  parallel workers receive a zero-copy reference instead of a full copy
  of the sequences.

- When a batch fails, its member sequences are automatically re-run
  individually (salvage), so healthy queries keep their results and
  errors are attributed to the offending sequences. Per-query BLAST
  warnings inside successful batches (e.g. empty records) are captured
  in
  [`exit_codes()`](https://heronoh.github.io/BLASTr/reference/exit_codes.md)
  output.

- Taxonomy lookups no longer depend on Entrez Direct.
  [`get_tax_by_taxID()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_taxID.md),
  [`get_tax_by_name()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_name.md),
  and
  [`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md)
  now query the NCBI E-utilities (`efetch.fcgi` / `esearch.fcgi`)
  directly over HTTPS with a small internal client (`curl` + `xml2`): no
  conda environment, no Perl, and taxonomy works on Windows. The client
  sends `tool` (and an optional `options(blastr.ncbi.email = )`), honors
  `NCBI_API_KEY`, throttles to the NCBI per-second limits (shared across
  the whole worker pool when `total_cores > 1`), and retries HTTP
  429/5xx and network errors with backoff. Tax IDs unknown to NCBI are
  reported once and no longer retried
  ([`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md)
  on one unknown ID took ~40 s before; it now takes one request). The
  `env_name` argument of the three functions is deprecated and ignored.
  The test suite validates the client against the real Entrez Direct
  tools (`test-eutils-vs-edirect.R`), so results are byte-for-byte the
  same XML NCBI serves to `efetch`. As a consequence the package no
  longer needs the development version of `condathis`: the CRAN release
  (`>= 0.1.4`) is sufficient.

- [`get_tax_by_name()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_name.md)
  was rewritten and now works: it searches NCBI Taxonomy (`esearch`) and
  fetches the matching records (`efetch`), returning the same schema as
  [`get_tax_by_taxID()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_taxID.md)
  plus a `query_name` column.

- Taxonomy results now include a `Domain (NCBI)` column: NCBI Taxonomy
  replaced the `superkingdom` rank with `domain` in its 2024/2025
  restructure. Both ranks are parsed, so results are correct for current
  and archived NCBI data. (Previously `Superkingdom (NCBI)` was silently
  `NA` with current NCBI data.)

- [`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md)
  now batches Tax IDs (up to `batch_size` per `efetch` request, default
  100), dramatically reducing the number of NCBI requests, and documents
  NCBI rate limits (`NCBI_API_KEY` is sent with every request when set).

- [`make_blast_db()`](https://heronoh.github.io/BLASTr/reference/make_blast_db.md)
  validates its input files and gained clearer errors; `db_path` may be
  omitted to create the database alongside the input FASTA.

- New exported
  [`search_primers_on_fq()`](https://heronoh.github.io/BLASTr/reference/search_primers_on_fq.md):
  counts, per FASTQ file and primer, how many reads carry the (IUPAC
  degenerate) primer, with the percentage of the library - a quick
  amplicon QC. The implementation is pure R (no external tool): files
  are streamed in chunks (`chunk_size` reads at a time, plain or
  gzip-compressed), primers are expanded into regular expressions
  (reported in the `parsed_primer` column), matching is
  case-insensitive, and both strands are searched by default
  (`only_positive_strand = FALSE`). It replaces a non-portable internal
  prototype that shelled out to `grep`/`zgrep` and miscounted reads
  whose quality line starts with `@`; malformed FASTQ records now raise
  a classed error (`blastr_fastq_malformed`). A small synthetic library
  (`inst/extdata/toy_reads.fastq.gz`) ships with the package for
  runnable examples and the vignette.

- The conda package specifications used to install command-line tools
  can now be overridden via options (`blastr.conda.blast`,
  `blastr.conda.blast_channels`, `blastr.conda.blast_fallback`,
  `blastr.conda.fallback_channels`, `blastr.conda.channels`), useful for
  testing candidate BLAST+ builds.

- The version-pin update policy for the bundled command-line tools is
  now defined and documented (see
  [`?install_dependencies`](https://heronoh.github.io/BLASTr/reference/install_dependencies.md)
  and `CONTRIBUTING.md`): pins are exact upstream releases (currently
  BLAST+ 2.17.0, the package’s only external tool) kept in a single
  source of truth, bumped only in minor releases with a NEWS record, and
  never upgraded implicitly - `install_dependencies(force = TRUE)` is
  the supported upgrade path.

- BLAST+ is now installed from the `blast` package on the
  `https://prefix.dev/universe` channel, built with a single toolchain
  for linux-64, linux-aarch64, osx-64, osx-arm64 and win-64. This
  upgrades the pinned BLAST+ release from 2.16 to 2.17.0 and makes the
  BLAST+ family
  ([`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md),
  [`make_blast_db()`](https://heronoh.github.io/BLASTr/reference/make_blast_db.md),
  [`get_fasta_header()`](https://heronoh.github.io/BLASTr/reference/get_fasta_header.md),
  …) available on Windows, which is now part of the CI matrix. With
  taxonomy over HTTPS and primer search in R, BLAST+ is the only
  external tool, so the whole package now works on Linux, macOS and
  Windows. Existing environments are not upgraded implicitly; run
  `install_dependencies(force = TRUE)` to move to 2.17.0.

- Environment installation is hardened and now supports fallback package
  sources: when the primary specification cannot be installed, the
  BLAST+ family automatically falls back to the bioconda build of the
  same BLAST+ release. Primary channels and fallbacks are overridable
  via the `blastr.conda.blast_channels`, `blastr.conda.blast_fallback`
  and `blastr.conda.fallback_channels` options.

- Installed tools are now validated (version probe) after environment
  creation and once per session for existing environments; a stale or
  corrupted environment is rebuilt once automatically, and installation
  failures raise classed errors (`blastr_env_install_error`,
  `blastr_env_validation_error`) carrying the underlying error.

- `blast_type` is now validated against the supported BLAST+ engines.

- [`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md)
  waits with an increasing backoff between retry rounds (politeness
  towards NCBI; gives transient failures time to clear).

- [`get_fasta_header()`](https://heronoh.github.io/BLASTr/reference/get_fasta_header.md)
  returns a character vector (one element per requested ID) instead of a
  single newline-embedded string.

- Unparsed (long) taxonomy output now includes the queried taxon’s own
  rank entry (`LineageEx` only contains ancestors), so e.g. a
  genus-level Tax ID now fills its own `Genus (NCBI)` column.

- The packaged example database was repaired and extended: the malformed
  record in `inst/extdata/minimal_db_blast.fasta` (three FASTA headers
  concatenated on one line) was fixed, and a matching taxid map
  (`inst/extdata/minimal_db_blast.txt`, one `<SequenceId> <TaxonomyId>`
  pair per line) is now shipped, so the packaged example exercises the
  full pipeline - database build with `-taxid_map`, BLAST hits with real
  `staxid` values, and taxonomy retrieval.

### Fixed

- Fixes from the pre-release code review (all verified with regression
  tests):

  - BLAST tabular output is parsed with quoting and comment handling
    disabled: subject titles containing `#` were silently truncated and
    titles starting with `"` could crash the R session.
  - Results always carry the `1_` hit-column group (`1_subject`,
    `1_staxid`, …) even when no query has hits, restoring the 0.1.7
    column guarantee.
  - [`get_blast_results()`](https://heronoh.github.io/BLASTr/reference/get_blast_results.md)
    again fails loudly (classed error `blastr_run_blast_error`) when
    every query fails - e.g. a mistyped `db_path` - instead of returning
    a hits-free tibble indistinguishable from “no hits”.
  - A pre-existing
    [`mirai::daemons()`](https://mirai.r-lib.org/reference/daemons.html)
    pool is now adopted even at the default `total_cores = 1`
    (previously everything silently ran serially while the pool idled),
    and chunk sizing accounts for the adopted pool size.
  - Merged/deprecated NCBI Tax IDs are resolved through `<AkaTaxIds>`:
    previously they were re-fetched every retry round and finally
    misreported as unretrievable.
  - [`exit_codes()`](https://heronoh.github.io/BLASTr/reference/exit_codes.md)
    reports R-level worker failures with the documented sentinel `-1`
    (previously `NA`, which NA-unsafe QC filters silently passed), and
    `stderr` again carries the full BLAST diagnostic output - including
    untagged warnings such as “Examining 5 or more matches is
    recommended” - for every query in a batch. Stale stderr from failed
    attempts is overwritten when a retry succeeds.
  - [`mori::share()`](https://rdrr.io/pkg/mori/man/share.html) is only
    used for local daemon pools: remote workers cannot map the host’s
    shared memory (every chunk would fail).
  - [`search_primers_on_fq()`](https://heronoh.github.io/BLASTr/reference/search_primers_on_fq.md)
    searches every primer even when names are duplicated (previously
    later same-named primers were silently skipped; duplicates are now
    renamed via
    [`make.unique()`](https://rdrr.io/r/base/make.unique.html) with a
    warning).
  - [`get_fasta_header()`](https://heronoh.github.io/BLASTr/reference/get_fasta_header.md)
    returns titles aligned to (and named by) the requested IDs instead
    of relying on database output order.
  - [`get_tax_by_name()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_name.md)
    resolves names to Tax IDs with lightweight `uid` fetches and
    retrieves all lineages in a single batched, retried request
    (previously two full serial NCBI round-trips per name with no
    retries).
  - [`run_blast()`](https://heronoh.github.io/BLASTr/reference/run_blast.md)’s
    raw `stdout` format (15 fields, `stitle` appended, `BLASTrQ<i>`
    query IDs) is now documented.

- [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  no longer duplicates result rows for queries that failed and then
  succeeded on retry.

- Multiple Tax IDs passed to
  [`get_tax_by_taxID()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_taxID.md)
  are now fetched in a single batched request and matched back through
  the XML `TaxId` element. Previously, vector input produced malformed
  `efetch` calls and results could be attributed to the wrong Tax ID
  when any ID was missing from the response.

- Malformed XML responses from NCBI are now detected and handled
  (previously the integrity check was inoperative and malformed XML
  crashed
  [`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md)).

- [`run_blast()`](https://heronoh.github.io/BLASTr/reference/run_blast.md)
  now writes each sequence as its own FASTA record. Previously, multiple
  sequences were silently concatenated into a single chimeric query.
  Temporary query files are now cleaned up.

- `parallel_blast_old()` (deprecated since 0.1.7, and broken by the
  0.1.7 argument rename) has been removed. Use
  [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md),
  which returns the same output format. Note the error-handling
  difference: failed queries no longer raise an error - they are
  recorded in
  [`exit_codes()`](https://heronoh.github.io/BLASTr/reference/exit_codes.md) -
  and empty input raises a classed error.

- [`parse_fasta()`](https://heronoh.github.io/BLASTr/reference/parse_fasta.md)
  no longer requires R \>= 4.5 and its error message now shows the
  actual file path.

- [`make_blast_db()`](https://heronoh.github.io/BLASTr/reference/make_blast_db.md)
  no longer prints debug output regardless of `verbose`, and no longer
  requires the `taxid_map` file to share the FASTA file’s base name (a
  constraint `makeblastdb` itself does not have).

- Messages in taxonomy functions now respect `verbose = "silent"`.

- Daemons created internally are reliably torn down (previously leaked
  on error in
  [`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md));
  pre-existing
  [`mirai::daemons()`](https://mirai.r-lib.org/reference/daemons.html)
  pools are now respected and reused instead of raising an error.

- `withr` and `tools` are now correctly declared in `Imports`
  (previously `withr` was in `Suggests` while being required
  unconditionally at runtime).

### Changed

- The misspelled `indentity` output column is renamed to `identity`
  (affects the `<n>_identity` wide columns).

- [`get_blast_results()`](https://heronoh.github.io/BLASTr/reference/get_blast_results.md)
  now shares the same engine as
  [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  and returns the identical format (including `subject header` sourced
  from BLAST `stitle` instead of separate `blastdbcmd` calls, and the
  `BLASTr_metadata` attribute).

- Queries consisting only of whitespace, empty strings, or `NA` are
  dropped with a warning; if nothing remains, a classed error is raised.

## BLASTr 0.1.7

Release Date: 2025-11-04

Development Changelog:
[0.1.7](https://github.com/heronoh/BLASTr/compare/v0.1.6...v0.1.7)

### Added

- New `retry_times` argument in
  [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  to specify the number of retries for failed BLAST jobs. Defaults to 3
  times.

- New `verbose = "progress"` in
  [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  to show a progress bar for the BLAST jobs.

- New
  [`get_blastr_cache()`](https://heronoh.github.io/BLASTr/reference/get_blastr_cache.md)
  for printing the directory used as cache for `BLASTr`.

- The previous version of
  [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  is now available as `parallel_blast_old()`. It is kept for backward
  compatibility, but users are encouraged to switch to the new
  [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  implementation.

- New `exit_codes` function to extract exit codes and error message from
  internal BLAST runs.

### Changed

- [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  will not throw errors immediately when a BLAST job fails. Instead, it
  will log the error and continue with the remaining jobs.

- [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  output has a new attributes data frame with columns:

  - `query_seq`: The query sequence that was processed.
  - `exit_code`: The exit code of the BLAST command.
  - `stderr`: The standard error output from the BLAST command.

- [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  will automatically retry failed BLAST jobs up to 3 times (or the value
  of `retry_times`) before giving up.

- Argument `asvs` is renamed to `query_seqs` in
  [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md).

- Arguments `asvs`, `out_file` and `out_RDS` in
  [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  are now deprecated.

## BLASTr 0.1.6

Release Date: 2025-10-28

Development Changelog:
[0.1.6](https://github.com/heronoh/BLASTr/compare/v0.1.5...v0.1.6)

### Fixed

- Fix hard coded `num_threads = 1L` in
  [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md).
  [`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
  now correctly uses the user provided `num_threads` argument.

- Fix parallel functions not using the the custom compute profile.
  [`purrr::map`](https://purrr.tidyverse.org/reference/map.html) do not
  have an argument for specifying the `mirai` `.compute` argument
  correctly. Now all parallel functions use the “default” mirai compute
  profile `.compute = NULL`.

- Fix
  [`get_tax_by_taxID()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_taxID.md)
  when multiple tax IDs are provided.

- Fix
  [`parse_fasta()`](https://heronoh.github.io/BLASTr/reference/parse_fasta.md)
  concatenate lines for multiline FASTA.

## BLASTr 0.1.5

Release Date: 2025-08-27

Development Changelog:
[0.1.5](https://github.com/heronoh/BLASTr/compare/v0.1.4...v0.1.5)

### Added

- New parallel framework based on native `purrr` functions, using
  `mirai` and `carrier` in the background.

- New
  [`make_blast_db()`](https://heronoh.github.io/BLASTr/reference/make_blast_db.md)
  function to create custom BLAST databases.

### Changed

- Internal `entrez-direct` version bump to `24.0`.

- The internal environments used by BLASTr have been renamed to
  `blastr-blast-env` and `blastr-entrez-env`.

- Remove of the `furrr` based functions in favor of the new `purrr`
  native parallel.

- All [`options()`](https://rdrr.io/r/base/options.html) based
  parameters have been removed in favor of explicit arguments in the
  functions.

## BLASTr 0.1.4

### Changed

- All functions have better defaults and less mandatory arguments.

### Fixed

- Fix progress bars when parallel processing is used.

## BLASTr 0.1.3

### Added

- Refactor handling of internal errors.

- `shell_exec` is not available anymore.

## BLASTr 0.1.2

### Added

- New
  [`install_dependencies()`](https://heronoh.github.io/BLASTr/reference/install_dependencies.md)
  automatically create environments.

- Initial support for `condathis` for managing dependency installation.
