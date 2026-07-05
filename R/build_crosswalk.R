# R/build_crosswalk.R
# Build the PUMA-to-CBSA crosswalk used by the NLIHC Gap Report 2026
# replication, as a single self-contained function.
#
# Method (see README.md for the full narrative):
#   1. Geocorr 2022 gives, for every 2022 PUMA, the 2020-Census population
#      share (allocation factor) falling in each 2020-vintage CBSA.
#   2. 50% population rule: assign each PUMA to the single CBSA holding
#      >= 50% of its population; otherwise the PUMA is "Non-metropolitan".
#   3. Connecticut is dropped from Geocorr (which lacks CT's 2022
#      planning-region PUMAs) and rebuilt from the IPUMS MSA2023-PUMA2020
#      crosswalk; the 25 CT PUMAs (passed in from config.R) are enumerated so
#      any not present in that crosswalk are added as non-metropolitan.
#   4. Metropolitan vs micropolitan status comes from the OMB July 2023
#      delineation file (LSAD-equivalent M1 = metro, M2 = micro).
#
# This mirrors code/04_build_crosswalk.R from the parent gap-report pipeline
# exactly, with one deliberate change: the metro/micro classification is read
# from the bundled delineation file instead of a live tigris download, so the
# build is fully offline and deterministic. The two produce identical output
# (verified by a row-for-row diff of the resulting crosswalk).
#
# Self-contained: this file does not source config.R. Callers (build.R, the
# tests) pass every vintage/path/rule in as an argument.

suppressPackageStartupMessages({
  library(readr)
  library(readxl)
  library(dplyr)
  library(stringr)
})

# Geocorr's sentinel CBSA code meaning "not in any CBSA".
GEOCORR_NONMETRO_CBSA <- "99999"

# Left zero-pad helper (state FIPS is 2-wide; PUMA and CBSA codes are 5-wide).
zero_pad <- function(x, width) str_pad(x, width, "left", "0")

# --- Step 1: Geocorr 2022 (all states except Connecticut) --------------------
# Note: readr emits a benign "one or more parsing issues" warning here -- the
# Geocorr file's second row is a text description of each column, so the numeric
# columns (pop20, afact) fail col_double() on that single row. We drop it with
# slice(-1) immediately below, so the warning concerns only discarded data.
load_geocorr <- function(geocorr_path) {
  read_csv(
    geocorr_path,
    col_types = cols(
      state      = col_character(),
      puma22     = col_character(),
      cbsa20     = col_character(),
      stab       = col_character(),
      CBSAName20 = col_character(),
      PUMA22name = col_character(),
      pop20      = col_double(),
      afact      = col_double()
    )
  ) |>
    slice(-1) |> # drop the Geocorr description row
    mutate(
      statefip   = zero_pad(state, 2),
      puma       = zero_pad(puma22, 5),
      puma_id    = paste0(statefip, puma),
      cbsa       = if_else(cbsa20 == GEOCORR_NONMETRO_CBSA, NA_character_, cbsa20),
      cbsa_name  = if_else(cbsa20 == GEOCORR_NONMETRO_CBSA, "Non-metropolitan", CBSAName20),
      puma_name  = PUMA22name,
      pop_weight = afact
    ) |>
    select(statefip, puma, puma_id, cbsa, cbsa_name, puma_name, pop_weight)
}

# --- Step 2: Connecticut patch from the IPUMS crosswalk ----------------------
load_ct_patch <- function(ipums_ct_path, ct_statefip, ct_pumas) {
  ct <- read_xlsx(ipums_ct_path) |>
    filter(`State FIPS Code` == ct_statefip) |>
    mutate(
      statefip   = ct_statefip,
      puma       = zero_pad(`PUMA Code`, 5),
      puma_id    = paste0(statefip, puma),
      cbsa       = if_else(is.na(`MSA Code`), NA_character_, `MSA Code`),
      cbsa_name  = if_else(is.na(`MSA Title`), "Non-metropolitan", `MSA Title`),
      puma_name  = `PUMA Name`,
      pop_weight = `Percent PUMA Population` / 100
    ) |>
    select(statefip, puma, puma_id, cbsa, cbsa_name, puma_name, pop_weight)

  # Any CT PUMAs absent from the IPUMS crosswalk are added as non-metro.
  missing_pumas <- setdiff(ct_pumas, ct$puma)
  if (length(missing_pumas) > 0) {
    ct <- bind_rows(ct, tibble(
      statefip   = ct_statefip,
      puma       = missing_pumas,
      puma_id    = paste0(ct_statefip, missing_pumas),
      cbsa       = NA_character_,
      cbsa_name  = "Non-metropolitan",
      puma_name  = NA_character_,
      pop_weight = 1.0
    ))
  }
  ct
}

