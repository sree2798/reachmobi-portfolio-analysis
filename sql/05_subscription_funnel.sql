-- =============================================================================
-- Query 5: Subscription funnel — install -> subscribe -> D30 -> D90
-- -----------------------------------------------------------------------------
-- Business question: Where do paying users come from, and how sticky is the
-- subscription product? Strong subscription retention is a moat for utility
-- apps where ad revenue alone often doesn't justify CAC.
-- Assumption: Only cohorts with >= 90 days of post-install data are included.
-- A subscriber is "retained at D90" if they have no churned_date or churned
-- more than 90 days after subscribing.
-- =============================================================================
WITH mature_users AS (
    SELECT * FROM users
    WHERE install_date <= (SELECT MAX(install_date) FROM users) - INTERVAL '90 days'
),
funnel AS (
    SELECT
        u.app_id,
        u.channel,
        COUNT(DISTINCT u.user_id) AS installs,
        COUNT(DISTINCT s.user_id) AS subscribed,
        COUNT(DISTINCT CASE
            WHEN s.user_id IS NOT NULL
             AND (s.churned_date IS NULL OR s.churned_date > s.subscribed_date + INTERVAL '30 days')
            THEN s.user_id END) AS retained_d30,
        COUNT(DISTINCT CASE
            WHEN s.user_id IS NOT NULL
             AND (s.churned_date IS NULL OR s.churned_date > s.subscribed_date + INTERVAL '90 days')
            THEN s.user_id END) AS retained_d90
    FROM mature_users u
    LEFT JOIN subscriptions s ON u.user_id = s.user_id
    GROUP BY u.app_id, u.channel
)
SELECT
    app_id,
    channel,
    installs,
    subscribed,
    ROUND(subscribed     * 100.0 / NULLIF(installs, 0),   2) AS install_to_sub_pct,
    ROUND(retained_d30   * 100.0 / NULLIF(subscribed, 0), 1) AS sub_to_d30_pct,
    ROUND(retained_d90   * 100.0 / NULLIF(subscribed, 0), 1) AS sub_to_d90_pct
FROM funnel
WHERE subscribed > 0
ORDER BY app_id, install_to_sub_pct DESC;