CREATE TABLE carriers (

	carrier_id varchar,
	carrier_name text,
	carrier_tier varchar,
	primary_region text
)

SELECT * FROM shipments

CREATE TABLE products (

	product_id varchar,
	product_name text,
	drug_category text,
	required_temp_min_c numeric,
	required_temp_max_c numeric,
	unit_value_usd numeric
	
)

CREATE TABLE routes (

	route_id varchar,
	origin_dc text,
	destination_region text,
	distance_miles numeric,
	standard_transit_days numeric
	
)

CREATE TABLE shipments (

	shipment varchar,
	product_id varchar,
	carrier_id varchar,
	route_id varchar,
	shipment_date date,
	promised_delivery_date date,
	actual_delivery_date date,
	quantity_shipped numeric,
	quantity_delivered numeric,
	shipment_value_usd numeric
	
)

ALTER TABLE shipments
RENAME COLUMN shipment TO shipment_id;

CREATE TABLE temperature_logs (

	log_id varchar,
	shipment_id varchar,
	reading_timestamp timestamp,
	recorded_temperature_c numeric,
	within_range boolean
	
)

-----------------------------------------------------------------------------------------------------------------

SELECT 'shipments' AS table_name, COUNT(*) FROM shipments
UNION ALL
SELECT 'temperature_logs', COUNT(*) FROM temperature_logs
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'carriers', COUNT(*) FROM carriers
UNION ALL
SELECT 'routes', COUNT(*) FROM routes;

-----------------------------------------------------------------------------------------------------------------
-- Data Validation

--NULL check on temperature readings
SELECT COUNT(*) AS null_temp_readings
FROM temperature_logs
WHERE recorded_temperature_c IS NULL;

--NULL check on within_range flag
SELECT COUNT(*) AS null_within_range
FROM temperature_logs
WHERE within_range IS NULL;

