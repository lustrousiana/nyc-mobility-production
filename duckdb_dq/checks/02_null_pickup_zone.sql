SELECT
    'null_pickup_zone' AS check_name,
    COUNT(*) FILTER (WHERE PULocationID IS NULL) AS observed,
    0 AS expected,
    COUNT(*) FILTER (WHERE PULocationID IS NULL) = 0 AS passed
FROM read_parquet(
    'https://d37ci6vzurychx.cloudfront.net/trip-data/green_tripdata_2026-03.parquet'
);