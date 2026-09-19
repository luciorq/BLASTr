testthat::test_that("conda_pkg_spec uses universe BLAST+ with bioconda fallback", {
  spec <- conda_pkg_spec("blastn")
  testthat::expect_equal(spec$packages, blastr_conda_pins$blast)
  testthat::expect_equal(spec$channels[[1]], "https://prefix.dev/universe")
  testthat::expect_equal(
    spec$fallback$packages,
    blastr_conda_pins$blast_fallback
  )
  testthat::expect_true("bioconda" %in% spec$fallback$channels)
  # Primary and fallback pin the same BLAST+ release, so results do not
  # depend on which source was installed.
  extract_version <- function(x) sub(".*==", "", x)
  testthat::expect_equal(
    extract_version(spec$packages),
    extract_version(spec$fallback$packages)
  )
  # Same spec for every BLAST+ family member.
  for (blast_cmd in c("tblastn", "blastx", "makeblastdb", "blastdbcmd")) {
    testthat::expect_equal(conda_pkg_spec(blast_cmd), spec)
  }
})

testthat::test_that("only the BLAST+ family is managed", {
  # Taxonomy is fetched over HTTPS (R/eutils.R) and primer search runs
  # in R, so neither Entrez Direct nor seqkit is a managed tool.
  for (removed_cmd in c("efetch", "esearch", "xtract", "seqkit")) {
    conda_pkg_spec(removed_cmd) |>
      testthat::expect_error(class = "blastr_check_cmd_unsupported_cmd")
  }
  # BLAST+ is available on every platform.
  testthat::expect_true(cmd_available_on_platform("blastn"))
})

testthat::test_that("conda_pkg_spec rejects unsupported commands", {
  conda_pkg_spec("not-a-tool") |>
    testthat::expect_error(class = "blastr_check_cmd_unsupported_cmd")
})

testthat::test_that("check_cmd validates and caches existing environments", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # The setup environments exist: first call validates the tool with its
  # version probe, subsequent calls hit the session cache.
  testthat::expect_true(check_cmd("blastn", env_name = "blastr-blast-env"))
  cached_timing <- system.time(
    res <- check_cmd("blastn", env_name = "blastr-blast-env")
  )
  testthat::expect_true(res)
  testthat::expect_lt(cached_timing[["elapsed"]], 0.5)
})

testthat::test_that("install_env_spec raises classed error without fallback", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  install_env_spec(
    pkg_spec = list(
      packages = "bioconda::not-a-real-package-blastr==9.9.9",
      channels = c("conda-forge", "bioconda"),
      fallback = NULL
    ),
    env_name = "blastr-test-bogus-env",
    verbose = "silent"
  ) |>
    testthat::expect_error(class = "blastr_env_install_error")
})

testthat::test_that("install_env_spec raises classed error when fallback also fails", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  install_env_spec(
    pkg_spec = list(
      packages = "bioconda::not-a-real-package-blastr==9.9.9",
      channels = c("conda-forge", "bioconda"),
      fallback = list(
        packages = "not-a-real-fallback-blastr==9.9.9",
        channels = "conda-forge"
      )
    ),
    env_name = "blastr-test-bogus-env",
    verbose = "silent"
  ) |>
    testthat::expect_error(class = "blastr_env_install_error")
})

testthat::test_that("env_bin_search_dirs matches the platform layout", {
  dirs <- env_bin_search_dirs("/tmp/env")
  if (isTRUE(stringr::str_detect(get_sys_arch(), "^Windows"))) {
    testthat::expect_true(
      any(stringr::str_detect(dirs, stringr::fixed("Library/bin")))
    )
    testthat::expect_true("/tmp/env" %in% as.character(dirs))
  } else {
    testthat::expect_equal(as.character(dirs), "/tmp/env/bin")
  }
})

testthat::test_that("run_env_cmd finds and runs environment binaries", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  first_line <- function(x) {
    stringr::str_trim(strsplit(x, "\r?\n")[[1]][[1]])
  }

  res <- run_env_cmd("blastn", "-version", env_name = "blastr-blast-env")
  testthat::expect_equal(res$status, 0L)
  testthat::expect_true(stringr::str_detect(res$stdout, "blastn: 2\\.17"))

  # Same answer as `micromamba run` (environment activation), which
  # works everywhere but goes through a shell.
  res_run <- condathis::run(
    "blastn",
    "-version",
    env_name = "blastr-blast-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_equal(first_line(res$stdout), first_line(res_run$stdout))

  # Arguments with `%` reach the binary verbatim (no shell expansion):
  # blastdbcmd rejects a mangled -outfmt with "Invalid format specification".
  res_fmt <- run_env_cmd(
    "blastdbcmd",
    "-db",
    tmp_blast_db_path,
    "-entry",
    "AP011979.1",
    "-outfmt",
    "%a %t",
    env_name = "blastr-blast-env"
  )
  testthat::expect_equal(res_fmt$status, 0L)
  testthat::expect_true(stringr::str_detect(res_fmt$stdout, "^AP011979\\.1 "))

  probe <- validate_cmd("blastn", "blastr-blast-env")
  testthat::expect_true(probe$ok)
  testthat::expect_equal(probe$status, 0L)
})
