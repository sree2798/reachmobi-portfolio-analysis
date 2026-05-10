"""
ReachMobi Portfolio Analysis - Synthetic Data Generator

Generates a realistic 6-month dataset for 4 personalization apps across
5 UA channels. Output is a DuckDB database used for SQL analysis, LTV modeling,
and a data quality audit.

Schema:
  users          - one row per install
  sessions       - one row per (user, active day)
  ad_events      - banner/interstitial/rewarded revenue per session-day
  subscriptions  - premium-tier subs with sub date and (sometimes) churn date
  ua_spend       - daily paid-UA spend by channel x app
"""

import duckdb
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from pathlib import Path
SEED = 42
START_DATE = datetime(2025, 5, 1)
END_DATE = datetime(2025, 10, 31)
OUTPUT_PATH = Path("data/portfolio.duckdb")

DAILY_INSTALLS_BASE = 700

APPS = {
    "launchpad": {"name": "LaunchPad", "category": "launcher",
                  "install_share": 0.45, "ad_arpdau_base": 0.045,
                  "sub_conversion": 0.025, "sub_mrr": 4.99},
    "inboxzen":  {"name": "InboxZen",  "category": "email",
                  "install_share": 0.20, "ad_arpdau_base": 0.025,
                  "sub_conversion": 0.055, "sub_mrr": 6.99},
    "pingme":    {"name": "PingMe",    "category": "messaging",
                  "install_share": 0.15, "ad_arpdau_base": 0.020,
                  "sub_conversion": 0.018, "sub_mrr": 3.99},
    "wallcraft": {"name": "WallCraft", "category": "personalization",
                  "install_share": 0.20, "ad_arpdau_base": 0.055,
                  "sub_conversion": 0.012, "sub_mrr": 2.99},
}

CHANNELS = {
    "meta":     {"share": 0.30, "cpi_mean": 3.20, "cpi_std": 0.40,
                 "d1_ret": 0.32, "d7_ret": 0.18, "arpdau_mult": 1.00},
    "tiktok":   {"share": 0.25, "cpi_mean": 2.10, "cpi_std": 0.50,
                 "d1_ret": 0.28, "d7_ret": 0.14, "arpdau_mult": 0.85},
    "google":   {"share": 0.20, "cpi_mean": 3.50, "cpi_std": 0.30,
                 "d1_ret": 0.35, "d7_ret": 0.20, "arpdau_mult": 1.05},
    "applovin": {"share": 0.10, "cpi_mean": 1.80, "cpi_std": 0.60,
                 "d1_ret": 0.22, "d7_ret": 0.08, "arpdau_mult": 0.70},
    "organic":  {"share": 0.15, "cpi_mean": 0.00, "cpi_std": 0.00,
                 "d1_ret": 0.45, "d7_ret": 0.28, "arpdau_mult": 1.30},
}

COUNTRIES = ["US", "GB", "DE", "BR", "IN", "MX", "CA", "AU"]
COUNTRY_WEIGHTS = [0.40, 0.10, 0.08, 0.10, 0.15, 0.07, 0.05, 0.05]

DEVICE_TIERS = ["high", "mid", "low"]
DEVICE_WEIGHTS = [0.30, 0.50, 0.20]

AD_TYPES = {
    "banner":       {"ecpm_mean": 1.20,  "imp_per_session": 8.0},
    "interstitial": {"ecpm_mean": 9.50,  "imp_per_session": 1.5},
    "rewarded":     {"ecpm_mean": 18.00, "imp_per_session": 0.4},
}

rng = np.random.default_rng(SEED)




def daterange(start, end):
    for n in range((end - start).days + 1):
        yield start + timedelta(days=n)


def power_retention(d1, d7, day):
    """Power-law retention: r(d) = a * d^b, fit through D1 and D7."""
    if day == 0:
        return 1.0
    b = np.log(d7 / d1) / np.log(7)
    return float(d1 * (day ** b))




