# data/source/

The three inputs that fully determine the crosswalk. All are bundled with the
repository, so the build is completely offline -- no downloads, no API keys, no
network dependency. Nothing else is read.

## Bundled inputs

| File | Bytes | What it is | Used for | Where it came from |
| ---- | ----- | ---------- | -------- | ------------------ |
| `geocorr2022_2609206408.csv` | ~380KB | PUMA-to-CBSA population-weighted crosswalk: for every 2022 PUMA, the 2020-Census population share (`afact`) in each 2020-vintage CBSA. | Primary input. Drives the 50% population assignment for all states except Connecticut. | Generated at <https://mcdc.missouri.edu/applications/geocorr2022.html> (source: PUMA 2022; target: CBSA 2020; weight: 2020 population). |
| `MSA2023_PUMA2020_crosswalk.xlsx` | ~227KB | IPUMS USA's MSA2023 -> PUMA2020 crosswalk with per-PUMA population shares. | Connecticut only. Geocorr 2022 omits CT's 2022 planning-region PUMAs, so CT is rebuilt from this file. | Distributed by IPUMS USA: <https://usa.ipums.org/usa/volii/state_county_metro.shtml> (see "Boundary files / crosswalks"). |
| `delineation_2023.xlsx` | ~144KB | OMB Core-Based Statistical Area delineation file, July 2023. Column E classifies each CBSA as Metropolitan or Micropolitan. | Metro (M1) vs micro (M2) flag. Replaces a live `tigris` download so the build is offline; produces identical `is_micro` values. | <https://www2.census.gov/programs-surveys/metro-micro/geographies/reference-files/2023/delineation-files/list1_2023.xlsx> |

## Column contracts

If you swap in a newer export, keep these columns (the build reads them by name):

- **Geocorr CSV** (a description row sits under the header and is dropped by the
  build): `state`, `puma22`, `cbsa20`, `stab`, `CBSAName20`, `PUMA22name`,
  `pop20`, `afact`. CBSA code `99999` is the "not in any CBSA" sentinel.
- **IPUMS CT xlsx**: `State FIPS Code`, `PUMA Code`, `PUMA Name`, `MSA Code`,
  `MSA Title`, `Percent PUMA Population`.
- **Delineation xlsx** (two title rows precede the header on row 3):
  `CBSA Code`, `Metropolitan/Micropolitan Statistical Area`.

To rebuild after a swap, update the corresponding path/vintage in `../../config.R`
and run `Rscript ../../build.R`.