--Orphaned temperature logs (readings pointing to a shipment_id that doesn't exist in shipments)
SELECT COUNT(*) AS orphaned_logs
FROM temperature_logs tl
LEFT JOIN shipments s ON tl.shipment_id = s.shipment_id
WHERE s.shipment_id IS NULL;

--Date range check (confirm full 2022-2024 coverage, no stray dates outside range)
SELECT MIN(shipment_date) AS earliest, MAX(shipment_date) AS latest
FROM shipments;

--Duplicate shipment_id check (should be zero, shipment_id is meant to be unique)
SELECT shipment_id, COUNT(*)
FROM public.shipments
GROUP BY shipment_id
HAVING COUNT(*) > 1;

--Orphaned foreign keys in shipments (product_id, carrier_id, route_id that don't exist in their dimension tables)
SELECT
  (SELECT COUNT(*) FROM shipments s LEFT JOIN products p ON s.product_id = p.product_id WHERE p.product_id IS NULL) AS bad_products,
  (SELECT COUNT(*) FROM shipments s LEFT JOIN carriers c ON s.carrier_id = c.carrier_id WHERE c.carrier_id IS NULL) AS bad_carriers,
  (SELECT COUNT(*) FROM shipments s LEFT JOIN routes r ON s.route_id = r.route_id WHERE r.route_id IS NULL) AS bad_routes;


-----------------------------------------------------------------------------------------------------------------
--SQL Analysis

-- ============================================================================
-- Query 1: Annual Excursion Rate Baseline
-- Purpose: Establish the year-over-year excursion rate trend across all
--          shipments, 2022-2024. This is the foundational metric the rest
--          of the analysis (carrier, region, category breakdowns) builds on.
--
-- Data quality note: 168 temperature_logs rows have NULL recorded_temperature_c
-- (and correspondingly NULL within_range). These readings are excluded from
-- the analysis rather than treated as pass or fail, since we have no way of
-- knowing what the actual temperature was. 
-- ============================================================================

-- Step 1: Filter out the 168 null-temperature readings up front.
WITH valid_readings AS (
    SELECT
        shipment_id,
        within_range
    FROM temperature_logs
    WHERE recorded_temperature_c IS NOT NULL
),

-- Step 2: Collapse potentially many readings per shipment into a single
-- true/false flag per shipment: did this shipment have AT LEAST ONE
-- excursion reading anywhere in transit?
-- bool_or() returns TRUE if any row in the group evaluates to TRUE, which
-- is exactly the "any excursion at all" logic we want here.
shipment_flags AS (
    SELECT
        shipment_id,
        bool_or(within_range = FALSE) AS has_excursion
    FROM valid_readings
    GROUP BY shipment_id
)

-- Step 3: Join the per-shipment excursion flag back to the full shipments
-- table (LEFT JOIN) so that every shipment counts toward the
-- denominator, even in the edge case where a shipment has zero valid
-- readings at all. In that edge case, has_excursion comes back NULL, and
-- the CASE WHEN below treats NULL as "not an excursion" by default, which
-- is the safe, explicit choice rather than silently dropping the shipment.
SELECT
    EXTRACT(YEAR FROM s.shipment_date) AS year,

    -- Denominator: every shipment that occurred that year, regardless of
    -- whether it had any valid temperature readings.
    COUNT(DISTINCT s.shipment_id) AS total_shipments,

    -- Numerator: shipments where has_excursion = TRUE. NULL (no valid
    -- readings) and FALSE (all readings in range) both fall through to 0.
    SUM(CASE WHEN f.has_excursion THEN 1 ELSE 0 END) AS excursion_shipments,

    -- Excursion rate as a percentage, rounded to 2 decimal places for
    -- readability in the write-up.
    ROUND(
        100.0 * SUM(CASE WHEN f.has_excursion THEN 1 ELSE 0 END)
        / COUNT(DISTINCT s.shipment_id),
        2
    ) AS excursion_rate_pct

FROM shipments s
LEFT JOIN shipment_flags f ON s.shipment_id = f.shipment_id
GROUP BY EXTRACT(YEAR FROM s.shipment_date)
ORDER BY year;

-----------------------------------------------------------------------------------------------------------------

-- ============================================================================
-- Query 2: Excursion Rate by Carrier
-- Purpose: Query 1 established the overall excursion rate is rising
--          year over year (2.78% -> 3.13% -> 5.84%). This query breaks
--          that trend down by carrier to find out WHO is driving it.
-- ============================================================================

-- Step 1: exclude the 168 readings with no recorded temperature. We can't
-- classify a reading as pass or fail if we don't know what it was, so it's
-- dropped from the analysis entirely rather than assumed either way.
WITH valid_readings AS (
    SELECT shipment_id, within_range
    FROM temperature_logs
    WHERE recorded_temperature_c IS NOT NULL
),

-- Step 2: collapse potentially many temperature readings per shipment
-- into a single true/false flag: did this shipment have an excursion
-- ANYWHERE during transit? bool_or() returns TRUE if any row in the
-- group is TRUE, which is exactly the "at least one excursion" logic
-- we want, rather than requiring every reading to fail.
shipment_flags AS (
    SELECT shipment_id, bool_or(within_range = FALSE) AS has_excursion
    FROM valid_readings
    GROUP BY shipment_id
)

SELECT
    c.carrier_name,
    c.carrier_tier,

    -- Denominator: every shipment handled by this carrier, regardless of
    -- whether it had valid temperature readings. Matches the same logic
    -- used in Query 1's total_shipments column.
    COUNT(DISTINCT s.shipment_id) AS total_shipments,

    -- Numerator: shipments where has_excursion = TRUE. Shipments with no
    -- valid readings come through as NULL from the LEFT JOIN and are
    -- treated as "not an excursion" by the CASE WHEN.
    SUM(CASE WHEN f.has_excursion THEN 1 ELSE 0 END) AS excursion_shipments,

    -- Same percentage formula as Query 1, just grouped by carrier instead
    -- of by year.
    ROUND(
        100.0 * SUM(CASE WHEN f.has_excursion THEN 1 ELSE 0 END)
        / COUNT(DISTINCT s.shipment_id),
        2
    ) AS excursion_rate_pct

FROM shipments s
-- INNER JOIN is safe here (not LEFT JOIN) because every shipment in the
-- dataset has a valid carrier_id confirmed during the Phase 2 data audit
-- (zero orphaned foreign keys), so no shipments would be lost.
JOIN carriers c ON s.carrier_id = c.carrier_id
-- LEFT JOIN here, though, because we DO want to keep shipments that have
-- no entry in shipment_flags (i.e. no valid readings at all).
LEFT JOIN shipment_flags f ON s.shipment_id = f.shipment_id

GROUP BY c.carrier_name, c.carrier_tier
ORDER BY excursion_rate_pct DESC;

-----------------------------------------------------------------------------------------------------------------

-- ============================================================================
-- Query 3: Excursion Concentration in the Two Problem Carriers
-- Purpose: Query 2 showed Palmetto Cold Freight and Southwind Regional
--          Transport have the two highest INDIVIDUAL excursion rates.
--          This query answers a different question: of ALL excursions
--          across the entire carrier network, what SHARE is concentrated
--          in just these two carriers? A high individual rate and a high
--          share of total excursions are different claims, and this is
--          the number that tells you how much of the overall problem
--          would go away if these two relationships were fixed.
-- ============================================================================

-- Step 1: same NULL-exclusion as every prior query. Readings with no
-- recorded temperature carry no information, so they're filtered out
-- before anything else happens.
WITH valid_readings AS (
    SELECT shipment_id, within_range
    FROM temperature_logs
    WHERE recorded_temperature_c IS NOT NULL
),

-- Step 2: same shipment-level flag as before. bool_or() collapses
-- multiple readings per shipment into one true/false: did this shipment
-- have an excursion anywhere in transit?
shipment_flags AS (
    SELECT shipment_id, bool_or(within_range = FALSE) AS has_excursion
    FROM valid_readings
    GROUP BY shipment_id
),

-- Step 3: attach the carrier name to each shipment's excursion flag.
-- One row per shipment now, with everything we need to do the grouping
-- in the final SELECT.
shipment_carrier AS (
    SELECT
        s.shipment_id,
        c.carrier_name,
        f.has_excursion
    FROM shipments s
    JOIN carriers c ON s.carrier_id = c.carrier_id
    LEFT JOIN shipment_flags f ON s.shipment_id = f.shipment_id
)

SELECT
    -- Bucket every shipment's carrier into one of two labeled groups.
    -- Same CASE WHEN pattern used throughout this project, just applied
    -- to carrier_name instead of a boolean flag.
    CASE
        WHEN carrier_name IN ('Palmetto Cold Freight', 'Southwind Regional Transport')
            THEN 'Two flagged carriers'
        ELSE 'All other carriers'
    END AS carrier_group,

    -- Excursion count within each group (this part is a normal GROUP BY
    -- aggregate, collapses to one number per carrier_group).
    SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END) AS excursion_shipments,

    -- This is the key difference from a normal aggregate: SUM(...) OVER ()
    -- is a WINDOW function. Instead of collapsing to one total per group,
    -- it computes the SUM across every row in the entire result set and
    -- repeats that same grand total on every output row. 
    ROUND(
        100.0 * SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END)
        / SUM(SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END)) OVER (),
        2
    ) AS pct_of_total_excursions

