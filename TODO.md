# BLASTr — Review Findings & Task Tracker

> Generated from a full-package review (2026-08-11); implementation of the
> 0.2.0 overhaul completed the same day. Focus: correctness and performance
> ahead of public release and the companion analysis paper.
> Status legend: `[ ]` open · `[x]` done · `[~]` in progress · `[!]` decision needed

## Verification status (2026-09-03, production-readiness pass)

- `devtools::test()`: **all passing, no skips** (all three conda envs
  built from scratch in the hermetic test sandbox).
- `R CMD check --as-cran` (with vignette rebuild and tests):
  **Status OK — 0 errors, 0 warnings, 0 notes.**
- `devtools::spell_check()`: clean. `urlchecker`: clean except the two
  NEWS compare links pending tags (J7).
- `pkgdown::build_site()`: builds fully (reference index, executed
  articles, search) with zero problems. Note: pkgdown renders the root
  `TODO.md` into the public site as `TODO.html` — decide whether that is
  desired before deploying.
- Code style: `styler` + `air format` (justfile order) applied to `R/`
  and `tests/`; re-runs produce zero changes.
- Benchmark (200 unique 100 bp queries, minimal db, Linux x86_64):
  per-seq serial 131.7s → **batched serial 2.9s (~45x)**; per-seq 4-core
  34.4s → batched 4-core 4.5s. Identical results in all modes.
  Script: `data-raw/benchmark_chunked_vs_perseq.R`.

## A. Release blockers (regressions from recent commits)

- [x] **A1. `make_blast_db()` lost `db_path`** — restored as an optional
  argument (`NULL` = alongside input FASTA); input validation added.
- [x] **A2. `asv → query_seqs` rename half-done** — `asvs = deprecated()`
  shim restored in `parallel_blast()`; `parallel_blast_old()` fixed by
  delegating to `parallel_blast()`; tests updated; docs regenerated
  (codoc warnings gone).
- [x] **A3. `make_blast_db()` debug leftovers** — `print()`/`message()`
  removed; command echo now gated behind `verbose = "cmd"/"full"`;
  `cli_abort()` with classed errors.
- [x] **A4. taxid_map "same radical" check** — dropped (constraint does
  not exist in `makeblastdb`); replaced with file-existence +
  `parse_seqids` compatibility checks.
- [x] **A5. Test suite cannot run** — setup works again;
  `Config/testthat/parallel: false` (conda env creation is not
  concurrency-safe across testthat workers).

## B. Runtime bugs

- [x] **B1. Retry duplication in `parallel_blast()`** — new engine tracks
  per-sequence status; retried successes appear exactly once
  (regression test added).
- [x] **B2. `get_tax_by_name()` unusable** — rewritten on the verified
  `esearch → efetch` stdin pipe (`condathis::run(stdin = "|", input =)`);
  `esearch`/`esummary`/`elink`/`xtract` added to `check_cmd()`; returns
  the `get_tax_by_taxID()` schema plus `query_name`; live-tested.
- [x] **B3. Dead XML-integrity check** — parser now `tryCatch`es
  `read_xml()` properly and returns an empty typed tibble on failure.
- [x] **B4. Multi-taxid fetch broken/fragile** — IDs joined with commas
  into a single `-id` value; records mapped back via the XML `<TaxId>`
  element (NCBI's response order does **not** match request order —
  verified live; test added).
- [x] **B5. `run_blast()` concatenated multiple sequences into one
  query** — every sequence is now its own FASTA record with a generated
  `BLASTrQ<i>` header; temp files cleaned via `withr::local_tempfile()`;
  test added.
- [x] **B6. `parse_fasta()` message interpolation** — fixed.
- [x] **B7. `search_primer_on_fq.R`** — moved to `data-raw/` pending a
  portable rewrite (candidate backend: seqkit via condathis).
- [x] **B8. Messages ignoring `verbose`** — all taxonomy chatter now
  respects `verbose = "silent"`.
- [x] **B9. Daemon lifecycle** — pools created internally are torn down
  via `withr::defer()` on every path; pre-existing `mirai::daemons()`
  pools are detected (`mirai::daemons_set()`) and reused instead of
  erroring.

## C. Dependency / metadata correctness

- [x] **C1. `withr` moved Suggests → Imports.**
- [x] **C2. `tools` added to Imports.**
- [x] **C3. `declare(carrier::crate)` (R ≥ 4.5 only)** — removed;
  `@importFrom carrier crate` in the package doc instead.
