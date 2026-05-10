-- =============================================================================
-- Query 6: Data quality audit — three integrity checks
-- -----------------------------------------------------------------------------
-- Business question: Can we trust the numbers? Before forecasting LTV or
-- recommending budget shifts, surface upstream data issues that distort
-- decisions. Each check returns a row only if a threshold is breached.
-- Findings:
--   #1 Channel install inflation: reported vs actual installs by channel
--   #2 Ad event date bucketing: D0 vs D1 event ratio anomaly by app
--   #3 Silent churn: subs marked active but user has been inactive 30+ days
-- =============================================================================
WITH
-- ----- Check 1: install discrepancies between ad-network feed and our backend
reported AS (
    SELECT channel, SUM(installs) AS reported FROM ua_spend GROUP BY channel
),
actual AS (
    SELECT channel, COUNT(*) AS actual FROM users GROUP BY channel
),
finding_1 AS (
    SELECT
        'CHANNEL_INSTALL_INFLATION'                                       AS check_id,
        'Reported installs from ad network exceed actual backend records' AS issue,
        r.channel                                                         AS dimension,
        CAST(r.reported AS VARCHAR) || ' reported vs '
            || CAST(a.actual AS VARCHAR) || ' actual'                     AS observed,
        ROUND((r.reported - a.actual) * 100.0 / a.actual, 1)              AS severity_pct
    FROM reported r JOIN actual a USING (channel)
    WHERE ABS((r.reported - a.actual) * 100.0 / a.actual) > 5
),

-- ----- Check 2: per-app ratio of D0 to D1 ad event volume
event_days AS (
    SELECT
        u.app_id,
        DATEDIFF('day', u.install_date, ae.event_date) AS day_offset,
        COUNT(*) AS event_count
    FROM users u JOIN ad_events ae ON u.user_id = ae.user_id
    WHERE DATEDIFF('day', u.install_date, ae.event_date) BETWEEN 0 AND 1
    GROUP BY u.app_id, DATEDIFF('day', u.install_date, ae.event_date)
),
d0_d1_ratios AS (
    SELECT
        app_id,
        MAX(CASE WHEN day_offset = 0 THEN event_count END) AS d0_events,
        MAX(CASE WHEN day_offset = 1 THEN event_count END) AS d1_events,
        MAX(CASE WHEN day_offset = 0 THEN event_count END) * 1.0
            / NULLIF(MAX(CASE WHEN day_offset = 1 THEN event_count END), 0) AS ratio
    FROM event_days GROUP BY app_id
),
finding_2 AS (
    SELECT
        'AD_EVENT_DATE_BUCKETING'                                                       AS check_id,
        'D0 ad event volume anomalously high vs D1, suggests timezone bucketing issue'  AS issue,
        app_id                                                                          AS dimension,
        'D0=' || CAST(d0_events AS VARCHAR) || ' D1=' || CAST(d1_events AS VARCHAR)
            || ' ratio=' || CAST(ROUND(ratio, 2) AS VARCHAR)                            AS observed,
        ROUND((ratio - (SELECT AVG(ratio) FROM d0_d1_ratios)) * 100, 1)                 AS severity_pct
    FROM d0_d1_ratios
    WHERE ratio > (SELECT AVG(ratio) * 1.3 FROM d0_d1_ratios)
),

-- ----- Check 3: subscribers with NULL churned_date but no recent sessions
last_session AS (
    SELECT user_id, MAX(session_date) AS last_active FROM sessions GROUP BY user_id
),
data_max AS (SELECT MAX(session_date) AS max_date FROM sessions),
finding_3 AS (
    SELECT
        'SILENT_SUBSCRIPTION_CHURN'                                                    AS check_id,
        'Subscriptions marked active (NULL churned_date) but user inactive 30+ days'   AS issue,
        s.app_id                                                                       AS dimension,
        CAST(COUNT(*) AS VARCHAR) || ' suspicious subs, avg '
            || CAST(ROUND(AVG(DATEDIFF('day', ls.last_active, dm.max_date)), 0) AS VARCHAR)
            || ' days inactive'                                                        AS observed,
        ROUND(COUNT(*) * 100.0
            / (SELECT COUNT(*) FROM subscriptions WHERE churned_date IS NULL), 1)      AS severity_pct
    FROM subscriptions s
    JOIN last_session ls ON s.user_id = ls.user_id
    CROSS JOIN data_max dm
    WHERE s.churned_date IS NULL
      AND ls.last_active < dm.max_date - INTERVAL '30 days'
    GROUP BY s.app_id
    HAVING COUNT(*) > 0
)

SELECT * FROM finding_1
UNION ALL SELECT * FROM finding_2
UNION ALL SELECT * FROM finding_3
ORDER BY check_id, severity_pct DESC;