FROM shipment_carrier
GROUP BY carrier_group
ORDER BY pct_of_total_excursions DESC;

-----------------------------------------------------------------------------------------------------------------

-- ============================================================================
-- Query 4: Excursion Rate by Destination Region and Route Distance
-- Purpose: This query checks both geographic patterns at once by grouping on
--          region AND a distance bucket, so we can see whether the effects
--          are independent of each other or compound (e.g. is a long-haul
--          Southeast route worse than either factor alone would predict?).
-- ============================================================================

WITH valid_readings AS (
    SELECT shipment_id, within_range
    FROM temperature_logs
    WHERE recorded_temperature_c IS NOT NULL
),
shipment_flags AS (
    SELECT shipment_id, bool_or(within_range = FALSE) AS has_excursion
    FROM valid_readings
    GROUP BY shipment_id
),

-- Attach region and distance to each shipment via its route, and bucket
-- distance into short-haul vs long-haul using the 800-mile threshold.
-- Doing the bucketing here (rather than in the final
-- SELECT) keeps the GROUP BY clause below simple and readable.
shipment_route AS (
    SELECT
        s.shipment_id,
        r.destination_region,
        CASE
            WHEN r.distance_miles > 800 THEN 'Long-haul (800+ mi)'
            ELSE 'Short-haul (under 800 mi)'
        END AS distance_bucket,
        f.has_excursion
    FROM shipments s
    JOIN routes r ON s.route_id = r.route_id
    LEFT JOIN shipment_flags f ON s.shipment_id = f.shipment_id
)

