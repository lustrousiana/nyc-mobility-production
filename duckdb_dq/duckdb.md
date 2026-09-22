# How I Added DuckDB Source-Level Data Quality Checks to a Databricks Project

Today I worked on our **FTW Week 08 NYC Mobility project**, focusing on adding **DuckDB as an independent source-level data quality validation tool**.

The purpose was not to replace our existing Databricks validation. Instead, DuckDB adds another validation point that runs outside Databricks and checks the raw source file before the data enters the Bronze, Silver, and Gold layers.

## Table of Contents

1. #part-1-what-is-duckdb
2. #part-2-why-add-duckdb
3. #part-3-where-does-duckdb-run
4. #part-4-duckdb-vs-databricks-validation
5. #part-5-creating-the-duckdb-folder-structure
6. #part-6-adding-duckdb-as-a-dependency
7. #part-7-creating-the-duckdb-connection
8. #part-8-creating-the-sql-checks
9. #part-9-creating-the-check-runner
10. #part-10-running-the-checks
11. [Understandingstanding-the-results
12. #part-12-what-data-was-and-was-not-validated
13. #part-13-why-the-duplicate-failure-is-useful
14. [Possible Futuree-future-improvements
15. #what-i-learned

The overall DuckDB flow is:

```text
Raw source parquet
        ↓
DuckDB reads the file directly
        ↓
SQL data-quality checks
        ↓
Pass/Fail results
        ↓
evidence/proof/duckdb/results.json
```

No Databricks cluster is involved in the current DuckDB validation flow.

---

# Part 1: What is DuckDB?

**DuckDB** is an analytical database that can run inside a Python process and execute SQL directly against files such as parquet files.

The important DuckDB feature used in this implementation is:

```sql
FROM read_parquet(...)
```

This allows DuckDB to query a parquet file directly without first loading it into a Databricks or Delta table.

The basic flow is:

```text
Source parquet
      ↓
DuckDB
      ↓
SQL checks
      ↓
results.json
```

For this implementation, DuckDB runs using the Python virtual environment in the local repository.

---

# Part 2: Why Add DuckDB?

Our project already had data-quality checks inside Databricks.

The existing pipeline follows the medallion architecture:

```text
Green Taxi
Taxi Zones
Weather
     ↓
Bronze
     ↓
Silver
     ↓
Gold
     ↓
Databricks validation
```

Most of our previous validation occurred after the data had already entered the pipeline.

For example:

```text
Source
   ↓
Bronze
   ↓
Spark validation
```

or:

```text
Silver
   ↓
Data-quality checks
```

The DuckDB implementation adds an earlier and independent validation point:

```text
Raw source file
      ↓
DuckDB source validation
      ↓
Databricks ingestion
      ↓
Bronze
      ↓
Silver
      ↓
Gold
```

The important distinction is:

```text
Databricks validation = validates pipeline tables and outputs

DuckDB validation = validates the source file directly
```

DuckDB helps answer the following question:

> Did a data-quality issue already exist in the source, or was it introduced during ingestion or transformation?

---

# Part 3: Where Does DuckDB Run?

The DuckDB checks run outside Databricks.

For the current implementation, they run locally from the repository:

```text
Local repository
      ↓
Python virtual environment
      ↓
DuckDB
      ↓
Remote parquet source
      ↓
SQL validation results
```

The checks are executed using:

```powershell
.\.venv\Scripts\python.exe .\duckdb_dq\run_checks.py
```

This command uses the Python executable inside the project's `.venv` folder.

DuckDB then reads the Green Taxi parquet file directly from its public source URL.

The current implementation is therefore:

```text
Public Green Taxi parquet
          ↓
Local DuckDB process
          ↓
SQL checks
          ↓
Local results.json
```

It is important to clarify that the current implementation does **not** read from R2.

It also does **not** read from the Databricks Bronze, Silver, or Gold layers.

It reads directly from the public Green Taxi parquet source.

---

# Part 4: DuckDB vs Databricks Validation

| Area | Existing Databricks Validation | DuckDB Validation |
|---|---|---|
| Engine | Spark and Databricks | DuckDB |
| Runs where | Databricks workspace and cluster | Local Python process |
| Main validation point | After ingestion and transformation | Before Databricks ingestion |
| Layer checked | Bronze, Silver, and Gold | Raw source file |
| Data read | Databricks or Delta tables | Parquet file directly |
| Main purpose | Validate pipeline tables and transformed outputs | Validate source quality independently |
| Output | Notebook results, validation output, or pipeline evidence | `results.json` |
| Infrastructure | Databricks environment | Local virtual environment |
| Current scope | Multiple pipeline datasets and layers | March 2026 Green Taxi parquet only |
| Relationship | Main pipeline validation | Additional source-validation proof of concept |

The two approaches complement each other:

```text
DuckDB checks the source
          +
Databricks checks the pipeline
          =
Better visibility into where an issue originated
```

DuckDB does not replace Great Expectations or the existing Databricks checks.

DuckDB adds another point of comparison.

---

# Part 5: Creating the DuckDB Folder Structure

I created the following folder structure:

```text
duckdb_dq/
├── checks/
│   ├── 01_row_count.sql
│   ├── 02_null_pickup_zone.sql
│   └── 03_duplicate_trips.sql
├── connection.py
└── run_checks.py
```

The generated validation evidence is stored under:

```text
evidence/
└── proof/
    └── duckdb/
        └── results.json
```

The `checks` folder should keep its current name because `run_checks.py` explicitly references it:

```python
CHECKS_DIR = pathlib.Path(__file__).parent / "checks"
```

If the folder were renamed, the path in `run_checks.py` would also need to be updated.

The individual SQL files can be renamed to make their purpose clearer.

For example:

```text
checks/
├── 01_green_taxi_row_count.sql
├── 02_green_taxi_null_pickup_zone.sql
└── 03_green_taxi_duplicate_trips.sql
```

The runner would still find them because it searches for every file ending in `.sql`.

---

# Part 6: Adding DuckDB as a Dependency

DuckDB was added to:

```text
requirements-dev.txt
```

The dependency added was:

```text
duckdb==1.1.3
```

DuckDB was installed in the local virtual environment using:

```powershell
.\.venv\Scripts\python.exe -m pip install duckdb==1.1.3
```

The installation was verified using:

```powershell
.\.venv\Scripts\python.exe -m pip show duckdb
```

The installed version was:

```text
1.1.3
```

Using the Python executable inside `.venv` was important because DuckDB needed to be installed in the same Python environment used to run the checks.

---

# Part 7: Creating the DuckDB Connection

## Where?

```text
duckdb_dq/connection.py
```

## Code

```python
import duckdb


def connect():
    return duckdb.connect()
```

## What does this code do?

The following line creates a DuckDB connection:

```python
duckdb.connect()
```

In this proof of concept, DuckDB runs inside the current Python process.

The connection is returned to `run_checks.py`, which uses it to execute the SQL check files.

The flow is:

```text
run_checks.py
      ↓
connect()
      ↓
DuckDB connection
      ↓
Execute SQL files
```

---

# Part 8: Creating the SQL Checks

Three SQL checks were created for:

```text
green_tripdata_2026-03.parquet
```

The checks were based on common source-validation requirements:

```text
Row count
Required-field null check
Duplicate detection
```

## Check 1: Green Taxi Row Count

### Where?

```text
duckdb_dq/checks/01_row_count.sql
```

### Code

```sql
SELECT
    'green_taxi_row_count' AS check_name,
    COUNT(*) AS observed,
    0 AS expected,
    COUNT(*) > 0 AS passed
FROM read_parquet(
    'https://d37ci6vzurychx.cloudfront.net/trip-data/green_tripdata_2026-03.parquet'
);
```

### What does it do?

The query reads the parquet file and counts all records:

```sql
COUNT(*)
```

The check passes when the file contains more than zero rows:

```sql
COUNT(*) > 0
```

The returned columns mean:

```text
check_name = name of the validation rule
observed   = actual row count
expected   = comparison baseline recorded in the evidence
passed     = whether the row count is greater than zero
```

Current result:

```text
Observed rows: 44,208
Passed: true
```

The `expected` value is shown as `0`, but the rule is not checking whether the row count equals zero.

The actual pass condition is:

```text
Row count must be greater than zero
```

## Check 2: Null Pickup Zone

### Where?

```text
duckdb_dq/checks/02_null_pickup_zone.sql
```

### Code

```sql
SELECT
    'null_pickup_zone' AS check_name,
    COUNT(*) FILTER (
        WHERE PULocationID IS NULL
    ) AS observed,
    0 AS expected,
    COUNT(*) FILTER (
        WHERE PULocationID IS NULL
    ) = 0 AS passed
FROM read_parquet(
    'https://d37ci6vzurychx.cloudfront.net/trip-data/green_tripdata_2026-03.parquet'
);
```

### What does it do?

This query counts records where:

```text
PULocationID IS NULL
```

`PULocationID` represents the pickup location identifier in the Green Taxi data.

The check expects:

```text
0 null pickup location IDs
```

The returned values mean:

```text
observed = actual number of null PULocationID values
expected = zero null values
passed   = true only when the null count equals zero
```

Current result:

```text
Observed nulls: 0
Expected nulls: 0
Passed: true
```

## Check 3: Duplicate Trips

### Where?

```text
duckdb_dq/checks/03_duplicate_trips.sql
```

### Code

```sql
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
    GROUP BY 1, 2, 3, 4, 5
    HAVING COUNT(*) > 1
)
SELECT
    'duplicate_trips' AS check_name,
    COUNT(*) AS observed,
    0 AS expected,
    COUNT(*) = 0 AS passed
FROM dupes;
```

### What does it do?

The query creates duplicate groups based on the following fields:

```text
VendorID
lpep_pickup_datetime
lpep_dropoff_datetime
PULocationID
DOLocationID
```

The following clause groups records using those five fields:

```sql
GROUP BY 1, 2, 3, 4, 5
```

The following clause keeps combinations that appear more than once:

```sql
HAVING COUNT(*) > 1
```

The outer query then co*nts the number of duplicate groups*

```sql
COUNT(*) AS observed
```
*The check expects:

```text
0 dupl*cate groups
```

The check passes *nly when:

```sql
COUNT(*) = 0
```*
Current result:

```text
Observed*duplicate groups: 112
Expected dup*icate groups: 0
Passed: false
```
*This means DuckDB found 112 repeat*d combinations based on the five f*elds used in the query.

It does n*t automatically mean that exactly *12 individual rows should be delet*d.

The result represents 112 dupl*cate groups under this specific du*licate definition. The definition *hould be compared with the duplica*e or business-key rule documented *y the project.

---

# Part 9: Cre*ting the Check Runner

## Where?

*``text
duckdb_dq/run_checks.py
```*
## Purpose

The runner performs t*e following steps:

1. Connects to*DuckDB.
2. Finds all SQL files in *he `checks` folder.
3. Sorts the SQL files by filename.
4. Executes each SQL file.
5. Collects the returned values.
6. Writes the results to JSON.
7. Prints the results in the terminal.

The checks folder is defined using:

```python
CHECKS_DIR = pathlib.Path(__file__).parent / "checks"
```

The output location is defined using:

```python
OUTPUT_PATH = pathlib.Path(
    "evidence/proof/duckdb/results.json"
)
```

The following loop finds and executes all `.sql` files:

```python
for sql_file in sorted(CHECKS_DIR.glob("*.sql")):
    result = con.execute(
        sql_file.read_text()
    ).fetchone()
```

The result of each query is added to a Python list:

```python
results.append(
    {
        "check": result[0],
        "observed": result[1],
        "expected": result[2],
        "passed": bool(result[3]),
    }
)
```

The JSON output directory is created using:

```python
OUTPUT_PATH.parent.mkdir(
    parents=True,
    exist_ok=True
)
```

The results are written using:

```python
OUTPUT_PATH.write_text(
    json.dumps(results, indent=2)
)
```

Because the runner uses:

```python
CHECKS_DIR.glob("*.sql")
```

additional SQL check files can be added to the `checks` folder later without manually listing every filename inside the Python script.

---

# Part 10: Running the Checks

The checks are run from the root of the repository using:

```powershell
.\.venv\Scripts\python.exe .\duckdb_dq\run_checks.py
```

The full process is:

```text
Run run_checks.py
       ↓
Create DuckDB connection
       ↓
Find SQL files
       ↓
Execute SQL checks
       ↓
Collect observed and expected values
       ↓
Calculate Pass/Fail
       ↓
Write results.json
       ↓
Print results in the terminal
```

A successful script execution does not mean every data-quality check passed.

It only means the validation process was able to run.

The distinction is:

```text
Execution success
        ≠
All data-quality rules passed
```

---

# Part 11: Understanding the Results

The generated evidence file is:

```text
evidence/proof/duckdb/results.json
```

The current results are:

```json
[
  {
    "check": "green_taxi_row_count",
    "observed": 44208,
    "expected": 0,
    "passed": true
  },
  {
    "check": "null_pickup_zone",
    "observed": 0,
    "expected": 0,
    "passed": true
  },
  {
    "check": "duplicate_trips",
    "observed": 112,
    "expected": 0,
    "passed": false
  }
]
```

The results can be summarized as:

| Check | Observed | Expected | Result |
|---|---:|---:|---|
| Green Taxi row count | 44,208 | Greater than 0 | Pass |
| Null pickup zone | 0 | 0 | Pass |
| Duplicate trip groups | 112 | 0 | Fail |

The JSON file provides compact evidence of what DuckDB observed when the checks were executed.

---

# Part 12: What Data Was and Was Not Validated

## Validated by the current DuckDB proof of concept

The current implementation validates:

```text
green_tripdata_2026-03.parquet
```

It checks:

```text
Row count
Null PULocationID values
Duplicate Green Taxi trip-key combinations
```

## Not validated by the current DuckDB proof of concept

The current implementation does not validate:

```text
April 2026 Green Taxi parquet
May 2026 Green Taxi parquet
Taxi Zones source
Weather source
Bronze Green Taxi table
Silver Green Taxi table
Gold fact table
Other Bronze, Silver, or Gold tables
Databricks job execution
```

The current DuckDB implementation is therefore a focused proof of concept.

It demonstrates that DuckDB can independently validate a raw Green Taxi parquet file.

It does not yet provide complete DuckDB validation for every source in the NYC Mobility project.

---

# Part 13: Why the Duplicate Failure Is Useful

The duplicate check returned:

```text
Observed: 112
Expected: 0
Passed: false
```

This does not mean the DuckDB implementation failed.

The implementation successfully:

```text
Read the parquet file
       ↓
Executed the duplicate SQL query
       ↓
Found matching duplicate groups
       ↓
Returned the observed value
       ↓
Compared it with the expected value
       ↓
Marked the check as failed
       ↓
Stored the result in results.json
```

This is the difference between an execution failure and a data-quality failure:

```text
Execution failure
=
The validation could not run correctly

Data-quality failure
=
The validation ran correctly, but the data did not meet the rule
```

The duplicate result is a **data-quality check failure**, not a DuckDB execution failure.

The source-level result may also help with troubleshooting.

For example:

```text
Source parquet
      ↓
DuckDB finds 112 duplicate groups
```

If comparable duplicate combinations are later found in Bronze, the DuckDB result provides evidence that duplicate patterns already existed in the source.

However, the comparison must use:

```text
The same source scope
The same date range
The same duplicate key
The same row definition
```

Without aligning those items, it would not be accurate to claim that every duplicate in Bronze came from the source.

---

# Part 14: Possible Future Improvements

The current implementation is a focused proof of concept. It can be improved later without changing its main purpose.

## 1. Validate All Green Taxi Source Files

The current implementation checks only:

```text
March 2026
```

A future version could also validate:

```text
April 2026
May 2026
```

These source locations are already represented in the project configuration.

## 2. Read Source Locations from Configuration

The SQL currently contains a hardcoded Green Taxi URL.

A future implementation could read the source locations from:

```text
config/sources.json
```

This would avoid repeating the source paths in multiple SQL files.

It would also make the validation easier to update if the source configuration changes.

## 3. Add Taxi Zones Validation

Possible Taxi Zones checks could include:

```text
Location ID is not null
Location ID is unique
Borough is not null
Zone is not null
Expected columns exist
```

The final rules should be aligned with the project's existing validation documentation.

## 4. Add Weather Validation

DuckDB checks could also be created for the weather source after reviewing:

```text
The actual weather source format
The expected schema
Required weather fields
Existing validation rules
```

## 5. Compare Source and Bronze Row Counts

DuckDB could calculate a source count and compare it with the corresponding Databricks Bronze result.

```text
DuckDB source count
          vs
Databricks Bronze count
```

For this comparison to be valid, both counts must use the same files, date range, and filtering rules.

This comparison could help identify records that were unexpectedly lost or added during ingestion.

## 6. Add a Failing Process Exit Code

The current runner writes and prints the results.

A future version could return a nonzero process exit code when any data-quality check fails:

```python
if not all(
    result["passed"]
    for result in results
):
    raise SystemExit(1)
```

This would allow the DuckDB checks to operate as an automated quality gate.

Before enabling this behavior, the team should decide whether known source duplicates should block the validation workflow.

## 7. Run the Checks in GitHub Actions

The checks could eventually run in GitHub Actions.

This would provide another execution environment:

```text
GitHub Actions runner
        ↓
Install DuckDB
        ↓
Read source files
        ↓
Execute SQL checks
        ↓
Pass or fail workflow
```

That enhancement would require the team to confirm the repository's workflow, connectivity, and security requirements.

---

# What I Learned

The biggest change in my understanding was recognizing that data quality can be validated at different points for different purposes.

Before adding DuckDB, the main validation flow was:

```text
Source data
     ↓
Databricks ingestion
     ↓
Bronze
     ↓
Silver
     ↓
Gold
     ↓
Pipeline validation
```

After adding DuckDB, the flow became:

```text
                 ┌→ DuckDB source validation
Raw source data ─┤
                 └→ Databricks ingestion
                          ↓
                       Bronze
                          ↓
                       Silver
                          ↓
                        Gold
                          ↓
                 Databricks validation
```

DuckDB and Databricks answer different questions.

```text
DuckDB asks:

Does the raw source already contain this issue?
```

```text
Databricks validation asks:

Did the pipeline produce tables that meet our quality rules?
```

Previously, our data-quality validation was performed inside Databricks after ingestion into the Bronze, Silver, or Gold layers using Spark and Great Expectations.

The DuckDB implementation adds an independent validation point that reads the raw source parquet file directly before it enters the Databricks pipeline.

This allows us to examine source quality using a different query engine and execution environment.

In short:

```text
Before
=
Pipeline validation inside Databricks

DuckDB
=
Source validation outside Databricks

Together
=
Better visibility into where data-quality issues originate
```

The current proof of concept successfully:

* connected to DuckDB through Python
* read the March 2026 Green Taxi parquet directly
* executed three SQL data-quality checks
* observed 44,208 source records
* confirmed zero null `PULocationID` values
* identified 112 duplicate trip-key groups
* generated `evidence/proof/duckdb/results.json`

The DuckDB implementation does not replace our Databricks validation.

It adds an independent source-level validation step that can help distinguish source-data issues from pipeline-related issues.