- [x] **C4. DESCRIPTION typo** — fixed.
- [x] **C5. NEWS vs code `retry_times` default** — corrected (3).
- [x] **C6. `.Rbuildignore` `README_files` pattern** — fixed; `TODO.md`
  also ignored.
- [x] **C7. Dead `check_connection()`** — removed.
- [x] **C8. `inst/CITATION`** — added (update with the article DOI when
  the paper is out).
- [x] **C9/C10/C11. Stale man pages, ghost params, wrong titles** —
  regenerated/rewritten.

## D. Performance / architecture (mirai + mori)

- [x] **D1. Batched multi-record FASTA chunks** (`R/blast_engine.R`):
  `>BLASTrQ<i>` headers, exact `qseqid`-based mapping back to input.
- [x] **D2. `mirai::mirai_map()` dispatch** with `collect_mirai()`
  (`.progress` collection), `carrier::crate()` workers (self-contained;
  no package namespace needed on daemons), per-element error values.
- [x] **D3. `mori::share()`** — query vector placed in shared memory when
  `mori` is installed (Suggests); zero-copy reads on workers; graceful
  fallback otherwise.
- [x] **D4. Salvage + retry** — failed chunks re-run per-sequence within
  the same attempt (verified live: BLAST+ itself salvages malformed
  records inside a batch with exit 0 + per-query warnings, which the
  engine parses and attributes via `parse_blast_warnings()`); failing
  singletons retried up to `retry_times`.
- [x] **D5. Respect pre-existing daemons** (see B9).
- [x] **D6. `mt_mode`** — verified `-mt_mode 2` is accepted by BLAST
  2.16; argument kept and interaction documented.
- [x] **D7. Wide-format assembly** — column order computed
  programmatically for any `num_alignments` (no more hardcoded `1_`–`6_`).
- [x] **D8. Per-hit `blastdbcmd` calls eliminated** — `subject header`
  comes from `stitle` in the single outfmt; `get_fasta_header()` also
  accepts a vector of IDs now.
- [x] **D9. NCBI etiquette** — taxids batched (default 100/request);
  `NCBI_API_KEY` documented (honored automatically by Entrez Direct);
  rate limits documented.
- [x] **D10. Benchmark** — see verification status above.

## E. Output/API polish (paper-facing)

- [x] **E1. `indentity` → `identity`** (wide columns now
  `<n>_identity`). Downstream analysis code referencing `_indentity`
  columns must be updated.
- [x] **E2/E5. Version 0.2.0 + NEWS** — full changelog written.
- [x] **E3. Fate of `parallel_blast_old()`** — removed on 2026-08-12
  (owner decision; see I1).
- [x] **E4. Vignette** — real intro written (install → make db →
  parallel_blast → exit_codes → taxonomy → performance notes).

## F. Windows / cross-OS

- [~] **F1. Windows conda packages** — conda specs centralized in
  `conda_pkg_spec()` (`R/check_cmd.R`), keyed on OS with a clear
  Windows TODO marker; currently fails on Windows with an informative
  classed error. **Owner plan:** slot in the dedicated Windows BLAST
  conda package spec once released.
- [x] **F2. Env staleness** — `install_dependencies(force = TRUE)`
  documented as the upgrade path (vignette + README).
- [ ] **F3. Re-enable Windows CI** once the Windows package exists.

## G. Remaining / follow-ups

- [x] **G1. `inst/extdata/minimal_db_blast.fasta` repaired** (the defect
  was one line holding three concatenated `>` headers — `KX381515.1` /
  `KX381584.1` / `KX381638.1` — folded into a single record's title;
  fixed keeping `KX381515.1` with its own description, sequences
  byte-identical, wrapped at 80 columns; script:
  `data-raw/fix_minimal_db_fasta.R`). A matching taxid map is now
  packaged as `inst/extdata/minimal_db_blast.txt` (47/47 accessions,
  derived from the curated `shortest_minimal_db_BLASTr.txt`, which moved
  to `data-raw/` where its own FASTA lives). The shared test database is
  built with the map, so the whole suite exercises the `staxid` path;
  the formerly-skipped taxid test is now a real end-to-end assertion
  (build → blast → `staxid` → `parallel_get_tax()` round trip).
  Verified: output shape unchanged (6 × 57), suite green with **no
  skips**.
- [ ] **G2. Rewrite `search_primers_on_fq()`** portably (seqkit grep via
  condathis) and re-export.
- [ ] **G3. Update pinned tool versions deliberately** (blast==2.16,
  entrez-direct==24.0) and document the policy.