# --- Step 3: 50% population rule ---------------------------------------------
# Assign each PUMA to the CBSA holding its largest population share, keeping the
# assignment only when that share meets the threshold; every other PUMA is
# non-metropolitan. Returns one row per PUMA.
assign_pumas_to_cbsa <- function(combined, pop_threshold) {
  best_cbsa <- combined |>
    filter(!is.na(cbsa)) |>
    group_by(puma_id, statefip, puma, puma_name) |>
    summarise(
      cbsa                = cbsa[which.max(pop_weight)],
      cbsa_name           = cbsa_name[which.max(pop_weight)],
      best_cbsa_pop_share = max(pop_weight),
      .groups             = "drop"
    )

  metro <- best_cbsa |>
    filter(best_cbsa_pop_share >= pop_threshold) |>
    transmute(
      puma_id, statefip, puma, puma_name, cbsa, cbsa_name,
      overlap_pct = best_cbsa_pop_share
    )

  non_metro <- combined |>
    distinct(puma_id, statefip, puma, puma_name) |>
    filter(!puma_id %in% metro$puma_id) |>
    mutate(cbsa = NA_character_, cbsa_name = "Non-metropolitan", overlap_pct = NA_real_)

  bind_rows(metro, non_metro)
}

# --- Step 4: metro (M1) vs micro (M2) from the OMB delineation file ----------
# Returns a named character vector of LSAD-equivalent codes keyed by CBSA code,
# mirroring the shape tigris::core_based_statistical_areas() would return so the
# downstream is_micro expression is identical.
load_cbsa_types <- function(delineation_path) {
  # The delineation file has two title rows above the real header (row 3).
  types <- read_xlsx(delineation_path, skip = 2) |>
    transmute(
      cbsa = zero_pad(as.character(`CBSA Code`), 5),
      lsad = case_when(
        `Metropolitan/Micropolitan Statistical Area` ==
          "Metropolitan Statistical Area" ~ "M1",
        `Metropolitan/Micropolitan Statistical Area` ==
          "Micropolitan Statistical Area" ~ "M2",
        TRUE ~ NA_character_
      )
    ) |>
    filter(!is.na(cbsa), !is.na(lsad)) |>
    distinct(cbsa, lsad)
  setNames(types$lsad, types$cbsa)
}

# Print the metro / micro / non-metro breakdown after a build.
log_crosswalk_summary <- function(crosswalk) {
  cat("\n", strrep("=", 56), "\n", sep = "")
  cat("PUMA-CBSA CROSSWALK SUMMARY\n")
  cat(strrep("=", 56), "\n")
  cat("Total PUMAs:    ", nrow(crosswalk), "\n")
  cat("  Metropolitan: ", sum(crosswalk$is_metro & !crosswalk$is_micro, na.rm = TRUE), "\n")
  cat("  Micropolitan: ", sum(crosswalk$is_micro, na.rm = TRUE), "\n")
  cat("  Non-metro:    ", sum(!crosswalk$is_metro), "\n")
}

# --- Orchestrator ------------------------------------------------------------
build_puma_cbsa_crosswalk <- function(geocorr_path,
                                      ipums_ct_path,
                                      delineation_path,
                                      pop_threshold,
                                      ct_statefip,
                                      ct_pumas,
                                      verbose = TRUE) {
  say <- function(...) if (verbose) cat(...)

  say("Loading Geocorr crosswalk...\n")
  geocorr <- load_geocorr(geocorr_path) |> filter(statefip != ct_statefip)

  say("Patching Connecticut from the IPUMS MSA-PUMA crosswalk...\n")
  ct <- load_ct_patch(ipums_ct_path, ct_statefip, ct_pumas)

  combined <- bind_rows(geocorr, ct)
  say("  Total PUMAs after CT patch:", n_distinct(combined$puma_id), "\n")

  say("Applying the ", round(pop_threshold * 100), "% population rule...\n", sep = "")
  assigned <- assign_pumas_to_cbsa(combined, pop_threshold)

  say("Classifying metro (M1) vs micro (M2) from the OMB delineation file...\n")
  cbsa_types <- load_cbsa_types(delineation_path)
  crosswalk <- assigned |>
    mutate(
      is_metro = !is.na(cbsa),
      is_micro = is_metro & cbsa_types[cbsa] == "M2"
    ) |>
    arrange(statefip, puma)

  # Ensure valid UTF-8 for parquet/DuckDB consumers.
  crosswalk$cbsa_name <- iconv(crosswalk$cbsa_name, to = "UTF-8", sub = "?")
  crosswalk$puma_name <- iconv(crosswalk$puma_name, to = "UTF-8", sub = "?")

  if (verbose) log_crosswalk_summary(crosswalk)
  crosswalk
}