SELECT
    destination_region,
    distance_bucket,
    COUNT(DISTINCT shipment_id) AS total_shipments,
    SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END) AS excursion_shipments,
    ROUND(
        100.0 * SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END)
        / COUNT(DISTINCT shipment_id),
        2
    ) AS excursion_rate_pct

FROM shipment_route
GROUP BY destination_region, distance_bucket
-- Order by region first so the two distance buckets for each region sit
-- next to each other, making the short-haul vs long-haul gap easy to spot
-- for any single region, then by rate within that.
ORDER BY destination_region, distance_bucket;

-----------------------------------------------------------------------------------------------------------------

-- ============================================================================
-- Query 5: Carrier Concentration Within the Southeast/Southwest, Long-Haul Slice
-- Purpose: Query 3 showed the two flagged carriers (Palmetto Cold Freight,
--          Southwind Regional Transport) cause 57.5% of ALL excursions
--          network-wide. Query 4 shows Southeast/Southwest and
--          long-haul routes have elevated rates too. This query tests
--          whether those are actually the SAME finding wearing two hats:
--          are the two flagged carriers simply the ones who happen to run
--          most of the Southeast/Southwest long-haul routes, meaning
--          carrier is the true root cause and region/distance are just
--          correlated with it? Or is the region/distance effect still
--          present even among the OTHER 8 carriers, meaning there are two
--          genuinely separate problems?
-- ============================================================================

WITH valid_readings AS (
    SELECT shipment_id, within_range
    FROM temperature_logs
    WHERE recorded_temperature_c IS NOT NULL
),
shipment_flags AS (
    SELECT shipment_id, bool_or(within_range = FALSE) AS has_excursion
    FROM valid_readings
    GROUP BY shipment_id
),

-- Pull together everything needed in one place: which carrier, which
-- region, how far the route was, and whether the shipment had an
-- excursion. One row per shipment.
shipment_detail AS (
    SELECT
        s.shipment_id,
        c.carrier_name,
        r.destination_region,
        r.distance_miles,
        f.has_excursion
    FROM shipments s
    JOIN carriers c ON s.carrier_id = c.carrier_id
    JOIN routes r ON s.route_id = r.route_id
    LEFT JOIN shipment_flags f ON s.shipment_id = f.shipment_id
)

SELECT
    -- Same two-bucket carrier split as Query 3.
    CASE
        WHEN carrier_name IN ('Palmetto Cold Freight', 'Southwind Regional Transport')
            THEN 'Two flagged carriers'
        ELSE 'All other carriers'
    END AS carrier_group,

    -- Restrict this query's scope to high-risk: Southeast or Southwest destination, 
    -- AND a long-haul route. Filtering here (in the CASE, not a WHERE clause)
    -- keeps shipment_detail reusable for other queries if needed later.
    CASE
        WHEN destination_region IN ('Southeast', 'Southwest') AND distance_miles > 800
            THEN 'Southeast/Southwest, long-haul'
        ELSE 'All other region/distance combinations'
    END AS region_distance_group,

    COUNT(DISTINCT shipment_id) AS total_shipments,
    SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END) AS excursion_shipments,
    ROUND(
        100.0 * SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END)
        / COUNT(DISTINCT shipment_id),
        2
    ) AS excursion_rate_pct

