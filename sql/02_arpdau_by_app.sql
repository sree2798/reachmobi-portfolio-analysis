-- =============================================================================
-- Query 2: ARPDAU by app, split by revenue source
-- -----------------------------------------------------------------------------
-- Business question: How does each app monetize, and which revenue stream is
-- the workhorse? ReachMobi's portfolio is ad + subscription; understanding the
-- mix tells us where to invest product effort.
-- Assumption: Daily subscription revenue = MRR / 30. A DAU-day is one user
-- having any session on one date.
-- =============================================================================
WITH dau_days AS (
    SELECT app_id, COUNT(*) AS total_dau_days
    FROM (SELECT DISTINCT app_id, user_id, session_date FROM sessions)
    GROUP BY app_id
),
ad_revenue AS (
    SELECT
        app_id,
        SUM(CASE WHEN ad_type = 'banner'       THEN revenue_usd ELSE 0 END) AS banner_rev,
        SUM(CASE WHEN ad_type = 'interstitial' THEN revenue_usd ELSE 0 END) AS interstitial_rev,
        SUM(CASE WHEN ad_type = 'rewarded'     THEN revenue_usd ELSE 0 END) AS rewarded_rev,
        SUM(revenue_usd) AS total_ad_rev
    FROM ad_events
    GROUP BY app_id
),
sub_revenue AS (
    SELECT
        app_id,
        SUM(
            DATEDIFF(
                'day',
                subscribed_date,
                COALESCE(churned_date, (SELECT MAX(session_date) FROM sessions))
            ) * mrr_usd / 30.0
        ) AS total_sub_rev
    FROM subscriptions
    GROUP BY app_id
)
SELECT
    d.app_id,
    d.total_dau_days,
    ROUND(a.banner_rev       / d.total_dau_days, 4) AS arpdau_banner,
    ROUND(a.interstitial_rev / d.total_dau_days, 4) AS arpdau_interstitial,
    ROUND(a.rewarded_rev     / d.total_dau_days, 4) AS arpdau_rewarded,
    ROUND(COALESCE(s.total_sub_rev, 0) / d.total_dau_days, 4) AS arpdau_subscription,
    ROUND((a.total_ad_rev + COALESCE(s.total_sub_rev, 0)) / d.total_dau_days, 4) AS arpdau_total
FROM dau_days d
JOIN ad_revenue a ON d.app_id = a.app_id
LEFT JOIN sub_revenue s ON d.app_id = s.app_id
ORDER BY arpdau_total DESC;