# test_reproducibility.R
# Guards that the crosswalk in data/output/ is (a) exactly what the current
# build code produces, and (b) identical to the parent gap-report pipeline's
# crosswalk when that reference is reachable.
#
#   - Golden regression: a fresh in-memory rebuild must equal the committed
#     data/output/ crosswalk. Any change to config.R or R/build_crosswalk.R
#     that alters the result fails here until the committed output is
#     deliberately regenerated -- no silent drift.
#   - Provenance cross-check: if the parent pipeline's crosswalk parquet is
#     reachable (env var GAP_PARENT_CROSSWALK, or the default ../../ path when
#     this repo lives inside the parent project), assert equivalence. Skips
#     cleanly in a standalone checkout.

suppressPackageStartupMessages({
  library(testthat)
  library(arrow)
  library(dplyr)
  library(here)
})

source(here("config.R"))
source(here("R", "build_crosswalk.R"))

committed <- arrow::read_parquet(here(OUTPUT_PARQUET))

# Order-independent, NA-safe cell-for-cell comparison of two crosswalk frames.
expect_crosswalk_identical <- function(a, b, label = "crosswalk") {
  norm <- function(d) as.data.frame(arrange(select(d, all_of(CROSSWALK_COLS)), puma_id))
  expect_equal(norm(a), norm(b), info = label)
}

test_that("committed output equals a fresh rebuild (no silent drift)", {
  rebuilt <- build_puma_cbsa_crosswalk(
    geocorr_path     = here(GEOCORR_FILE),
    ipums_ct_path    = here(IPUMS_CT_FILE),
    delineation_path = here(DELINEATION_FILE),
    pop_threshold    = PUMA_POP_THRESHOLD,
    ct_statefip      = CT_STATEFIP,
    ct_pumas         = CT_PUMAS_2020,
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
  expect_crosswalk_identical(committed, arrow::read_parquet(parent_path), "standalone vs parent")
})
