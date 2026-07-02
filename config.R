# config.R
# Single source of truth for the vintages, paths, and rules that define the
# PUMA-to-CBSA crosswalk. Every knob that could change between crosswalk
# vintages lives here and nowhere else -- edit this file, re-run build.R, and
# the whole crosswalk is regenerated. Nothing downstream hard-codes a year,
# path, or threshold.
#
# Sourced first by build.R and by tests/testthat/test_crosswalk.R.

# --- Geographic vintages -----------------------------------------------------
# PUMA vintage carried by the ACS sample the crosswalk is meant to serve.
# Geocorr's puma22 codes are the 2020-Census-based PUMAs used by the
# 2020-2024 ACS 5-year sample.
PUMA_VINTAGE <- 2022L

# CBSA (metro/micro area) delineation vintage.
# Geocorr assigns cbsa20 (2020 OMB delineation); the metro-vs-micro split is
# read from the OMB July 2023 delineation file (DELINEATION_FILE below).
CBSA_ASSIGN_VINTAGE <- 2020L # from Geocorr (cbsa20)
CBSA_TYPE_VINTAGE   <- 2023L # from OMB delineation (M1 metro / M2 micro)

# ACS sample these PUMAs correspond to (documentation only).
ACS_SAMPLE_LABEL <- "2020-2024 ACS 5-year (IPUMS us2024c)"

# --- Assignment rule ---------------------------------------------------------
# 50% population rule: assign a PUMA to the single CBSA holding at least this
# share of the PUMA's 2020-Census population; otherwise the PUMA is non-metro.
PUMA_POP_THRESHOLD <- 0.50

# Connecticut is patched from the IPUMS crosswalk because Geocorr 2022 lacks
# CT's 2022 planning-region PUMAs. See R/build_crosswalk.R for the mechanism
# and the hard-coded CT PUMA list (revisit after the 2030 PUMA reapportionment).
CT_STATEFIP <- "09"

# --- Input paths (relative to repo root; wrapped in here() by build.R) --------
GEOCORR_FILE     <- file.path("data", "source", "geocorr2022_2609206408.csv")
IPUMS_CT_FILE    <- file.path("data", "source", "MSA2023_PUMA2020_crosswalk.xlsx")
DELINEATION_FILE <- file.path("data", "source", "delineation_2023.xlsx")

# --- Output paths ------------------------------------------------------------
OUTPUT_PARQUET <- file.path("data", "output", "puma_cbsa_crosswalk.parquet")
OUTPUT_CSV     <- file.path("data", "output", "puma_cbsa_crosswalk.csv")
