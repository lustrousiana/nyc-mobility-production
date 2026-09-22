import json
import pathlib

from connection import connect

CHECKS_DIR = pathlib.Path(__file__).parent / "checks"
OUTPUT_PATH = pathlib.Path("evidence/proof/duckdb/results.json")


def main():
    con = connect()

    results = []

    for sql_file in sorted(CHECKS_DIR.glob("*.sql")):
        result = con.execute(sql_file.read_text()).fetchone()

        results.append(
            {
                "check": result[0],
                "observed": result[1],
                "expected": result[2],
                "passed": bool(result[3]),
            }
        )

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    OUTPUT_PATH.write_text(
        json.dumps(results, indent=2)
    )

    print(results)


if __name__ == "__main__":
    main()
    