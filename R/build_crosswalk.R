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
#      crosswalk; the 25 CT PUMAs are enumerated so any not present in that
#      crosswalk are added as non-metropolitan.
#   4. Metropolitan vs micropolitan status comes from the OMB July 2023
#      delineation file (LSAD-equivalent M1 = metro, M2 = micro).
#
# This mirrors code/04_build_crosswalk.R from the parent gap-report pipeline
# exactly, with one deliberate change: the metro/micro classification is read
# from the bundled delineation file instead of a live tigris download, so the
# build is fully offline and deterministic. The two produce identical output
# (verified by a row-for-row diff of the resulting crosswalk).

suppressPackageStartupMessages({
  library(readr)
  library(readxl)
  library(dplyr)
  library(stringr)
})

# The 25 Connecticut PUMAs (2020-Census vintage, planning-region based).
# Enumerated so CT PUMAs absent from the IPUMS crosswalk are still emitted as
# non-metropolitan. Revisit after the 2030 PUMA reapportionment.
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

# --- Step 1: Geocorr 2022 (all states except Connecticut) --------------------
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
      statefip   = str_pad(state, 2, "left", "0"),
      puma       = str_pad(puma22, 5, "left", "0"),
      puma_id    = paste0(statefip, puma),
      cbsa       = if_else(cbsa20 == "99999", NA_character_, cbsa20),
      cbsa_name  = if_else(cbsa20 == "99999", "Non-metropolitan", CBSAName20),
      puma_name  = PUMA22name,
      pop_weight = afact
    ) |>
    select(statefip, puma, puma_id, cbsa, cbsa_name, puma_name, pop_weight)
}

# --- Step 2: Connecticut patch from the IPUMS crosswalk ----------------------
load_ct_patch <- function(ipums_ct_path, ct_statefip) {
  ct <- read_xlsx(ipums_ct_path) |>
    filter(`State FIPS Code` == ct_statefip) |>
    mutate(
      statefip   = ct_statefip,
      puma       = str_pad(`PUMA Code`, 5, "left", "0"),
      puma_id    = paste0(statefip, puma),
      cbsa       = if_else(is.na(`MSA Code`), NA_character_, `MSA Code`),
      cbsa_name  = if_else(is.na(`MSA Title`), "Non-metropolitan", `MSA Title`),
      puma_name  = `PUMA Name`,
      pop_weight = `Percent PUMA Population` / 100
    ) |>
    select(statefip, puma, puma_id, cbsa, cbsa_name, puma_name, pop_weight)

  # Any of the 25 CT PUMAs absent from the IPUMS crosswalk are non-metro.
  ct_all_ids <- paste0(ct_statefip, CT_PUMAS_2020)
  ct_missing <- setdiff(ct_all_ids, ct$puma_id)
  if (length(ct_missing) > 0) {
    ct <- bind_rows(
      ct,
      tibble(
        statefip   = ct_statefip,
        puma       = substr(ct_missing, 3, 7),
        puma_id    = ct_missing,
        cbsa       = NA_character_,
        cbsa_name  = "Non-metropolitan",
        puma_name  = NA_character_,
        pop_weight = 1.0
      )
    )
  }
  ct
}

# --- Step 4: metro (M1) vs micro (M2) from the OMB delineation file ----------
# Returns a named character vector of LSAD-equivalent codes keyed by CBSA code,
# mirroring the shape tigris::core_based_statistical_areas() would return so the
# downstream is_micro expression is identical.
load_cbsa_types <- function(delineation_path) {
  # The delineation file has two title rows above the real header (row 3).
  types <- read_xlsx(delineation_path, skip = 2) |>
    transmute(
      cbsa = str_pad(as.character(`CBSA Code`), 5, "left", "0"),
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

# --- Orchestrator ------------------------------------------------------------
build_puma_cbsa_crosswalk <- function(geocorr_path,
                                      ipums_ct_path,
                                      delineation_path,
                                      pop_threshold = 0.50,
                                      ct_statefip = "09",
                                      verbose = TRUE) {
  say <- function(...) if (verbose) cat(...)

  say("Loading Geocorr crosswalk...\n")
  geocorr <- load_geocorr(geocorr_path) |> filter(statefip != ct_statefip)

  say("Patching Connecticut from the IPUMS MSA-PUMA crosswalk...\n")
  ct <- load_ct_patch(ipums_ct_path, ct_statefip)

  combined <- bind_rows(geocorr, ct)
  say("  Total PUMAs after CT patch:", n_distinct(combined$puma_id), "\n")

  # --- Step 3: 50% population rule -------------------------------------------
  say("Applying the ", round(pop_threshold * 100), "% population rule...\n", sep = "")
  puma_cbsa_shares <- combined |>
    filter(!is.na(cbsa)) |>
    group_by(puma_id, statefip, puma, puma_name) |>
    summarise(
      cbsa               = cbsa[which.max(pop_weight)],
      cbsa_name          = cbsa_name[which.max(pop_weight)],
      best_cbsa_pop_share = max(pop_weight),
      .groups            = "drop"
    )

  puma_assignments <- puma_cbsa_shares |>
    filter(best_cbsa_pop_share >= pop_threshold) |>
    transmute(
      puma_id, statefip, puma, puma_name, cbsa, cbsa_name,
      overlap_pct = best_cbsa_pop_share
    )

  all_pumas <- combined |> distinct(puma_id, statefip, puma, puma_name)
  pumas_no_cbsa <- all_pumas |>
    filter(!puma_id %in% puma_assignments$puma_id) |>
    mutate(cbsa = NA_character_, cbsa_name = "Non-metropolitan", overlap_pct = NA_real_)

  # --- Step 4: metro/micro classification ------------------------------------
  say("Classifying metro (M1) vs micro (M2) from the OMB delineation file...\n")
  cbsa_types <- load_cbsa_types(delineation_path)

  crosswalk <- bind_rows(puma_assignments, pumas_no_cbsa) |>
    mutate(
      is_metro = !is.na(cbsa),
      is_micro = is_metro & cbsa_types[cbsa] == "M2"
    ) |>
    arrange(statefip, puma)

  # Ensure valid UTF-8 for parquet/DuckDB consumers.
  crosswalk$cbsa_name <- iconv(crosswalk$cbsa_name, to = "UTF-8", sub = "?")
  crosswalk$puma_name <- iconv(crosswalk$puma_name, to = "UTF-8", sub = "?")

  if (verbose) {
    cat("\n", strrep("=", 56), "\n", sep = "")
    cat("PUMA-CBSA CROSSWALK SUMMARY\n")
    cat(strrep("=", 56), "\n")
    cat("Total PUMAs:    ", nrow(crosswalk), "\n")
    cat("  Metropolitan: ", sum(crosswalk$is_metro & !crosswalk$is_micro, na.rm = TRUE), "\n")
    cat("  Micropolitan: ", sum(crosswalk$is_micro, na.rm = TRUE), "\n")
    cat("  Non-metro:    ", sum(!crosswalk$is_metro), "\n")
  }

  crosswalk
}