FROM shipment_detail
-- Grouping by BOTH bucketed dimensions at once produces a 2x2 grid:
-- flagged/other carriers crossed with SE-SW-longhaul/everything-else.
-- That 2x2 shape is exactly what answers the root-cause question: if the
-- "All other carriers" row within "Southeast/Southwest, long-haul" still
-- shows a meaningfully elevated rate compared to "All other carriers"
-- within "All other combinations", the region/distance effect is real
-- and independent of the two flagged carriers. If it's flat, the region
-- effect was really just the two carriers' geographic footprint all along.
GROUP BY carrier_group, region_distance_group
ORDER BY carrier_group, region_distance_group;

-----------------------------------------------------------------------------------------------------------------

-- ============================================================================
-- Query 6: Excursion Rate by Product Category
-- Purpose: This query tests whether that clinical sensitivity
--          shows up as a measurably higher excursion rate in the data.
-- ============================================================================

-- Step 1: exclude the 168 readings with no recorded temperature, same as
-- every prior query. Unknown readings carry no information either way.
WITH valid_readings AS (
    SELECT shipment_id, within_range
    FROM temperature_logs
    WHERE recorded_temperature_c IS NOT NULL
),

-- Step 2: collapse each shipment's (possibly many) readings into one
-- true/false flag. bool_or() returns TRUE the moment any single reading
-- in the group failed, which is the "any excursion during transit"
-- definition used consistently across this whole analysis.
shipment_flags AS (
    SELECT shipment_id, bool_or(within_range = FALSE) AS has_excursion
    FROM valid_readings
    GROUP BY shipment_id
),

-- Step 3: attach each shipment's drug_category by joining to products
-- on product_id, the foreign key that links shipments to the products
-- dimension table (confirmed as a clean, non-orphaned relationship
-- during the Phase 2 data audit).
shipment_product AS (
    SELECT
        s.shipment_id,
        p.drug_category,
        f.has_excursion
    FROM shipments s
    JOIN products p ON s.product_id = p.product_id
    -- LEFT JOIN here (not INNER) because shipment_flags only contains
    -- shipments with at least one valid reading. A shipment with zero
    -- valid readings would otherwise disappear from this analysis
    -- instead of correctly counting toward the denominator with
    -- has_excursion = NULL.
    LEFT JOIN shipment_flags f ON s.shipment_id = f.shipment_id
)

SELECT
    drug_category,

    -- Denominator: every shipment in this category, regardless of
    -- whether it had valid temperature readings.
    COUNT(DISTINCT shipment_id) AS total_shipments,

    -- Numerator: shipments where has_excursion = TRUE. NULL (no valid
    -- readings at all) and FALSE (fully in range) both count as 0 here,
    -- the same safe default used in every earlier query.
    SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END) AS excursion_shipments,

    -- Same percentage formula used in every query so far: excursions
    -- divided by total shipments, times 100, rounded for readability.
    ROUND(
        100.0 * SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END)
        / COUNT(DISTINCT shipment_id),
        2
    ) AS excursion_rate_pct

FROM shipment_product
GROUP BY drug_category
-- Highest-risk category first, since that's the finding most likely to
-- lead the write-up.
ORDER BY excursion_rate_pct DESC;

-----------------------------------------------------------------------------------------------------------------

-- ============================================================================
-- Query 7: Excursion Rate by Quarter (Q3 Seasonal Heat Stress)
-- Purpose: This query tests that by bucketing
--          every shipment into "Q3" vs "all other months" and comparing
--          rates, then breaks the same comparison out by year so we can
--          see whether the seasonal spike is getting worse over time
--          too, not just the annual average.
-- ============================================================================

WITH valid_readings AS (
    SELECT shipment_id, within_range
    FROM temperature_logs
    WHERE recorded_temperature_c IS NOT NULL
),
shipment_flags AS (
    SELECT shipment_id, bool_or(within_range = FALSE) AS has_excursion
    FROM valid_readings
    GROUP BY shipment_id
),

