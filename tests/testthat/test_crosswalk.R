# test_crosswalk.R
# Invariants the built crosswalk must satisfy. Run via: Rscript run_tests.R
# (run_tests.R builds the crosswalk first if data/output is empty).

suppressPackageStartupMessages({
  library(testthat)
  library(arrow)
  library(dplyr)
  library(here)
})

source(here("config.R"))
xw <- arrow::read_parquet(here(OUTPUT_PARQUET))

test_that("schema: required columns are present", {
  expect_true(all(CROSSWALK_COLS %in% names(xw)))
})

test_that("coverage: > 2,400 PUMAs, one unique row each", {
  expect_gt(nrow(xw), 2400)
  expect_equal(nrow(xw), n_distinct(xw$puma_id))
})

test_that("join key: puma_id is 7 all-digit chars = statefip(2) + puma(5)", {
  expect_true(all(grepl("^[0-9]{7}$", xw$puma_id)))
  expect_true(all(nchar(xw$statefip) == 2))
  expect_true(all(nchar(xw$puma) == 5))
  expect_equal(xw$puma_id, paste0(xw$statefip, xw$puma))
})

test_that("Connecticut patch produced > 20 PUMAs", {
  ct <- xw |> filter(statefip == "09")
  expect_gt(nrow(ct), 20)
})

test_that("metro flag is exactly 'has a CBSA'", {
  expect_equal(xw$is_metro, !is.na(xw$cbsa))
})

test_that("non-metro rows have no CBSA and no overlap_pct", {
  nm <- xw |> filter(!is_metro)
  expect_true(all(is.na(nm$cbsa)))
  expect_true(all(nm$cbsa_name == "Non-metropolitan"))
  expect_true(all(is.na(nm$overlap_pct)))
  expect_true(all(!nm$is_micro)) # non-metro is never micro (FALSE, not NA)
})

test_that("metro rows satisfy the 50% population rule", {
  m <- xw |> filter(is_metro)
  expect_true(all(m$overlap_pct >= 0.50))
  expect_true(all(m$overlap_pct <= 1.0))
  expect_true(all(m$cbsa_name != "Non-metropolitan"))
})

test_that("micropolitan implies metropolitan (has a CBSA)", {
  micro <- xw |> filter(!is.na(is_micro) & is_micro)
  expect_true(all(micro$is_metro))
})

test_that("all three geography types are represented", {
  expect_gt(sum(xw$is_metro & !xw$is_micro, na.rm = TRUE), 0) # metropolitan
  expect_gt(sum(xw$is_micro, na.rm = TRUE), 0)                # micropolitan
  expect_gt(sum(!xw$is_metro), 0)                             # non-metro
})

test_that("known composition (this vintage: Geocorr 2022 + OMB 2023)", {
  expect_equal(nrow(xw), 2486L)
  expect_equal(sum(xw$is_metro & !xw$is_micro, na.rm = TRUE), 2107L) # metropolitan
  expect_equal(sum(xw$is_micro, na.rm = TRUE), 95L)                  # micropolitan
  expect_equal(sum(!xw$is_metro), 249L)                             # non-metro
  expect_equal(sum(xw$statefip == "09"), 25L)                       # Connecticut
})

test_that("anchor mappings resolve to the expected CBSAs", {
  row_for <- function(id) xw[xw$puma_id == id, , drop = FALSE]

  # Limestone County, AL -> Huntsville, AL metro (100% of the PUMA)
  hsv <- row_for("0100200")
  expect_equal(nrow(hsv), 1L)
  expect_equal(hsv$cbsa, "26620")
  expect_true(hsv$is_metro)
  expect_false(hsv$is_micro)

  # Major metros should aggregate many PUMAs
  expect_gt(sum(xw$cbsa == "35620", na.rm = TRUE), 100) # New York-Newark-Jersey City
  expect_gt(sum(xw$cbsa == "31080", na.rm = TRUE), 50)  # Los Angeles-Long Beach-Anaheim
  expect_gt(sum(xw$cbsa == "47900", na.rm = TRUE), 20)  # Washington-Arlington-Alexandria
})
