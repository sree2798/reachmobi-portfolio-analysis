import duckdb
con = duckdb.connect("data/portfolio.duckdb")

# Check 1: install volume by app — should match install_share roughly
print(con.execute("""
    SELECT app_id, COUNT(*) AS installs
    FROM users GROUP BY 1 ORDER BY 2 DESC
""").fetchdf())

# Check 2: D1 retention by channel — organic should be highest, applovin lowest
print(con.execute("""
    SELECT channel,
           ROUND(AVG(CASE WHEN day_offset = 1 THEN 1.0 ELSE 0 END), 3) AS d1_active_share
    FROM sessions s
    JOIN users u USING (user_id)
    WHERE s.day_offset <= 1
    GROUP BY 1 ORDER BY 2 DESC
""").fetchdf())

# Check 3: revenue concentration — launchpad and wallcraft should dominate ads
print(con.execute("""
    SELECT app_id, ROUND(SUM(revenue_usd), 0) AS ad_rev
    FROM ad_events GROUP BY 1 ORDER BY 2 DESC
""").fetchdf())