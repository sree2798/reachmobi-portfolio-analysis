-- =============================================================================
-- Query 4: LTV and payback period by channel x app
-- -----------------------------------------------------------------------------
-- Business question: For each channel-app combo, how much revenue do we earn
-- per user at D7/D30/D60/D90, and how does that compare to what it costs to
-- acquire them? Payback bucket = how fast the channel turns profitable.
-- Assumption: LTV per user = cumulative ad revenue + pro-rated subscription
-- revenue accrued within N days of install. Only mature cohorts (90+ days
-- post-install) are included to avoid biased averages.
-- =============================================================================
WITH mature_users AS (
    SELECT * FROM users
    WHERE install_date <= (SELECT MAX(install_date) FROM users) - INTERVAL '90 days'
      AND channel != 'organic'
),
spend AS (
    SELECT channel, app_id, SUM(spend_usd) AS total_spend
    FROM ua_spend
    WHERE channel != 'organic'
    GROUP BY channel, app_id
),
installs AS (
    SELECT channel, app_id, COUNT(*) AS install_count
    FROM users
    WHERE channel != 'organic'
    GROUP BY channel, app_id
),
cac AS (
    SELECT s.channel, s.app_id,
           s.total_spend / NULLIF(i.install_count, 0) AS cac
    FROM spend s JOIN installs i USING (channel, app_id)
),
ad_rev_per_user AS (
    SELECT
        u.user_id, u.channel, u.app_id,
        SUM(CASE WHEN ae.event_date < u.install_date + INTERVAL '7 days'  THEN ae.revenue_usd ELSE 0 END) AS ad_d7,
        SUM(CASE WHEN ae.event_date < u.install_date + INTERVAL '30 days' THEN ae.revenue_usd ELSE 0 END) AS ad_d30,
        SUM(CASE WHEN ae.event_date < u.install_date + INTERVAL '60 days' THEN ae.revenue_usd ELSE 0 END) AS ad_d60,
        SUM(CASE WHEN ae.event_date < u.install_date + INTERVAL '90 days' THEN ae.revenue_usd ELSE 0 END) AS ad_d90
    FROM mature_users u
    LEFT JOIN ad_events ae ON u.user_id = ae.user_id
    GROUP BY u.user_id, u.channel, u.app_id
),
sub_rev_per_user AS (
    SELECT
        u.user_id,
        COALESCE(SUM(GREATEST(0, DATEDIFF('day',
            GREATEST(s.subscribed_date, u.install_date),
            LEAST(COALESCE(s.churned_date, DATE '9999-12-31'), u.install_date + INTERVAL '7 days')
        )) * s.mrr_usd / 30.0), 0) AS sub_d7,
        COALESCE(SUM(GREATEST(0, DATEDIFF('day',
            GREATEST(s.subscribed_date, u.install_date),
            LEAST(COALESCE(s.churned_date, DATE '9999-12-31'), u.install_date + INTERVAL '30 days')
        )) * s.mrr_usd / 30.0), 0) AS sub_d30,
        COALESCE(SUM(GREATEST(0, DATEDIFF('day',
            GREATEST(s.subscribed_date, u.install_date),
            LEAST(COALESCE(s.churned_date, DATE '9999-12-31'), u.install_date + INTERVAL '60 days')
        )) * s.mrr_usd / 30.0), 0) AS sub_d60,
        COALESCE(SUM(GREATEST(0, DATEDIFF('day',
            GREATEST(s.subscribed_date, u.install_date),
            LEAST(COALESCE(s.churned_date, DATE '9999-12-31'), u.install_date + INTERVAL '90 days')
        )) * s.mrr_usd / 30.0), 0) AS sub_d90
    FROM mature_users u
    LEFT JOIN subscriptions s ON u.user_id = s.user_id
    GROUP BY u.user_id
),
ltv AS (
    SELECT
        a.channel, a.app_id,
        COUNT(*)                                  AS cohort_size,
        AVG(a.ad_d7  + COALESCE(s.sub_d7,  0))    AS ltv_d7,
        AVG(a.ad_d30 + COALESCE(s.sub_d30, 0))    AS ltv_d30,
        AVG(a.ad_d60 + COALESCE(s.sub_d60, 0))    AS ltv_d60,
        AVG(a.ad_d90 + COALESCE(s.sub_d90, 0))    AS ltv_d90
    FROM ad_rev_per_user a
    LEFT JOIN sub_rev_per_user s ON a.user_id = s.user_id
    GROUP BY a.channel, a.app_id
)
SELECT
    l.channel,
    l.app_id,
    l.cohort_size,
    ROUND(c.cac, 2)                                  AS cac,
    ROUND(l.ltv_d7, 2)                               AS ltv_d7,
    ROUND(l.ltv_d30, 2)                              AS ltv_d30,
    ROUND(l.ltv_d60, 2)                              AS ltv_d60,
    ROUND(l.ltv_d90, 2)                              AS ltv_d90,
    ROUND(l.ltv_d90 / NULLIF(c.cac, 0), 2)           AS roas_d90,
    CASE
        WHEN l.ltv_d7  >= c.cac THEN 'D7 or earlier'
        WHEN l.ltv_d30 >= c.cac THEN 'D8 - D30'
        WHEN l.ltv_d60 >= c.cac THEN 'D31 - D60'
        WHEN l.ltv_d90 >= c.cac THEN 'D61 - D90'
        ELSE 'unprofitable at D90'
    END                                              AS payback_bucket
FROM ltv l
JOIN cac c ON l.channel = c.channel AND l.app_id = c.app_id
ORDER BY roas_d90 DESC;