-- Extract year and month from each shipment's date, and bucket month
-- into "Q3" (Jul, Aug, Sep) vs everything else. Doing this once here
-- keeps both the year-level and quarter-level grouping below simple.
shipment_season AS (
    SELECT
        s.shipment_id,
        EXTRACT(YEAR FROM s.shipment_date) AS year,
        CASE
            WHEN EXTRACT(MONTH FROM s.shipment_date) IN (7, 8, 9) THEN 'Q3 (Jul-Sep)'
            ELSE 'Rest of year'
        END AS season_bucket,
        f.has_excursion
    FROM shipments s
    LEFT JOIN shipment_flags f ON s.shipment_id = f.shipment_id
)

SELECT
    year,
    season_bucket,
    COUNT(DISTINCT shipment_id) AS total_shipments,
    SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END) AS excursion_shipments,
    ROUND(
        100.0 * SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END)
        / COUNT(DISTINCT shipment_id),
        2
    ) AS excursion_rate_pct

FROM shipment_season
GROUP BY year, season_bucket
-- Year first, then season, so Q3 sits directly next to "rest of year"
-- for each year, making the seasonal gap easy to read and compare
-- across years at the same time.
ORDER BY year, season_bucket;

-----------------------------------------------------------------------------------------------------------------
-- ============================================================================
-- Query 8: Financial Impact Query
-- Purpose: Every prior query measured excursions as a RATE (percentage of
--          shipments affected). This query converts that into a DOLLAR
--          figure: the total value of product that traveled in a
--          shipment which experienced a temperature excursion, treated
--          as a spoilage-risk cost. It also introduces a RUNNING total
--          per carrier, so you can see cumulative financial exposure
--          building year over year, not just each year in isolation.
--
-- Note: this reuses the same shipment_flags pattern from every prior
-- query rather than the briefing's original JOIN + SELECT DISTINCT
-- approach, since routing through the pre-aggregated shipment-level flag
-- avoids ever materializing a multiplied join against temperature_logs
-- (where a single shipment can have many reading rows) before collapsing
-- it back down. Same result, cheaper and safer to reason about.
-- ============================================================================

WITH valid_readings AS (
    SELECT shipment_id, within_range
    FROM temperature_logs
    WHERE recorded_temperature_c IS NOT NULL
),
shipment_flags AS (
    SELECT shipment_id, bool_or(within_range = FALSE) AS has_excursion
    FROM valid_readings
    GROUP BY shipment_id
),

-- Pull together only the shipments that actually had an excursion, along
-- with their carrier, year, and dollar value. This is the "at-risk"
-- population for the financial calculation, every shipment here is one
-- where the product's cold chain was broken at least once in transit.
excursion_shipments AS (
    SELECT
        s.shipment_id,
        s.carrier_id,
        EXTRACT(YEAR FROM s.shipment_date) AS year,
        s.shipment_value_usd
    FROM shipments s
    JOIN shipment_flags f ON s.shipment_id = f.shipment_id
    WHERE f.has_excursion = TRUE
)

