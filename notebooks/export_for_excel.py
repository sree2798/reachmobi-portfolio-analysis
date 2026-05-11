import duckdb
import pandas as pd
from pathlib import Path

DB_PATH = "data/portfolio.duckdb"
OUT_PATH = Path("excel/ltv_model.xlsx")
OUT_PATH.parent.mkdir(parents=True, exist_ok=True)

con = duckdb.connect(DB_PATH, read_only=True)

ltv_sql = Path("sql/04_ltv_payback.sql").read_text()
ltv_df = con.execute(ltv_sql).fetchdf()

cac_df = con.execute("""
    WITH spend AS (
        SELECT channel, app_id, SUM(spend_usd) AS total_spend
        FROM ua_spend WHERE channel != 'organic' GROUP BY channel, app_id
    ),
    actual AS (
        SELECT channel, app_id, COUNT(*) AS true_installs
        FROM users WHERE channel != 'organic' GROUP BY channel, app_id
    )
    SELECT s.channel, s.app_id, s.total_spend, a.true_installs,
           ROUND(s.total_spend / a.true_installs, 2) AS cac_true
    FROM spend s JOIN actual a USING (channel, app_id)
    ORDER BY s.channel, s.app_id
""").fetchdf()

arpdau_df = con.execute(Path("sql/02_arpdau_by_app.sql").read_text()).fetchdf()
con.close()

with pd.ExcelWriter(OUT_PATH, engine="openpyxl") as w:
    ltv_df.to_excel(w, sheet_name="data_ltv", index=False)
    cac_df.to_excel(w, sheet_name="data_spend", index=False)
    arpdau_df.to_excel(w, sheet_name="data_arpdau", index=False)

print(f"Wrote {OUT_PATH}")
for name, df in [("data_ltv", ltv_df), ("data_spend", cac_df), ("data_arpdau", arpdau_df)]:
    print(f"  {name}: {len(df)} rows")