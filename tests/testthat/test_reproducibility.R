# test_reproducibility.R
# Guards that the crosswalk in data/output/ is (a) exactly what the current
# build code produces, and (b) identical to the parent gap-report pipeline's
# crosswalk when that reference is reachable.
#
#   - Golden regression: a fresh in-memory rebuild must equal the committed
#     data/output/ crosswalk cell-for-cell. Any change to config.R or
#     R/build_crosswalk.R that alters the result fails here until the committed
#     output is deliberately regenerated -- no silent drift.
#   - Provenance cross-check: if the parent pipeline's crosswalk parquet is
#     reachable (env var GAP_PARENT_CROSSWALK, or the default ../../ path when
#     this repo lives inside the parent project), assert byte-for-byte column
#     equivalence. Skips cleanly in a standalone checkout.

suppressPackageStartupMessages({
  library(testthat)
  library(arrow)
  library(dplyr)
  library(here)
})

source(here("config.R"))
source(here("R", "build_crosswalk.R"))

# Cell-for-cell comparison of two crosswalk frames (NA-safe, order-independent).
expect_crosswalk_identical <- function(a, b, label = "crosswalk") {
  cols <- c("puma_id", "statefip", "puma", "puma_name",
            "cbsa", "cbsa_name", "overlap_pct", "is_metro", "is_micro")
  expect_true(all(cols %in% names(a)), info = paste(label, "- a missing columns"))
  expect_true(all(cols %in% names(b)), info = paste(label, "- b missing columns"))

  a <- a |> arrange(puma_id) |> select(all_of(cols))
  b <- b |> arrange(puma_id) |> select(all_of(cols))

  expect_equal(nrow(a), nrow(b), info = paste(label, "- row count"))
  expect_true(setequal(a$puma_id, b$puma_id), info = paste(label, "- puma_id set"))
  expect_identical(a$puma_id, b$puma_id, info = paste(label, "- puma_id order"))

  na_safe_equal <- function(x, y) (is.na(x) & is.na(y)) | (!is.na(x) & !is.na(y) & x == y)
  for (cc in cols) {
    diffs <- sum(!na_safe_equal(a[[cc]], b[[cc]]))
    expect_equal(diffs, 0, info = paste(label, "- differing cells in", cc))
  }
}

test_that("committed output equals a fresh rebuild (no silent drift)", {
  committed <- arrow::read_parquet(here(OUTPUT_PARQUET))
  rebuilt <- build_puma_cbsa_crosswalk(
    geocorr_path     = here(GEOCORR_FILE),
    ipums_ct_path    = here(IPUMS_CT_FILE),
    delineation_path = here(DELINEATION_FILE),
    pop_threshold    = PUMA_POP_THRESHOLD,
    ct_statefip      = CT_STATEFIP,
    verbose          = FALSE
  )
  expect_crosswalk_identical(committed, rebuilt, "committed vs rebuild")
})

test_that("output matches the parent gap-report pipeline crosswalk (if reachable)", {
  parent_path <- Sys.getenv("GAP_PARENT_CROSSWALK", unset = "")
  if (!nzchar(parent_path)) {
    parent_path <- here("..", "..", "data", "intermed", "puma_cbsa_crosswalk.parquet")
  }
  skip_if_not(
    file.exists(parent_path),
    "Parent pipeline crosswalk not reachable; set GAP_PARENT_CROSSWALK to enable."
  )
  committed <- arrow::read_parquet(here(OUTPUT_PARQUET))
  parent <- arrow::read_parquet(parent_path)
  expect_crosswalk_identical(committed, parent, "standalone vs parent pipeline")
})