def build_users():
    print("Building users...")
    rows = []
    user_id = 1
    for d in daterange(START_DATE, END_DATE):
        dow_mult = 1.10 if d.weekday() >= 5 else 1.00
        growth = 1.0 + (d - START_DATE).days * 0.0008
        daily_total = int(DAILY_INSTALLS_BASE * dow_mult * growth * rng.normal(1.0, 0.08))
        for app_id, app in APPS.items():
            app_n = int(daily_total * app["install_share"])
            for channel_id, ch in CHANNELS.items():
                n = int(app_n * ch["share"])
                if n == 0:
                    continue
                countries = rng.choice(COUNTRIES, size=n, p=COUNTRY_WEIGHTS)
                tiers = rng.choice(DEVICE_TIERS, size=n, p=DEVICE_WEIGHTS)
                hours = rng.integers(0, 24, size=n)
                for i in range(n):
                    rows.append((f"u_{user_id:08d}", app_id, d.date(),
                                 channel_id, countries[i], tiers[i], int(hours[i])))
                    user_id += 1
    df = pd.DataFrame(rows, columns=["user_id", "app_id", "install_date",
                                     "channel", "country", "device_tier",
                                     "install_hour_utc"])
    print(f"  {len(df):,} users")
    return df


def build_sessions(users_df):
    """Per user, sample which days they're active using their channel's retention curve."""
    print("Building sessions...")
    end_date = END_DATE.date()
    max_days = (END_DATE - START_DATE).days
    rows = []

    for channel_id, ch in CHANNELS.items():
        retention = np.array([1.0 if d == 0 else power_retention(ch["d1_ret"], ch["d7_ret"], d)
                              for d in range(max_days + 1)])
        ch_users = users_df[users_df["channel"] == channel_id]
        for u in ch_users.itertuples(index=False):
            max_day = (end_date - u.install_date).days
            probs = retention[:max_day + 1]
            actives = rng.random(len(probs)) < probs
            actives[0] = True
            day_offsets = np.where(actives)[0]
            n = len(day_offsets)
            if n == 0:
                continue
            session_counts = np.maximum(1, rng.poisson(2.0, n))
            seconds = np.maximum(30, (session_counts * rng.normal(180, 60, n)).astype(int))
            for i, off in enumerate(day_offsets):
                rows.append((u.user_id, u.app_id,
                             u.install_date + timedelta(days=int(off)),
                             int(off), int(session_counts[i]), int(seconds[i])))
    df = pd.DataFrame(rows, columns=["user_id", "app_id", "session_date",
                                     "day_offset", "session_count",
                                     "total_session_seconds"])
    print(f"  {len(df):,} session-days")
    return df


def build_ad_events(sessions_df, users_df):
    print("Building ad events...")
    user_lookup = users_df.set_index("user_id")[
        ["channel", "country", "install_hour_utc"]].to_dict("index")
    rows = []
    for s in sessions_df.itertuples(index=False):
        u = user_lookup[s.user_id]
        ch_mult = CHANNELS[u["channel"]]["arpdau_mult"]
        app_mult = APPS[s.app_id]["ad_arpdau_base"] / 0.04
        country_factor = 1.3 if u["country"] in ("US", "GB", "CA", "AU") else 0.7

        for ad_type, params in AD_TYPES.items():
            impressions = int(max(0, rng.poisson(params["imp_per_session"] * s.session_count)))
            if impressions == 0:
                continue
            ecpm = max(0.10, rng.normal(params["ecpm_mean"], params["ecpm_mean"] * 0.25))
            revenue = (impressions / 1000.0) * ecpm * ch_mult * country_factor * app_mult

            event_date = s.session_date
            if (s.app_id == "wallcraft" and u["install_hour_utc"] >= 22
                    and s.day_offset == 1 and rng.random() < 0.6):
                event_date = s.session_date - timedelta(days=1)

            rows.append((s.user_id, s.app_id, event_date, ad_type,
                         impressions, round(revenue, 4)))
    df = pd.DataFrame(rows, columns=["user_id", "app_id", "event_date",
                                     "ad_type", "impressions", "revenue_usd"])
    print(f"  {len(df):,} ad events")
    return df


