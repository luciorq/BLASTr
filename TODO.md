# BLASTr — Review Findings & Task Tracker

> Generated from a full-package review (2026-08-11); implementation of
> the 0.2.0 overhaul completed the same day. Focus: correctness and
> performance ahead of public release and the companion analysis paper.
> Status legend: `[ ]` open · `[x]` done · `[~]` in progress · `[!]`
> decision needed

## Verification status (2026-09-03, production-readiness pass)

- `devtools::test()`: **all passing, no skips** (all three conda envs
  built from scratch in the hermetic test sandbox).
- `R CMD check --as-cran` (with vignette rebuild and tests): **Status OK
  — 0 errors, 0 warnings, 0 notes.**
- `devtools::spell_check()`: clean. `urlchecker`: clean except the two
  NEWS compare links pending tags (J7).
- [`pkgdown::build_site()`](https://pkgdown.r-lib.org/reference/build_site.html):
  builds fully (reference index, executed articles, search) with zero
  problems. Note: pkgdown renders the root `TODO.md` into the public
  site as `TODO.html` — decide whether that is desired before deploying.
- Code style: `styler` + `air format` (justfile order) applied to `R/`
  and `tests/`; re-runs produce zero changes.
- Benchmark (200 unique 100 bp queries, minimal db, Linux x86_64):
  per-seq serial 131.7s → **batched serial 2.9s (~45x)**; per-seq 4-core
  34.4s → batched 4-core 4.5s. Identical results in all modes. Script:
  `data-raw/benchmark_chunked_vs_perseq.R`.

## A. Release blockers (regressions from recent commits)

**A1.
[`make_blast_db()`](https://heronoh.github.io/BLASTr/reference/make_blast_db.md)
lost `db_path`** — restored as an optional argument (`NULL` = alongside
input FASTA); input validation added.

**A2. `asv → query_seqs` rename half-done** — `asvs = deprecated()` shim
restored in
[`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md);
`parallel_blast_old()` fixed by delegating to
[`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md);
tests updated; docs regenerated (codoc warnings gone).

**A3.
[`make_blast_db()`](https://heronoh.github.io/BLASTr/reference/make_blast_db.md)
debug leftovers** —
[`print()`](https://rdrr.io/r/base/print.html)/[`message()`](https://rdrr.io/r/base/message.html)
removed; command echo now gated behind `verbose = "cmd"/"full"`;
`cli_abort()` with classed errors.

**A4. taxid_map “same radical” check** — dropped (constraint does not
exist in `makeblastdb`); replaced with file-existence + `parse_seqids`
compatibility checks.

**A5. Test suite cannot run** — setup works again;
`Config/testthat/parallel: false` (conda env creation is not
concurrency-safe across testthat workers).

## B. Runtime bugs

**B1. Retry duplication in
[`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)**
— new engine tracks per-sequence status; retried successes appear
exactly once (regression test added).

**B2.
[`get_tax_by_name()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_name.md)
unusable** — rewritten on the verified `esearch → efetch` stdin pipe
(`condathis::run(stdin = "|", input =)`);
`esearch`/`esummary`/`elink`/`xtract` added to `check_cmd()`; returns
the
[`get_tax_by_taxID()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_taxID.md)
schema plus `query_name`; live-tested.

**B3. Dead XML-integrity check** — parser now `tryCatch`es `read_xml()`
properly and returns an empty typed tibble on failure.

**B4. Multi-taxid fetch broken/fragile** — IDs joined with commas into a
single `-id` value; records mapped back via the XML `<TaxId>` element
(NCBI’s response order does **not** match request order — verified live;
test added).

**B5.
[`run_blast()`](https://heronoh.github.io/BLASTr/reference/run_blast.md)
concatenated multiple sequences into one query** — every sequence is now
its own FASTA record with a generated `BLASTrQ<i>` header; temp files
cleaned via
[`withr::local_tempfile()`](https://withr.r-lib.org/reference/with_tempfile.html);
test added.

**B6.
[`parse_fasta()`](https://heronoh.github.io/BLASTr/reference/parse_fasta.md)
message interpolation** — fixed.

**B7. `search_primer_on_fq.R`** — moved to `data-raw/` pending a
portable rewrite (candidate backend: seqkit via condathis).

**B8. Messages ignoring `verbose`** — all taxonomy chatter now respects
`verbose = "silent"`.

**B9. Daemon lifecycle** — pools created internally are torn down via
[`withr::defer()`](https://withr.r-lib.org/reference/defer.html) on
every path; pre-existing
[`mirai::daemons()`](https://mirai.r-lib.org/reference/daemons.html)
pools are detected
([`mirai::daemons_set()`](https://mirai.r-lib.org/reference/daemons_set.html))
and reused instead of erroring.

## C. Dependency / metadata correctness

**C1. `withr` moved Suggests → Imports.**

**C2. `tools` added to Imports.**

**C3. `declare(carrier::crate)` (R ≥ 4.5 only)** — removed;
`@importFrom carrier crate` in the package doc instead.

**C4. DESCRIPTION typo** — fixed.

**C5. NEWS vs code `retry_times` default** — corrected (3).

**C6. `.Rbuildignore` `README_files` pattern** — fixed; `TODO.md` also
ignored.

**C7. Dead `check_connection()`** — removed.

**C8. `inst/CITATION`** — added (update with the article DOI when the
paper is out).

**C9/C10/C11. Stale man pages, ghost params, wrong titles** —
regenerated/rewritten.

## D. Performance / architecture (mirai + mori)

**D1. Batched multi-record FASTA chunks** (`R/blast_engine.R`):
`>BLASTrQ<i>` headers, exact `qseqid`-based mapping back to input.

**D2.
[`mirai::mirai_map()`](https://mirai.r-lib.org/reference/mirai_map.html)
dispatch** with `collect_mirai()` (`.progress` collection),
[`carrier::crate()`](https://rdrr.io/pkg/carrier/man/crate.html) workers
(self-contained; no package namespace needed on daemons), per-element
error values.

**D3. [`mori::share()`](https://rdrr.io/pkg/mori/man/share.html)** —
query vector placed in shared memory when `mori` is installed
(Suggests); zero-copy reads on workers; graceful fallback otherwise.

**D4. Salvage + retry** — failed chunks re-run per-sequence within the
same attempt (verified live: BLAST+ itself salvages malformed records
inside a batch with exit 0 + per-query warnings, which the engine parses
and attributes via `parse_blast_warnings()`); failing singletons retried
up to `retry_times`.

**D5. Respect pre-existing daemons** (see B9).

**D6. `mt_mode`** — verified `-mt_mode 2` is accepted by BLAST 2.16;
argument kept and interaction documented.

**D7. Wide-format assembly** — column order computed programmatically
for any `num_alignments` (no more hardcoded `1_`–`6_`).

**D8. Per-hit `blastdbcmd` calls eliminated** — `subject header` comes
from `stitle` in the single outfmt;
[`get_fasta_header()`](https://heronoh.github.io/BLASTr/reference/get_fasta_header.md)
also accepts a vector of IDs now.

**D9. NCBI etiquette** — taxids batched (default 100/request);
`NCBI_API_KEY` documented (honored automatically by Entrez Direct); rate
limits documented.

**D10. Benchmark** — see verification status above.

## E. Output/API polish (paper-facing)

**E1. `indentity` → `identity`** (wide columns now `<n>_identity`).
Downstream analysis code referencing `_indentity` columns must be
updated.

**E2/E5. Version 0.2.0 + NEWS** — full changelog written.

**E3. Fate of `parallel_blast_old()`** — removed on 2026-08-12 (owner
decision; see I1).

**E4. Vignette** — real intro written (install → make db →
parallel_blast → exit_codes → taxonomy → performance notes).

## F. Windows / cross-OS

**F1. Windows conda packages (BLAST+)** — done 2026-09-18: the `blast`
package on `https://prefix.dev/universe` (2.17.0, one toolchain for
linux-64/linux-aarch64/osx-64/osx-arm64/win-64) is now the primary
BLAST+ spec on every platform, with `bioconda::blast==2.17.0` as
fallback. Entrez Direct and seqkit remain Linux/macOS-only (L4).

**F2. Env staleness** — `install_dependencies(force = TRUE)` documented
as the upgrade path (vignette + README).

**F3. Windows CI re-enabled** (2026-09-18): `windows-latest` is back in
the matrix. Tests needing Entrez Direct / seqkit skip on Windows via
`skip_if_tool_unavailable()` (`helper-platform.R`);
[`install_dependencies()`](https://heronoh.github.io/BLASTr/reference/install_dependencies.md)
skips those families there instead of aborting. First green Windows run
pending (owner: watch CI).

## G. Remaining / follow-ups

**G1. `inst/extdata/minimal_db_blast.fasta` repaired** (the defect was
one line holding three concatenated `>` headers — `KX381515.1` /
`KX381584.1` / `KX381638.1` — folded into a single record’s title; fixed
keeping `KX381515.1` with its own description, sequences byte-identical,
wrapped at 80 columns; script: `data-raw/fix_minimal_db_fasta.R`). A
matching taxid map is now packaged as
`inst/extdata/minimal_db_blast.txt` (47/47 accessions, derived from the
curated `shortest_minimal_db_BLASTr.txt`, which moved to `data-raw/`
where its own FASTA lives). The shared test database is built with the
map, so the whole suite exercises the `staxid` path; the
formerly-skipped taxid test is now a real end-to-end assertion (build →
blast → `staxid` →
[`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md)
round trip). Verified: output shape unchanged (6 × 57), suite green with
**no skips**.

**G2. Rewrite
[`search_primers_on_fq()`](https://heronoh.github.io/BLASTr/reference/search_primers_on_fq.md)**
portably (seqkit grep via condathis) and re-export.

**G3. Update pinned tool versions deliberately** (blast==2.16,
entrez-direct==24.0) and document the policy.

**G4. `parallel_get_tax(parse_result = FALSE)`** returns lineage rows
without the query linkage beyond `query_taxID` — consider adding the
taxon’s own rank row for completeness.

**G5. Benchmark against a realistically sized database** for the paper
(nt/core_nt subset), including `num_threads`/`mt_mode` interaction, and
record hardware details.

**G6. Downstream code migration note**: `1_indentity` → `1_identity`,
taxonomy tables gained `Domain (NCBI)` (14 cols), and
[`get_blast_results()`](https://heronoh.github.io/BLASTr/reference/get_blast_results.md)
now returns the
[`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
format.

## H. Post-review round 2 (2026-08-11, while Windows packages are in progress)

**H1. Conda spec overrides via options** (`blastr.conda.blast`,
`blastr.conda.entrez`, `blastr.conda.seqkit`, `blastr.conda.channels`) —
lets the Windows candidate packages be tested with
`options(blastr.conda.blast = "<channel>::<pkg>==<ver>")` and unlocks
the Windows code path when set (F1 hook).

**H2.
[`search_primers_on_fq()`](https://heronoh.github.io/BLASTr/reference/search_primers_on_fq.md)
rewritten on seqkit** (G2 done): portable (seqkit has Windows bioconda
builds), degenerate-base aware, correct read counting, both-strand
matching, classed errors; exported with tests (verified live: 4/6
both-strand, 3/6 forward-only on a toy set with a known
reverse-complement match).

**H3. `blast_type` validated** against supported BLAST+ engines.

**H4. Backoff between NCBI retry rounds** in
[`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md).

**H5.
[`get_fasta_header()`](https://heronoh.github.io/BLASTr/reference/get_fasta_header.md)**
returns one element per requested ID.

**H6. Long taxonomy output includes the taxon’s own rank** (G4 done) —
genus-level queries now fill their own `Genus (NCBI)`.

**H7. pkgdown reference index organized**; `cran-comments.md` added.

**H8. Realistic-DB benchmark script** for the paper:
`data-raw/benchmark_16S_db.R` (NCBI preformatted 16S rRNA database; run
on the paper’s hardware and record machine details).

## I. Round 3 (2026-08-12)

**I1 (closes E3). `parallel_blast_old()` removed** before first public
release (was deprecated since 0.1.7;
[`parallel_blast()`](https://heronoh.github.io/BLASTr/reference/parallel_blast.md)
returns the same format). Function, man page, tests, and pkgdown entry
removed; NEWS updated with migration notes.

**I2 (closes G3). Version-pin update policy defined**: pins centralized
in `blastr_conda_pins` (`R/check_cmd.R`, single source of truth;
currently BLAST+ 2.16, Entrez Direct 24.0, seqkit 2.10.1). Policy
documented user-side in
[`?install_dependencies`](https://heronoh.github.io/BLASTr/reference/install_dependencies.md)
(never implicit upgrades; `force = TRUE` is the upgrade path; runtime
overrides via `blastr.conda.*` options) and maintainer-side in
`.github/CONTRIBUTING.md` (minor-release-only bumps, platform
availability check, fresh-env test run, NEWS record).
[`install_dependencies()`](https://heronoh.github.io/BLASTr/reference/install_dependencies.md)
now also provisions the seqkit environment.

## J. Round 4 (2026-08-12) — dependency floors & release plumbing

**J1. condathis floor corrected to `>= 0.2.0`** —
[`get_tax_by_name()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_name.md)
uses `condathis::run(stdin = "|", input = )`, which only exists in the
0.2.0 development version; CRAN has 0.1.4, so the old `>= 0.1.2` floor
would have produced runtime failures for CRAN installs.
`Remotes: luciorq/condathis` added for GitHub installs in the meantime.

**J2. Release-order constraint lifted (2026-09-18).** With Entrez Direct
gone (N2) the `stdin` pipe feature is unused; the floor is back to CRAN
`condathis (>= 0.1.4)` and `Remotes:` is removed. Verified by running
the tool-dependent suite against CRAN condathis 0.1.4 in an isolated
library (all green).

**J3. `dplyr (>= 1.1.0)` floor added** (engine uses `mutate(.by=)`) and
**`stats` declared in Imports**
([`stats::setNames`](https://rdrr.io/r/stats/setNames.html)).

**J4. Workflows now install the quarto CLI**
(`quarto-dev/quarto-actions/setup@v2` in both `r-cmd-check.yaml` and
`pkgdown.yaml`) — the quarto-engine vignette cannot build without it,
and runners don’t ship it. Stale CI comment (Sunday vs Friday cron)
fixed.

**J5. Vignette dependency list updated** to include seqkit.

**J6. `urlchecker::url_check()` run** — 10/12 URLs OK; the two 404s are
the NEWS compare links, caused by missing git tags upstream.

**J7. Push the missing `v0.1.7` tag** (at the 0.1.7 release commit) and
tag `v0.2.0` on release — this fixes both NEWS compare URLs
(`just git-tag` automates tagging the current version). Owner action.

## K. Production-readiness pass (2026-09-03)

**K1. Code style standardized**: `styler::style_pkg()` + `air format`
(justfile order) across `R/` and `tests/`; formatting is now idempotent
(re-runs change nothing).

**K2. `data-raw/notes.R` was not valid R** (bare Portuguese note text)
and broke any package-wide tooling that parses `.R` files (styler
aborted mid-run). Converted to comments; the note’s request is
implemented by
[`get_tax_by_name()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_name.md)
since 0.2.0.

**K3. Full verification battery re-run after reformatting** — see the
verification-status header: as-cran check fully clean (qpdf now
installed locally, so even the toolchain warning is gone), suite green,
examples (incl. `\dontrun`) pass, pkgdown site builds.

**K4. Local install validated** (`devtools::install()` → loads from
final location; pkgdown articles execute against the installed package,
mirroring the CI setup).

**K5. Not done deliberately — commit & tag.** The entire 0.2.0 overhaul
is uncommitted work in the tree on `main`. Suggested release sequence
(owner actions):

1.  Commit the working tree (suggested message: “BLASTr 0.2.0: batched
    mirai/mori parallel engine, taxonomy fixes, seqkit primer search,
    docs/test overhaul”).
2.  Push the missing `v0.1.7` tag at the 0.1.7 release commit (J7).
3.  Release condathis 0.2.0 to CRAN (J2), then drop the `Remotes:` field
    here.
4.  Tag `v0.2.0` (`just git-tag`) and push; CI (with the new quarto
    setup steps) validates on all matrix platforms.
5.  When the Windows conda packages land: default them in
    `conda_pkg_spec()` (F1) and re-enable Windows CI (F3).
6.  Run `data-raw/benchmark_16S_db.R` on the paper’s hardware (G5) and
    record the numbers for the manuscript.

## L. Round 5 (2026-09-03) — blast-zig fallback & env hardening

**L1 (advances F1). `blast-zig` fallback wired** for the whole BLAST+
family on **all platforms**: primary bioconda spec is tried first; on
installation failure the zig-toolchain `blast-zig` package from
`https://prefix.dev/universe` is installed instead (Windows no longer
aborts for BLAST+). Overridable via `blastr.conda.blast_fallback` /
`blastr.conda.fallback_channels`.

**L2. universe BLAST+ package published** (as `blast`, not `blast-zig`;
2.17.0 on all five platforms) and promoted to the primary spec on
2026-09-18 (see F1). Verified live on linux-64: installs in ~13 s, all 7
tools probe OK, `makeblastdb -taxid_map` + `blastn -mt_mode 2` produce
correct `staxid` hits. The noarch `blast-scripts` metapackage
(`blast==2.17.0` + perl + python) is available on the same channel but
not used: it does not include Entrez Direct or seqkit, so it cannot
replace those environments by itself.

**L3. Environment installation/validation hardened** (`R/check_cmd.R`):
post-install version-probe validation (probes verified to exit 0 for all
8 supported tools), once-per-session validation cache, automatic
one-time rebuild of stale/corrupted environments, classed errors
(`blastr_env_install_error`, `blastr_env_validation_error`) carrying the
underlying condition. Unit + integration tests added
(`test-check_cmd.R`).

**L4. Entrez Direct / seqkit on Windows** still raise an informative
classed error on use (neither bioconda nor conda-forge has win-64
builds, verified 2026-09-18). Windows CI now runs the BLAST path and
skips the taxonomy / primer-search tests. Candidate: publish uniform
builds on the universe channel like `blast`, then drop
`windows_guarded_spec()`.

## M. Round 6 (2026-09-05) — code-review findings applied

**M1. All 10 verified correctness findings from `/code-review` fixed**,
plus the 4 cut findings (stale stderr on retry, header misalignment,
efetch worker duplication, seqkit temp-file waste, get_tax_by_name
serial fetching — the stderr fix subsumes the stale entry). Each has a
regression test. See NEWS 0.2.0 “Fixed” for the itemized list.

**M2. Per-query warning tagging (`parse_blast_warnings`) removed** in
favor of preserving the full chunk stderr for every member — restores
0.1.7 stderr parity and keeps QC filters like
`str_detect(stderr, "Examining")` working.

## N. Round 7 (2026-09-18) — universe BLAST+, Windows CI, Entrez Direct removed

**N1. BLAST+ from `universe::blast==2.17.0`** on every platform,
bioconda 2.17.0 fallback (see F1/L2). Windows CI re-enabled (F3).

**N2. Entrez Direct dependency removed.** `R/eutils.R` is a small NCBI
E-utilities client (`curl` + `xml2`, POST, `tool`/`email`/ `api_key`
params, per-process throttle 3/s or 10/s with key, retry on
429/5xx/network with backoff).
[`get_tax_by_taxID()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_taxID.md),
[`get_tax_by_name()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_name.md),
[`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md)
use it; `env_name` is deprecated (lifecycle) and ignored; the crated
worker runs unchanged on mirai daemons (verified live). Taxonomy now
works on Windows and its tests no longer skip there. `curl` moved
Suggests → Imports.

**N3. Validation against the real Entrez Direct**
(`tests/testthat/test-eutils-vs-edirect.R`, Linux/macOS, installs
`bioconda::entrez-direct==24.0` into a test-only env): identical parsed
records for 7 valid + 1 invalid Tax IDs across Eukaryota / Bacteria /
Archaea, identical `esearch` ID sets for 6 names (incl. a non-existent
one), and the public API equals a reference built from `efetch` XML
(serial, parallel, and by-name). Offline unit tests with mocked HTTP
cover parsing, retries, joins, and deprecations (`test-eutils.R`).

**N4. seqkit dependency removed (2026-09-18).**
[`search_primers_on_fq()`](https://heronoh.github.io/BLASTr/reference/search_primers_on_fq.md)
is pure R again, faithful to the co-author’s original goal (per
file/primer: total reads, reads carrying the primer, percentage; IUPAC
degenerate primers; plain or gzip FASTQ), with the original
`parsed_primer` column restored, streaming in chunks, both-strand
matching, and correct read counting. Packaged toy library
`inst/extdata/toy_reads.fastq.gz` (script
`data-raw/make_toy_reads_fastq.R`) powers runnable examples, tests and
an evaluated vignette section. BLAST+ is now the only external tool,
available on every platform; `windows_guarded_spec()` and the test skip
helper are gone and Windows CI runs the full suite. \## O. Round 8
(2026-09-18) — E-utilities client review (addressed 2026-09-18)

External review of `R/eutils.R`, `R/tax_engine.R`,
`R/parallel_get_tax.R`, `R/get_tax_by_name.R` against the two design
concerns raised before the implementation (NCBI rate limits; the
`esearch`/`efetch` query shapes). Verdict: both concerns are handled,
with one real gap (O1) and one measured inefficiency (O2). Evidence was
gathered live against NCBI on 2026-09-18 with
[`pkgload::load_all()`](https://pkgload.r-lib.org/reference/load_all.html).

**O1. Throttle is per daemon, not per process — aggregate rate exceeds
NCBI’s limit under `total_cores > 1`.** `make_eutils_worker()` captures
`eutils_state` in a
[`carrier::crate()`](https://rdrr.io/pkg/carrier/man/crate.html);
environments serialize *by copy*, so every `mirai` daemon receives its
own `last_request` slot. Verified: printing `environment(w)$state`
inside two daemons gives two distinct addresses (`0x5839…`, `0x58d3…`)
versus the main process (`0x5689…`). With `total_cores = 4` and no key
the aggregate is 4 × 3 = 12 req/s; NCBI answers 429, the worker’s
backoff absorbs it, so nothing fails — but it is exactly the client
behaviour NCBI asks to avoid, and the NEWS/roxygen wording “throttles to
the NCBI per-second limits” is only true for the serial path. Fix
options (either suffices):

1.  Scale the interval by pool size: `make_eutils_worker()` gains a
    `rate_share` (or `n_workers`) argument and uses
    `min_interval * n_workers` (`R/eutils.R:72`);
    [`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md)
    passes the daemon count it created/adopted
    (`mirai::status()$connections` or `total_cores`).
2.  Drop daemons for E-utilities entirely: each request already carries
    `batch_size = 100` IDs and NCBI is the bottleneck, so the serial
    path retrieves ~300 lineages/s (3 req/s) — parallelism buys nothing
    measurable. Keep `total_cores` as a no-op for API stability or
    deprecate it. Test idea: mock the HTTP layer, run with 3 daemons,
    assert the spacing of recorded request timestamps ≥ `1/3 * 3` s.

**O2. One unknown Tax ID costs ~40 s.** NCBI omits unknown IDs from an
otherwise successful `efetch` response;
[`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md)
treats every ID missing from the result as transient and re-requests it
`retry_times` (10) times with growing sleeps. Measured:
`parallel_get_tax(c("9606", "999999999"))` → 42.6 s for one row. Fix: an
ID absent from a batch that returned HTTP 200 *and* parsed
(`parse_tax_xml()` non-`NULL`) is definitively unknown; only IDs from
batches with `status != 0` / unparsable bodies go back into
`pending_ids` (`R/parallel_get_tax.R:143`). Report the definitively
unknown IDs once, without retrying. Same applies to
[`get_tax_by_name()`](https://heronoh.github.io/BLASTr/reference/get_tax_by_name.md),
which delegates to
[`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md).

**O3. Retry multiplication (awareness, low priority).** The worker
retries 429/5xx/transport errors 3× with backoff, and
[`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md)
retries failed batches up to 10 more rounds, so a persistent 5xx costs
up to ~30 requests per batch before giving up. Acceptable; consider
capping the outer loop lower (3–5) once O2 lands, since genuinely
transient failures clear within a few rounds.

Resolution (2026-09-18):

- O1: fix option 1. `make_eutils_worker(rate_share =)` multiplies the
  per-request interval; `make_tax_fetch_worker()` forwards it and
  [`parallel_get_tax()`](https://heronoh.github.io/BLASTr/reference/parallel_get_tax.md)
  passes `mirai::status()$connections` (1 on the serial path). Docs
  reworded (pool-wide throttle; `total_cores > 1` mostly overlaps
  latency). Test: unreachable host, `rate_share = 3`, second call waits
  \>= 1 s.
- O2: `tax_xml_is_valid()` (root element is `TaxaSet`). IDs absent from
  a valid TaxaSet are definitively unknown: collected in `unknown_ids`,
  reported once under verbose, never re-queued. Non-TaxaSet 200 bodies
  and non-200/transport failures still retry. Verified live before the
  fix: `parallel_get_tax(c("9606", "999999999"))` = 43.5 s; after: 0.4 s
  (one request). Mocked tests cover mixed batch, all-unknown batch, and
  the transient-body retry path.
- O3: accepted as is. With O2, only genuinely failing batches reach the
  outer loop; the 3 x 10 worst case only occurs during a sustained NCBI
  outage, where giving up early has no benefit. Default `retry_times`
  unchanged.

Confirmed correct (no action): API key read once in the main process and
baked into the crate (daemons need no env var), sent in the POST body
not the URL, redacted from verbose output; `tool`/`email` sent; POST for
ID batches; merged-ID resolution via `<AkaTaxIds>`; records matched by
`<TaxId>` not by order; `esearch` on taxonomy mirrors Entrez Direct (no
field restriction → many-to-many join is the right call); descendant
expansion (`txidNNN[Subtree]`, what `get_species_taxids.sh` adds) is not
needed by BLASTr. Live check: `get_tax_by_name("Danio rerio")` → 7955,
genus *Danio*.
