SELECT
    'green_taxi_row_count' AS check_name,
    COUNT(*) AS observed,
    0 AS expected,
    COUNT(*) > 0 AS passed
FROM read_parquet(
    'https://d37ci6vzurychx.cloudfront.net/trip-data/green_tripdata_2026-03.parquet'
);