def build_subscriptions(users_df):
    print("Building subscriptions...")
    rows = []
    for u in users_df.itertuples(index=False):
        app = APPS[u.app_id]
        if rng.random() >= app["sub_conversion"]:
            continue
        days_to_convert = min(int(rng.exponential(5.0)), 30)
        sub_date = u.install_date + timedelta(days=days_to_convert)
        if sub_date > END_DATE.date():
            continue
        months_active = max(1, int(rng.exponential(8.0)))
        churn_date = sub_date + timedelta(days=months_active * 30)
        if churn_date > END_DATE.date():
            churned_val = None
        else:
            churned_val = None if rng.random() < 0.15 else churn_date
        rows.append((u.user_id, u.app_id, sub_date, "premium",
                     app["sub_mrr"], churned_val))
    df = pd.DataFrame(rows, columns=["user_id", "app_id", "subscribed_date",
                                     "tier", "mrr_usd", "churned_date"])
    print(f"  {len(df):,} subscriptions")
    return df


def build_ua_spend(users_df):
    print("Building ua_spend...")
    actuals = (users_df.groupby(["install_date", "app_id", "channel"])
                       .size().reset_index(name="actual_installs"))
    rows = []
    for r in actuals.itertuples(index=False):
        ch = CHANNELS[r.channel]
        if r.channel == "organic":
            spend, reported = 0.0, r.actual_installs
        else:
            cpi = max(0.20, rng.normal(ch["cpi_mean"], ch["cpi_std"]))
            spend = round(r.actual_installs * cpi, 2)
            reported = r.actual_installs
            if r.channel == "applovin":
                reported = int(round(r.actual_installs * 1.30))
        rows.append((r.install_date, r.channel, r.app_id, spend, reported))
    df = pd.DataFrame(rows, columns=["date", "channel", "app_id",
                                     "spend_usd", "installs"])
    print(f"  {len(df):,} ua_spend rows")
    return df


def main():
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    users = build_users()
    sessions = build_sessions(users)
    ad_events = build_ad_events(sessions, users)
    subscriptions = build_subscriptions(users)
    ua_spend = build_ua_spend(users)

    users_out = users.drop(columns=["install_hour_utc"])

    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    con = duckdb.connect(str(OUTPUT_PATH))
    con.register("users_df", users_out)
    con.register("sessions_df", sessions)
    con.register("ad_events_df", ad_events)
    con.register("subscriptions_df", subscriptions)
    con.register("ua_spend_df", ua_spend)
    con.execute("CREATE TABLE users AS SELECT * FROM users_df")
    con.execute("CREATE TABLE sessions AS SELECT * FROM sessions_df")
    con.execute("CREATE TABLE ad_events AS SELECT * FROM ad_events_df")
    con.execute("CREATE TABLE subscriptions AS SELECT * FROM subscriptions_df")
    con.execute("CREATE TABLE ua_spend AS SELECT * FROM ua_spend_df")

    print("\n=== Summary ===")
    for t in ["users", "sessions", "ad_events", "subscriptions", "ua_spend"]:
        n = con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        print(f"  {t:15s}: {n:>10,} rows")
    rev = con.execute("SELECT ROUND(SUM(revenue_usd),0) FROM ad_events").fetchone()[0]
    spend = con.execute("SELECT ROUND(SUM(spend_usd),0) FROM ua_spend").fetchone()[0]
    print(f"\n  Total ad revenue: ${rev:,.0f}")
    print(f"  Total UA spend:   ${spend:,.0f}")
    con.close()
    print("\nDone. ✓")


if __name__ == "__main__":
    main()