SELECT
    c.carrier_name,
    e.year,

    -- How many excursion shipments this carrier had in this specific
    -- year (not cumulative, just this year's count).
    COUNT(*) AS excursion_count,

    -- Total dollar value of product shipped in an excursion shipment,
    -- for this carrier, in this specific year only.
    SUM(e.shipment_value_usd) AS total_spoilage_cost,

    -- RUNNING total: SUM(...) OVER (PARTITION BY ... ORDER BY ...) adds
    -- up total_spoilage_cost across all years UP TO AND INCLUDING the
    -- current row, but resets back to zero for each new carrier because
    -- of PARTITION BY carrier_name. So for Palmetto, 2024's value here
    -- is 2022 + 2023 + 2024 combined; for the next carrier, the running
    -- total starts over from that carrier's own 2022 figure. This is
    -- what shows cumulative financial exposure building over time,
    -- rather than just a snapshot of each year alone.
    SUM(SUM(e.shipment_value_usd)) OVER (
        PARTITION BY c.carrier_name
        ORDER BY e.year
    ) AS running_spoilage_total

FROM excursion_shipments e
JOIN carriers c ON e.carrier_id = c.carrier_id
GROUP BY c.carrier_name, e.year
ORDER BY c.carrier_name, e.year;

-----------------------------------------------------------------------------------------------------------------
-- ============================================================================
-- Query 9: Excursion Rate by Quarter, All Three Years (for View 1 trend line)
-- Purpose: Phase 8 calls for a trend line showing excursion rate by
--          quarter across all three years, with each year color-coded
--          separately, so the Q3 spike is visible as a repeating bump
--          in the same place on the X-axis every year (rather than one
--          long continuously rising line, which would visually bury the
--          seasonal pattern inside the overall upward trend). This query
--          produces exactly that shape: one row per year-quarter
--          combination, ready to plot with quarter on the X-axis and
--          year as the color/series field in Tableau.
-- ============================================================================

WITH valid_readings AS (
    SELECT shipment_id, within_range
    FROM temperature_logs
    WHERE recorded_temperature_c IS NOT NULL
),
shipment_flags AS (
    SELECT shipment_id, bool_or(within_range = FALSE) AS has_excursion
    FROM valid_readings
    GROUP BY shipment_id
),

-- EXTRACT(QUARTER FROM ...) does the same job as the month-bucketing
-- CASE statement from Query 7, but gives us all four quarters at once
-- instead of just isolating Q3 vs everything else, which is what the
-- trend line needs.
shipment_quarter AS (
    SELECT
        s.shipment_id,
        EXTRACT(YEAR FROM s.shipment_date) AS year,
        EXTRACT(QUARTER FROM s.shipment_date) AS quarter,
        f.has_excursion
    FROM shipments s
    LEFT JOIN shipment_flags f ON s.shipment_id = f.shipment_id
)

SELECT
    year,
    quarter,
    COUNT(DISTINCT shipment_id) AS total_shipments,
    SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END) AS excursion_shipments,
    ROUND(
        100.0 * SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END)
        / COUNT(DISTINCT shipment_id),
        2
    ) AS excursion_rate_pct

FROM shipment_quarter
GROUP BY year, quarter
-- Year then quarter, so Tableau can read this straight into a line chart
-- with quarter on X, year as color, no reshaping needed.
ORDER BY year, quarter;

-----------------------------------------------------------------------------------------------------------------
-- ============================================================================
-- Query 10: Excursion Rate by Region Only (for View 1 heat map)
-- Purpose: Phase 8 calls for a filled US map showing excursion rate by
--          region alone, not split by distance bucket. This is
--          deliberately NOT derived by averaging the two distance-bucket
--          rows from Query 4, since a simple average of two percentages
--          would weight short-haul and long-haul equally regardless of
--          how many shipments were actually in each bucket, which is a
--          weighted-average error. This query sums the raw shipment and
--          excursion counts across all routes into a region first, and
--          divides once at the end, which is the mathematically correct
--          way to combine rates that are based on different-sized groups.
-- ============================================================================

WITH valid_readings AS (
    SELECT shipment_id, within_range
    FROM temperature_logs
    WHERE recorded_temperature_c IS NOT NULL
),
shipment_flags AS (
    SELECT shipment_id, bool_or(within_range = FALSE) AS has_excursion
    FROM valid_readings
    GROUP BY shipment_id
),

-- Attach only destination_region here, no distance bucketing this time,
-- since the heat map needs one rate per region, full stop.
shipment_region AS (
    SELECT
        s.shipment_id,
        r.destination_region,
        f.has_excursion
    FROM shipments s
    JOIN routes r ON s.route_id = r.route_id
    LEFT JOIN shipment_flags f ON s.shipment_id = f.shipment_id
)

SELECT
    destination_region,
    COUNT(DISTINCT shipment_id) AS total_shipments,
    SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END) AS excursion_shipments,
    ROUND(
        100.0 * SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END)
        / COUNT(DISTINCT shipment_id),
        2
    ) AS excursion_rate_pct

FROM shipment_region
GROUP BY destination_region
-- Highest rate first, so it's immediately obvious which region should
-- render darkest on the heat map before you even open Tableau.
ORDER BY excursion_rate_pct DESC;