- [ ] **G4. `parallel_get_tax(parse_result = FALSE)`** returns lineage
  rows without the query linkage beyond `query_taxID` — consider adding
  the taxon's own rank row for completeness.
- [ ] **G5. Benchmark against a realistically sized database** for the
  paper (nt/core_nt subset), including `num_threads`/`mt_mode`
  interaction, and record hardware details.
- [ ] **G6. Downstream code migration note**: `1_indentity` →
  `1_identity`, taxonomy tables gained `Domain (NCBI)` (14 cols), and
  `get_blast_results()` now returns the `parallel_blast()` format.

## H. Post-review round 2 (2026-08-11, while Windows packages are in progress)

- [x] **H1. Conda spec overrides via options** (`blastr.conda.blast`,
  `blastr.conda.entrez`, `blastr.conda.seqkit`, `blastr.conda.channels`)
  — lets the Windows candidate packages be tested with
  `options(blastr.conda.blast = "<channel>::<pkg>==<ver>")` and unlocks
  the Windows code path when set (F1 hook).
- [x] **H2. `search_primers_on_fq()` rewritten on seqkit** (G2 done):
  portable (seqkit has Windows bioconda builds), degenerate-base aware,
  correct read counting, both-strand matching, classed errors; exported
  with tests (verified live: 4/6 both-strand, 3/6 forward-only on a toy
  set with a known reverse-complement match).
- [x] **H3. `blast_type` validated** against supported BLAST+ engines.
- [x] **H4. Backoff between NCBI retry rounds** in `parallel_get_tax()`.
- [x] **H5. `get_fasta_header()`** returns one element per requested ID.
- [x] **H6. Long taxonomy output includes the taxon's own rank** (G4
  done) — genus-level queries now fill their own `Genus (NCBI)`.
- [x] **H7. pkgdown reference index organized**; `cran-comments.md`
  added.
