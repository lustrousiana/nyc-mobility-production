-- ============================================================
-- EXTRA: What's the average fare-per-mile by borough?
--
-- Stage:      06 Analytics
-- Runs after: etl/05_gold/90_validate_gold.sql
-- Target:     `ftw-week-08`.`06-analytics`.fare_efficiency_by_borough
-- Grain:      one row per PICKUP borough
-- Source:     Gold only. Analytics never reads Silver or Bronze.
--
-- Value/efficiency question, not a volume or weather one: how much a
-- rider pays per mile traveled, not how many trips happened.
--
-- fare_per_mile_usd = SUM(eligible fare) / SUM(eligible distance),
-- NOT AVG(each trip's own fare/distance ratio) -- sum-of-sums keeps a
-- handful of short, high-fare trips (e.g. flat airport fares) from
-- skewing the result the way averaging individual ratios would.
--
-- A trip's fare only contributes if fare_eligible; a trip's distance
-- only contributes if distance_eligible AND > 0. trip_count itself is
-- never filtered, so it still reconciles 1:1 against Gold.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS `ftw-week-08`.`06-analytics`;

CREATE OR REPLACE TABLE `ftw-week-08`.`06-analytics`.fare_efficiency_by_borough AS

WITH trips AS (
    SELECT
        f.pickup_zone_key,
        f.trip_count,
        f.trip_distance_miles,
        f.fare_amount_usd,
        (NOT f.negative_trip_distance_flag AND f.trip_distance_miles > 0)
            AS distance_eligible,
        NOT f.negative_fare_amount_flag AS fare_eligible
    FROM `ftw-week-08`.`05-gold`.fact_taxi_trip AS f
)

SELECT
    z.borough AS pickup_borough,

    SUM(t.trip_count) AS trip_count,

    SUM(CASE WHEN t.fare_eligible THEN t.fare_amount_usd END)
        AS total_fare_amount_usd,
    SUM(CASE WHEN t.distance_eligible THEN t.trip_distance_miles END)
        AS total_trip_distance_miles,

    ROUND(
        SUM(CASE WHEN t.fare_eligible THEN t.fare_amount_usd END)
        / NULLIF(SUM(CASE WHEN t.distance_eligible THEN t.trip_distance_miles END), 0)
    , 2) AS fare_per_mile_usd,

    ROUND(SUM(CASE WHEN t.fare_eligible THEN t.fare_amount_usd END)
          / NULLIF(COUNT_IF(t.fare_eligible), 0), 2) AS avg_fare_amount_usd,

    ROUND(SUM(CASE WHEN t.distance_eligible THEN t.trip_distance_miles END)
          / NULLIF(COUNT_IF(t.distance_eligible), 0), 3) AS avg_trip_distance_miles,

    DENSE_RANK() OVER (
        ORDER BY
            SUM(CASE WHEN t.fare_eligible THEN t.fare_amount_usd END)
            / NULLIF(SUM(CASE WHEN t.distance_eligible THEN t.trip_distance_miles END), 0)
            DESC
    ) AS fare_per_mile_rank

FROM trips AS t
LEFT JOIN `ftw-week-08`.`05-gold`.dim_taxi_zone AS z
    ON t.pickup_zone_key = z.zone_key

GROUP BY z.borough;


-- Data quality gate: analytics totals must reconcile back to Gold,
-- and every borough should resolve to a real name (no unmatched zones).
SELECT
    (SELECT SUM(trip_count) FROM `ftw-week-08`.`06-analytics`.fare_efficiency_by_borough)
        AS analytics_trip_count,
    (SELECT SUM(trip_count) FROM `ftw-week-08`.`05-gold`.fact_taxi_trip)
        AS gold_trip_count,
    (SELECT COUNT(*) FROM `ftw-week-08`.`06-analytics`.fare_efficiency_by_borough)
        AS result_rows,
    (SELECT COUNT_IF(pickup_borough IS NULL)
     FROM `ftw-week-08`.`06-analytics`.fare_efficiency_by_borough)
        AS rows_with_unresolved_borough;