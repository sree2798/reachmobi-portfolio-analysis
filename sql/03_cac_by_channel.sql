-- =============================================================================
-- Query 3: CAC by channel x app — reported vs true
-- -----------------------------------------------------------------------------
-- Business question: What does it really cost us to acquire a user on each
-- channel? Reported CAC from network dashboards can lie; we validate against
-- actual installs recorded in our backend.
-- Assumption: An "actual install" is a row in the users table. Reported
-- installs come from ua_spend (the ad-network feed).
-- =============================================================================
WITH spend AS (
    SELECT channel, app_id,
           SUM(spend_usd) AS total_spend,
           SUM(installs)  AS reported_installs
    FROM ua_spend
    WHERE channel != 'organic'
    GROUP BY channel, app_id
),
actual AS (
    SELECT channel, app_id, COUNT(*) AS actual_installs
    FROM users
    WHERE channel != 'organic'
    GROUP BY channel, app_id
)
SELECT
    s.channel,
    s.app_id,
    s.total_spend,
    s.reported_installs,
    a.actual_installs,
    ROUND(s.total_spend / NULLIF(s.reported_installs, 0), 2) AS cac_reported,
    ROUND(s.total_spend / NULLIF(a.actual_installs, 0), 2)   AS cac_true,
    ROUND((s.reported_installs - a.actual_installs) * 100.0
          / NULLIF(a.actual_installs, 0), 1)                  AS install_inflation_pct
FROM spend s
JOIN actual a ON s.channel = a.channel AND s.app_id = a.app_id
ORDER BY install_inflation_pct DESC, s.channel, s.app_id;