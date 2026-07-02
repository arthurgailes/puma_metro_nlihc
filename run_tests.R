# run_tests.R
# Build the crosswalk if needed, then run the invariant tests.
# Usage (from the repo root):  Rscript run_tests.R

suppressPackageStartupMessages({
  library(testthat)
  library(here)
})

source(here("config.R"))

# Ensure an output exists to test (rebuild if missing).
if (!file.exists(here(OUTPUT_PARQUET))) {
  message("No built crosswalk found; running build.R first...")
  source(here("build.R"))
}

test_dir(here("tests", "testthat"), stop_on_failure = TRUE)
