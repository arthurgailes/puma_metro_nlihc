# PUMA-to-CBSA Crosswalk

Assigns every Census PUMA (Public Use Microdata Area) to a CBSA (a metropolitan
or micropolitan area), so ACS microdata keyed to PUMAs can be aggregated to
metro geographies.

This crosswalk was built to replicate the geographic approach in the National
Low Income Housing Coalition's report *The Gap: A Shortage of Affordable Homes*.
The methodology is NLIHC's; please cite them (see [Citation](#citation)).

The built crosswalk is in [`data/output/`](data/output/) as parquet and CSV, so
you can use it without running R. The build reads three files in
[`data/source/`](data/source/) and needs no network access.

## Columns

One row per PUMA (2,486 rows), keyed by `puma_id`. Full definitions are in
[`data/output/data_dictionary.md`](data/output/data_dictionary.md).

| Column | Meaning |
| --- | --- |
| `puma_id` | Join key: `statefip` (2) + `puma` (5), zero-padded |
| `statefip`, `puma` | State FIPS and PUMA code (2022 vintage) |
| `puma_name`, `cbsa`, `cbsa_name` | Names and assigned CBSA (2020 vintage). `cbsa` is `NA` and `cbsa_name` is "Non-metropolitan" when unassigned |
| `overlap_pct` | PUMA population share in the assigned CBSA (0.50 to 1.00) |
| `is_metro` | In any CBSA (metropolitan or micropolitan) |
| `is_micro` | Micropolitan only |

Metropolitan PUMAs are `is_metro & !is_micro`.

## Using it

Rebuild the key from IPUMS/ACS `STATEFIP` and `PUMA`, then left-join:

```r
library(dplyr); library(stringr); library(arrow)
xwalk <- read_parquet("data/output/puma_cbsa_crosswalk.parquet")

acs |>
  mutate(puma_id = paste0(str_pad(STATEFIP, 2, "left", "0"),
                          str_pad(PUMA, 5, "left", "0"))) |>
  left_join(xwalk, by = "puma_id")
```

Use a left join so records in non-metro PUMAs (which have `cbsa = NA`) are kept.
To list the PUMAs in a CBSA, filter on `cbsa`. Non-R users can read the CSV.

## Rebuilding

```bash
Rscript build.R        # writes data/output/{parquet,csv}
Rscript run_tests.R    # checks the crosswalk
```

Paths, the 50% threshold, and the Connecticut PUMA list are set in
[`config.R`](config.R).

## Method

1. Geocorr 2022 gives each 2022 PUMA's population share in each 2020 CBSA. A
   PUMA is assigned to the CBSA holding at least 50% of its population;
   otherwise it is non-metro. `overlap_pct` is that share.
2. Geocorr 2022 omits Connecticut, which replaced counties with nine planning
   regions in 2022. CT is taken from IPUMS USA's MSA2023-PUMA2020 crosswalk;
   its 25 PUMAs are listed in `config.R`.
3. Metropolitan vs micropolitan status is read from the OMB July 2023
   delineation file.

## Vintages

| Element | Vintage | Source |
| --- | --- | --- |
| PUMA geography | 2022 | Geocorr `puma22` |
| CBSA assignment | 2020 | Geocorr `cbsa20` |
| Metro/micro type | 2023 | OMB delineation |
| ACS sample | 2020-2024 5-year | IPUMS `us2024c` |

Sixteen CBSAs assigned from the 2020 delineation are absent from the 2023
delineation, so 35 PUMAs have `is_micro = NA` (metro status assigned; the
metro/micro split is unknown). See the data dictionary.

## Caveats

The crosswalk is one row per PUMA, so a left join never duplicates your
microdata rows. The cautions below are about geographic approximation and
vintage alignment, not join fan-out.

- **Whole-PUMA assignment approximates metros.** Each PUMA is assigned entirely
  to one CBSA (or to none), even when it straddles a metro boundary. A metro
  gains the full population of every PUMA assigned to it -- including any part
  that lives outside the CBSA -- and loses PUMAs that fall below the 50%
  threshold. Metro counts are close to, but will not exactly equal, published
  CBSA totals. `overlap_pct` shows how clean each assignment is: a PUMA at 0.51
  is far more approximate than one at 1.00.
- **Non-metro is a residual, not a place.** `cbsa = NA` ("Non-metropolitan")
  pools genuinely rural PUMAs with split PUMAs that cleared 50% for no single
  CBSA, so non-metro counts absorb the leakage from the point above and are
  correspondingly overstated.
- **Match the PUMA vintage to your data.** `puma_id` uses 2022
  (2020-Census-based) PUMAs, which match the 2020-2024 ACS 5-year and later
  5-year samples built on 2020 PUMAs. Joining to ACS data on a different PUMA
  vintage (for example 2010-based PUMAs) silently drops or mis-maps rows and
  corrupts any count. Confirm your sample's PUMA vintage first.
- **Handle `is_micro = NA` when splitting metro from micro.** 35 PUMAs (16
  CBSAs) have `is_micro = NA` (see Vintages). `is_metro & !is_micro` returns NA
  for them, so a strict metropolitan filter drops them; use
  `is_metro & (is.na(is_micro) | !is_micro)` or decide explicitly how to count
  them.
- **Connecticut uses a different source.** CT assignments come from the IPUMS
  MSA2023-PUMA2020 crosswalk (each PUMA mapped wholesale to one MSA), not the
  Geocorr 50% rule, and its `overlap_pct` is an IPUMS population percentage. CT
  metro assignments are not strictly comparable to the other states'.
- **CBSA level only.** Multi-division metros such as New York and Los Angeles
  are assigned at the CBSA level, not by metropolitan division; this crosswalk
  cannot split a CBSA into divisions.

## Dependencies

R >= 4.3 with `arrow`, `dplyr`, `readr`, `readxl`, `stringr`, `here`, and
`testthat` for the tests:

```r
install.packages(c("arrow", "dplyr", "readr", "readxl", "stringr", "here", "testthat"))
```

## Citation

This crosswalk supports a replication of NLIHC's methodology. Cite the report:

> National Low Income Housing Coalition. *The Gap: A Shortage of Affordable
> Homes.* Washington, DC. https://nlihc.org/gap

Data sources: Geocorr 2022 (Missouri Census Data Center); CBSA delineation
(U.S. Census Bureau / OMB); Connecticut crosswalk (IPUMS USA,
https://usa.ipums.org/usa/terms.shtml).

## License

Code is MIT-licensed (see [LICENSE](LICENSE)). Built by the AEI Housing Center.
