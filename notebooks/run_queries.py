import duckdb
from pathlib import Path
import pandas as pd

pd.set_option("display.max_columns", None)
pd.set_option("display.width", 200)
pd.set_option("display.float_format", lambda x: f"{x:,.2f}")

SQL_DIR = Path("sql")
DB_PATH = "data/portfolio.duckdb"


def run_all():
    con = duckdb.connect(DB_PATH, read_only=True)
    for sql_file in sorted(SQL_DIR.glob("*.sql")):
        print("\n" + "=" * 80)
        print(f"  {sql_file.name}")
        print("=" * 80)
        sql = sql_file.read_text()
        header = "\n".join(line for line in sql.splitlines() if line.startswith("--"))
        print(header + "\n")
        try:
            result = con.execute(sql).fetchdf()
            print(result.to_string(index=False))
        except Exception as e:
            print(f"ERROR: {e}")
    con.close()


if __name__ == "__main__":
    run_all()