-----------------------------------------------------------------------------------------------------------------
-- ============================================================================
-- Query 11: Excursion Rate by Carrier-Route Combination (for View 2 scatter)
-- Purpose: Phase 9 calls for a scatter plot where each dot is one
--          carrier-route combination, X-axis is route distance, Y-axis
--          is excursion rate. Every prior query aggregated by carrier
--          ALONE or by route/region ALONE, never both together at once,
--          so this is a genuinely new grain of aggregation: one row per
--          (carrier, route) pair that actually had shipments, not per
--          carrier and not per route individually.
--
-- Note on grain: with 10 carriers and 50 routes, the theoretical maximum
-- is 500 combinations, but not every carrier actually shipped on every
-- route (shipments were randomly assigned), so expect meaningfully fewer
-- than 500 rows back, only real, observed carrier-route pairs appear.
-- ============================================================================

WITH valid_readings AS (
    SELECT shipment_id, within_range
    FROM temperature_logs
    WHERE recorded_temperature_c IS NOT NULL
),
shipment_flags AS (
    SELECT shipment_id, bool_or(within_range = FALSE) AS has_excursion
    FROM valid_readings
    GROUP BY shipment_id
),

shipment_carrier_route AS (
    SELECT
        s.shipment_id,
        c.carrier_name,
        c.carrier_tier,
        r.route_id,
        r.distance_miles,
        f.has_excursion
    FROM shipments s
    JOIN carriers c ON s.carrier_id = c.carrier_id
    JOIN routes r ON s.route_id = r.route_id
    LEFT JOIN shipment_flags f ON s.shipment_id = f.shipment_id
)

SELECT
    carrier_name,
    carrier_tier,
    route_id,
    distance_miles,
    COUNT(DISTINCT shipment_id) AS total_shipments,
    SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END) AS excursion_shipments,
    ROUND(
        100.0 * SUM(CASE WHEN has_excursion THEN 1 ELSE 0 END)
        / COUNT(DISTINCT shipment_id),
        2
    ) AS excursion_rate_pct

FROM shipment_carrier_route
GROUP BY carrier_name, carrier_tier, route_id, distance_miles
-- Filter out combinations with too few shipments to produce a
-- statistically meaningful rate (1 excursion out of 3 shipments = 33%,
-- which would dominate the scatter plot visually without meaning much).
HAVING COUNT(DISTINCT shipment_id) >= 10
ORDER BY distance_miles;

-----------------------------------------------------------------------------------------------------------------
-- ============================================================================
-- Query 12: Average Spoilage Cost per Excursion, by Product Category
-- Purpose: Phase 9's product category table needs both the excursion
--          rate (already have this from Query 6) AND the average dollar
--          cost per excursion, by category. Average per excursion, not
--          total cost, is the right comparison here: a category could
--          have a high total just because it ships more often, but
--          average cost per incident tells you how expensive a single
--          excursion tends to be in that category.
-- ============================================================================

WITH valid_readings AS (
    SELECT shipment_id, within_range
    FROM temperature_logs
    WHERE recorded_temperature_c IS NOT NULL
),
shipment_flags AS (
    SELECT shipment_id, bool_or(within_range = FALSE) AS has_excursion
    FROM valid_readings
    GROUP BY shipment_id
),

excursion_shipments AS (
    SELECT
        s.shipment_id,
        p.drug_category,
        s.shipment_value_usd
    FROM shipments s
    JOIN products p ON s.product_id = p.product_id
    JOIN shipment_flags f ON s.shipment_id = f.shipment_id
    WHERE f.has_excursion = TRUE
)

SELECT
    drug_category,
    COUNT(*) AS excursion_count,
    SUM(shipment_value_usd) AS total_spoilage_cost,
    ROUND(AVG(shipment_value_usd), 2) AS avg_spoilage_cost_per_excursion

FROM excursion_shipments
GROUP BY drug_category
ORDER BY avg_spoilage_cost_per_excursion DESC;