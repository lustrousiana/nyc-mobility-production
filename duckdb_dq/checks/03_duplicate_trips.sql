WITH dupes AS (
    SELECT
        VendorID,
        lpep_pickup_datetime,
        lpep_dropoff_datetime,
        PULocationID,
        DOLocationID,
        COUNT(*) AS n
    FROM read_parquet(
        'https://d37ci6vzurychx.cloudfront.net/trip-data/green_tripdata_2026-03.parquet'
    )
    GROUP BY 1,2,3,4,5
    HAVING COUNT(*) > 1
)

SELECT
    'duplicate_trips' AS check_name,
    COUNT(*) AS observed,
    0 AS expected,
    COUNT(*) = 0 AS passed
FROM dupes;
