# config.R
# The knobs that define the PUMA-to-CBSA crosswalk: input/output paths, the
# assignment threshold, and the Connecticut vintage data. build.R and the test
# files source this first, so the actionable settings live here and nowhere
# else -- change a path, the threshold, or the CT PUMA list, re-run build.R,
# and the crosswalk is regenerated.

# --- Provenance labels -------------------------------------------------------
# These describe the bundled inputs for the build banner and README. They are
# labels, not switches: the actual vintages are fixed by the files in
# data/source/ and by CT_PUMAS_2020 below. Changing a label does not re-fetch
# data -- swap the corresponding source file (and CT list) to change a vintage.
PUMA_VINTAGE        <- 2022L # Geocorr puma22 (2020-Census-based PUMAs)
CBSA_ASSIGN_VINTAGE <- 2020L # Geocorr cbsa20 (CBSA assignment)
CBSA_TYPE_VINTAGE   <- 2023L # OMB delineation (M1 metro / M2 micro)
ACS_SAMPLE_LABEL    <- "2020-2024 ACS 5-year (IPUMS us2024c)"

# --- Assignment rule ---------------------------------------------------------
# 50% population rule: assign a PUMA to the single CBSA holding at least this
# share of the PUMA's 2020-Census population; otherwise the PUMA is non-metro.
PUMA_POP_THRESHOLD <- 0.50

# --- Connecticut -------------------------------------------------------------
# CT is patched from the IPUMS crosswalk because Geocorr 2022 lacks CT's 2022
# planning-region PUMAs. The 25 CT PUMAs (2020-Census vintage) are enumerated
# so any absent from the IPUMS crosswalk are emitted as non-metro. Revisit
# after the 2030 PUMA reapportionment.
CT_STATEFIP <- "09"
CT_PUMAS_2020 <- c(
  "20100",
  "20201", "20202", "20203", "20204", "20205", "20206", "20207",
  "20301",
  "20401", "20402",
  "20500",
  "20601", "20602", "20603", "20604",
  "20701", "20702", "20703",
  "20801", "20802",
  "20901", "20902", "20903", "20904"
)

# --- Output schema -----------------------------------------------------------
# Column contract for the crosswalk (order matters). Used by the tests.
CROSSWALK_COLS <- c(
  "puma_id", "statefip", "puma", "puma_name",
  "cbsa", "cbsa_name", "overlap_pct", "is_metro", "is_micro"
)

# --- Input paths (relative to repo root; wrapped in here() by build.R) --------
GEOCORR_FILE     <- file.path("data", "source", "geocorr2022_2609206408.csv")
IPUMS_CT_FILE    <- file.path("data", "source", "MSA2023_PUMA2020_crosswalk.xlsx")
DELINEATION_FILE <- file.path("data", "source", "delineation_2023.xlsx")

# --- Output paths ------------------------------------------------------------
OUTPUT_PARQUET <- file.path("data", "output", "puma_cbsa_crosswalk.parquet")
OUTPUT_CSV     <- file.path("data", "output", "puma_cbsa_crosswalk.csv")
