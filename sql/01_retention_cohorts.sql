-- =============================================================================
-- Query 1: D1 / D7 / D30 retention by app x channel
-- -----------------------------------------------------------------------------
-- Business question: Which channels deliver users who stick around, and which
-- apps retain best? Retention is the single biggest LTV lever for utility apps.
-- Assumption: A user is "retained on day N" if they had any session on the Nth
-- day after install. Only includes cohorts with >= 30 days of post-install data.
-- =============================================================================
WITH mature_cohorts AS (
    SELECT user_id, app_id, channel, install_date
    FROM users
    WHERE install_date <= (SELECT MAX(install_date) FROM users) - INTERVAL '30 days'
),
user_activity AS (
    SELECT
        c.app_id,
        c.channel,
        c.user_id,
        MAX(CASE WHEN s.day_offset = 1  THEN 1 ELSE 0 END) AS active_d1,
        MAX(CASE WHEN s.day_offset = 7  THEN 1 ELSE 0 END) AS active_d7,
        MAX(CASE WHEN s.day_offset = 30 THEN 1 ELSE 0 END) AS active_d30
    FROM mature_cohorts c
    LEFT JOIN sessions s ON c.user_id = s.user_id
    GROUP BY c.app_id, c.channel, c.user_id
)
SELECT
    app_id,
    channel,
    COUNT(*)                                       AS cohort_size,
    ROUND(AVG(active_d1::DOUBLE)  * 100, 1)        AS d1_retention_pct,
    ROUND(AVG(active_d7::DOUBLE)  * 100, 1)        AS d7_retention_pct,
    ROUND(AVG(active_d30::DOUBLE) * 100, 1)        AS d30_retention_pct
FROM user_activity
GROUP BY app_id, channel
ORDER BY app_id, d7_retention_pct DESC;