- [x] **H8. Realistic-DB benchmark script** for the paper:
  `data-raw/benchmark_16S_db.R` (NCBI preformatted 16S rRNA database;
  run on the paper's hardware and record machine details).

## I. Round 3 (2026-08-12)

- [x] **I1 (closes E3). `parallel_blast_old()` removed** before first
  public release (was deprecated since 0.1.7; `parallel_blast()` returns
  the same format). Function, man page, tests, and pkgdown entry
  removed; NEWS updated with migration notes.
- [x] **I2 (closes G3). Version-pin update policy defined**: pins
  centralized in `blastr_conda_pins` (`R/check_cmd.R`, single source of
  truth; currently BLAST+ 2.16, Entrez Direct 24.0, seqkit 2.10.1).
  Policy documented user-side in `?install_dependencies` (never
  implicit upgrades; `force = TRUE` is the upgrade path; runtime
  overrides via `blastr.conda.*` options) and maintainer-side in
  `.github/CONTRIBUTING.md` (minor-release-only bumps, platform
  availability check, fresh-env test run, NEWS record).
  `install_dependencies()` now also provisions the seqkit environment.

## J. Round 4 (2026-08-12) — dependency floors & release plumbing

- [x] **J1. condathis floor corrected to `>= 0.2.0`** — `get_tax_by_name()`
  uses `condathis::run(stdin = "|", input = )`, which only exists in the
  0.2.0 development version; CRAN has 0.1.4, so the old `>= 0.1.2` floor
  would have produced runtime failures for CRAN installs. `Remotes:
  luciorq/condathis` added for GitHub installs in the meantime.
- [ ] **J2. RELEASE-ORDER CONSTRAINT: condathis 0.2.0 must be published
  to CRAN before BLASTr can be submitted** (and the `Remotes:` field
  removed at that point). Owner action (condathis is owner-maintained).
- [x] **J3. `dplyr (>= 1.1.0)` floor added** (engine uses `mutate(.by=)`)
  and **`stats` declared in Imports** (`stats::setNames`).
- [x] **J4. Workflows now install the quarto CLI**
  (`quarto-dev/quarto-actions/setup@v2` in both `r-cmd-check.yaml` and
  `pkgdown.yaml`) — the quarto-engine vignette cannot build without it,
  and runners don't ship it. Stale CI comment (Sunday vs Friday cron)
  fixed.
- [x] **J5. Vignette dependency list updated** to include seqkit.
- [x] **J6. `urlchecker::url_check()` run** — 10/12 URLs OK; the two
  404s are the NEWS compare links, caused by missing git tags upstream.
- [ ] **J7. Push the missing `v0.1.7` tag** (at the 0.1.7 release
  commit) and tag `v0.2.0` on release — this fixes both NEWS compare
  URLs (`just git-tag` automates tagging the current version). Owner
  action.

## K. Production-readiness pass (2026-09-03)

- [x] **K1. Code style standardized**: `styler::style_pkg()` + `air
  format` (justfile order) across `R/` and `tests/`; formatting is now
  idempotent (re-runs change nothing).
- [x] **K2. `data-raw/notes.R` was not valid R** (bare Portuguese note
  text) and broke any package-wide tooling that parses `.R` files
  (styler aborted mid-run). Converted to comments; the note's request is
  implemented by `get_tax_by_name()` since 0.2.0.
- [x] **K3. Full verification battery re-run after reformatting** — see
  the verification-status header: as-cran check fully clean (qpdf now
  installed locally, so even the toolchain warning is gone), suite
  green, examples (incl. `\dontrun`) pass, pkgdown site builds.
- [x] **K4. Local install validated** (`devtools::install()` → loads
  from final location; pkgdown articles execute against the installed
  package, mirroring the CI setup).
- [ ] **K5. Not done deliberately — commit & tag.** The entire 0.2.0
  overhaul is uncommitted work in the tree on `main`. Suggested release
  sequence (owner actions):
  1. Commit the working tree (suggested message: "BLASTr 0.2.0:
     batched mirai/mori parallel engine, taxonomy fixes, seqkit primer
     search, docs/test overhaul").
  2. Push the missing `v0.1.7` tag at the 0.1.7 release commit (J7).
  3. Release condathis 0.2.0 to CRAN (J2), then drop the `Remotes:`
     field here.
  4. Tag `v0.2.0` (`just git-tag`) and push; CI (with the new quarto
     setup steps) validates on all matrix platforms.
  5. When the Windows conda packages land: default them in
     `conda_pkg_spec()` (F1) and re-enable Windows CI (F3).
  6. Run `data-raw/benchmark_16S_db.R` on the paper's hardware (G5)
     and record the numbers for the manuscript.

## L. Round 5 (2026-09-03) — blast-zig fallback & env hardening

- [x] **L1 (advances F1). `blast-zig` fallback wired** for the whole
  BLAST+ family on **all platforms**: primary bioconda spec is tried
  first; on installation failure the zig-toolchain `blast-zig` package
  from `https://prefix.dev/universe` is installed instead (Windows no
  longer aborts for BLAST+). Overridable via
  `blastr.conda.blast_fallback` / `blastr.conda.fallback_channels`.
- [ ] **L2. `blast-zig` is not yet visible on the `universe` channel**
  (channel currently lists tradetracker, polyglot, r-zig-slim, marimo-r
  only — verified via the prefix.dev GraphQL API). The fallback is
  configuration-complete but cannot be integration-tested until the
  package is published. **Owner actions:** publish `blast-zig` (win-64 +
  linux/osx builds), then pin its exact version in
  `blastr_conda_pins$blast_fallback` per the pin policy.
- [x] **L3. Environment installation/validation hardened**
  (`R/check_cmd.R`): post-install version-probe validation (probes
  verified to exit 0 for all 8 supported tools), once-per-session
  validation cache, automatic one-time rebuild of stale/corrupted
  environments, classed errors (`blastr_env_install_error`,
  `blastr_env_validation_error`) carrying the underlying condition.
  Unit + integration tests added (`test-check_cmd.R`).
- [ ] **L4. Entrez Direct / seqkit on Windows** still abort with an
  informative error (no fallback builds yet); Windows CI (F3) stays
  blocked on those since the test suite exercises taxonomy. Option:
  a Windows CI job running only the BLAST-path tests once blast-zig is
  published.

## M. Round 6 (2026-09-05) — code-review findings applied

- [x] **M1. All 10 verified correctness findings from `/code-review`
  fixed**, plus the 4 cut findings (stale stderr on retry, header
  misalignment, efetch worker duplication, seqkit temp-file waste,
  get_tax_by_name serial fetching — the stderr fix subsumes the stale
  entry). Each has a regression test. See NEWS 0.2.0 "Fixed" for the
  itemized list.
- [x] **M2. Per-query warning tagging (`parse_blast_warnings`) removed**
  in favor of preserving the full chunk stderr for every member —
  restores 0.1.7 stderr parity and keeps QC filters like
  `str_detect(stderr, "Examining")` working.
