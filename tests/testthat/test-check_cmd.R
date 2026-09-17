testthat::test_that("conda_pkg_spec returns fallback for the BLAST+ family", {
  spec <- conda_pkg_spec("blastn")
  testthat::expect_equal(spec$packages, blastr_conda_pins$blast)
  testthat::expect_equal(
    spec$fallback$packages,
    blastr_conda_pins$blast_fallback
  )
  testthat::expect_true(
    any(grepl("prefix.dev/universe", spec$fallback$channels, fixed = TRUE))
  )
  # Same spec for every BLAST+ family member.
  for (blast_cmd in c("tblastn", "blastx", "makeblastdb", "blastdbcmd")) {
    testthat::expect_equal(conda_pkg_spec(blast_cmd), spec)
  }
})

testthat::test_that("conda_pkg_spec has no fallback for entrez/seqkit", {
  testthat::expect_null(conda_pkg_spec("efetch")$fallback)
  testthat::expect_null(conda_pkg_spec("seqkit")$fallback)
})

testthat::test_that("conda_pkg_spec respects option overrides", {
  withr::local_options(list(
    blastr.conda.blast = "somechannel::someblast==1.0",
    blastr.conda.blast_fallback = "otherchannel::otherblast==2.0",
    blastr.conda.fallback_channels = "https://example.org/channel"
  ))
  spec <- conda_pkg_spec("blastn")
  testthat::expect_equal(spec$packages, "somechannel::someblast==1.0")
  testthat::expect_equal(
    spec$fallback$packages,
    "otherchannel::otherblast==2.0"
  )
  testthat::expect_equal(
    spec$fallback$channels,
    "https://example.org/channel"
  )
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
