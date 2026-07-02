# PUMA-to-CBSA Crosswalk

A standalone, single-source-of-truth build of the **PUMA -> CBSA crosswalk** used
in the AEI Housing Center's replication of the [NLIHC Gap Report
2026](https://nlihc.org/gap). It assigns every Census **PUMA** (Public Use
Microdata Area) to a **CBSA** (Core-Based Statistical Area, i.e. a metropolitan or
micropolitan area) so that ACS microdata keyed to PUMAs can be rolled up to metro
geographies.

The crosswalk is the deliverable. It lives, already built, at
[`data/output/puma_cbsa_crosswalk.parquet`](data/output/puma_cbsa_crosswalk.parquet)
and [`.csv`](data/output/puma_cbsa_crosswalk.csv) -- you can consume it directly
without running any R. The build is **fully offline and deterministic**: three
small input files in [`data/source/`](data/source/) reproduce it exactly, with no
downloads or API keys.

> Extracted from the AEI Housing Center gap-report project so future projects can
> depend on one authoritative crosswalk. Rebuild any time with `Rscript build.R`.

## What it contains

One row per PUMA (2,486 rows), keyed by `puma_id`. Each row gives the PUMA's
assigned CBSA (or non-metropolitan), the population overlap that justified the
assignment, and metro-vs-micro status. Full column definitions and headline
counts are in [`data/output/data_dictionary.md`](data/output/data_dictionary.md).

| Column | Meaning |
| ------ | ------- |
| `puma_id` | 7-char join key = `statefip`(2) + `puma`(5), zero-padded |
| `statefip`, `puma` | State FIPS and PUMA code (2022 vintage) |
| `puma_name`, `cbsa`, `cbsa_name` | Names and assigned CBSA code (2020 vintage); `cbsa` is `NA` and `cbsa_name` is `"Non-metropolitan"` when unassigned |
| `overlap_pct` | PUMA population share in the assigned CBSA, in [0.50, 1.00] |
| `is_metro` | in any CBSA (metro OR micro) |
| `is_micro` | micropolitan only (OMB type M2) |

True metropolitan PUMAs are `is_metro & !is_micro`.

## Using the crosswalk

**From IPUMS / ACS microdata** -- rebuild the same 7-character key from `STATEFIP`
and `PUMA`, then left-join:

```r
library(dplyr); library(stringr); library(arrow)
xwalk <- read_parquet("data/output/puma_cbsa_crosswalk.parquet")

acs |>
  mutate(puma_id = paste0(
    str_pad(STATEFIP, 2, "left", "0"),
    str_pad(PUMA,     5, "left", "0")
  )) |>
  left_join(xwalk, by = "puma_id")   # non-metro / unmatched PUMAs keep cbsa = NA
```

Always **left**-join so records in non-metropolitan PUMAs are preserved (they
carry `cbsa = NA`), not dropped.

**Which PUMAs make up a CBSA?** The file is one-row-per-PUMA; group by `cbsa` to
invert it:

```r
xwalk |> filter(cbsa == "31080") |> select(puma_id, puma_name, overlap_pct)
# all PUMAs assigned to Los Angeles-Long Beach-Anaheim, CA
```

**Non-R consumers** can read `data/output/puma_cbsa_crosswalk.csv` directly.

## Rebuilding

```bash
Rscript build.R        # writes data/output/{parquet,csv}
Rscript run_tests.R    # checks the crosswalk invariants
```

Everything that can vary between vintages -- input paths, the 50% threshold, the
Connecticut state FIPS -- lives in [`config.R`](config.R). Edit it, re-run
`build.R`, and the crosswalk is regenerated. The build takes a few seconds.

## Methodology

1. **50% population rule.** [Geocorr
   2022](https://mcdc.missouri.edu/applications/geocorr2022.html) gives, for each
   2022 PUMA, the 2020-Census population share falling in each 2020-vintage CBSA.
   Each PUMA is assigned to the single CBSA holding **>= 50%** of its population;
   otherwise it is non-metropolitan. `overlap_pct` records that winning share.
2. **Connecticut patch.** Geocorr 2022 lacks Connecticut, which replaced counties
   with nine planning regions (Councils of Governments) as its county-equivalents
   in 2022. CT is therefore dropped from Geocorr and rebuilt from IPUMS USA's
   MSA2023-PUMA2020 crosswalk. The 25 CT PUMAs are enumerated in
   `R/build_crosswalk.R` so any absent from that crosswalk are emitted as
   non-metropolitan.
3. **Metro vs micro.** Metropolitan (OMB type M1) vs micropolitan (M2) status
   comes from the OMB July 2023 delineation file. (The parent pipeline read this
   from a live `tigris` download; this repo reads the bundled delineation file
   instead, for offline reproducibility -- the two yield identical `is_micro`
   values.)

## Vintages and reproducibility

| Element | Vintage | Source |
| ------- | ------- | ------ |
| PUMA geography | 2022 (2020-Census based) | Geocorr `puma22` |
| CBSA assignment | 2020 OMB delineation | Geocorr `cbsa20` |
| Metro/micro type | 2023 OMB delineation | `delineation_2023.xlsx` |
| Intended ACS sample | 2020-2024 ACS 5-year (IPUMS `us2024c`) | -- |

These are pinned to the FY2023 HUD / 2020-2024 ACS run that the NLIHC Gap Report
2026 benchmarks were computed against. The Connecticut PUMA list and the metro/
micro delineation year are the knobs to revisit after the 2030 PUMA
reapportionment. Note the mild vintage seam documented in the data dictionary:
16 CBSAs assigned from the 2020 delineation are absent from the 2023 delineation,
so 35 PUMAs carry `is_micro = NA` (metropolitan status assigned, micro/metro split
unavailable) -- reproduced faithfully from the parent pipeline.

## Dependencies

R >= 4.3 and: `arrow`, `dplyr`, `readr`, `readxl`, `stringr`, `here` (plus
`testthat` for the tests). No `sf` or `tigris` -- the build is offline.

```r
install.packages(c("arrow", "dplyr", "readr", "readxl", "stringr", "here", "testthat"))
```

## Layout

```
puma_cbsa_crosswalk/
  config.R                 # vintages, paths, and the 50% rule (edit here)
  build.R                  # entry point: build + write parquet/csv
  R/build_crosswalk.R      # the build logic
  data/
    source/                # 3 bundled inputs (+ provenance README)
    output/                # the committed crosswalk (parquet + csv + dictionary)
  tests/testthat/          # invariant tests
  run_tests.R
```

## Sharing

This is a self-contained git repository. To publish it, add a remote and push:

```bash
git remote add origin <your-remote-url>
git push -u origin main
```

## License and attribution

Code is MIT-licensed (see [LICENSE](LICENSE)). Methodology follows the NLIHC *Gap*
report. Geocorr is provided by the Missouri Census Data Center; the delineation
file is U.S. Census Bureau / OMB (public domain); the Connecticut crosswalk is
distributed by IPUMS USA under its
[terms of use](https://usa.ipums.org/usa/terms.shtml). Built by the AEI Housing
Center.
