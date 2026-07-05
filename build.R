# build.R
# Entry point: regenerate the PUMA-to-CBSA crosswalk from the three bundled
# source files and write it to data/output/ as both parquet and CSV.
#
# Usage (from the repo root):  Rscript build.R
#
# All vintages, paths, and rules come from config.R -- edit that file, re-run
# this one, and the crosswalk is rebuilt. The build is fully offline.

suppressPackageStartupMessages({
  library(here)
  library(arrow)
  library(readr)
})

source(here("config.R"))
source(here("R", "build_crosswalk.R"))

cat("Building PUMA-to-CBSA crosswalk\n")
cat("  PUMA vintage:        ", PUMA_VINTAGE, "\n")
cat("  CBSA assign vintage: ", CBSA_ASSIGN_VINTAGE, " (Geocorr cbsa20)\n", sep = "")
cat("  CBSA type vintage:   ", CBSA_TYPE_VINTAGE, " (OMB delineation M1/M2)\n", sep = "")
cat("  ACS sample:          ", ACS_SAMPLE_LABEL, "\n")
cat("  Population threshold: ", round(PUMA_POP_THRESHOLD * 100), "%\n\n", sep = "")

crosswalk <- build_puma_cbsa_crosswalk(
  geocorr_path     = here(GEOCORR_FILE),
  ipums_ct_path    = here(IPUMS_CT_FILE),
  delineation_path = here(DELINEATION_FILE),
  pop_threshold    = PUMA_POP_THRESHOLD,
  ct_statefip      = CT_STATEFIP,
  ct_pumas         = CT_PUMAS_2020
)

# --- Write both deliverable formats ------------------------------------------
arrow::write_parquet(crosswalk, here(OUTPUT_PARQUET), compression = "zstd")
readr::write_csv(crosswalk, here(OUTPUT_CSV), na = "")

cat("\nWrote:\n")
cat("  ", OUTPUT_PARQUET, "\n", sep = "")
cat("  ", OUTPUT_CSV, "\n", sep = "")
