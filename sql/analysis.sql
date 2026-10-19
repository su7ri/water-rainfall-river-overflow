-- ============================================================
-- Rain, river flow and storm overflows: SQL analysis (SQLite)
-- Tables: dim_date, dim_station, fact_daily_readings,
--         fact_edm_daily, fact_edm_events
-- ============================================================

-- Q1. Data quality: share of readings that are not "Good", per station
SELECT station,
       COUNT(*)                                        AS readings,
       SUM(value IS NULL)                              AS missing,
       ROUND(100.0 * SUM(quality <> 'Good') / COUNT(*), 1) AS pct_not_good
FROM fact_daily_readings
GROUP BY station
ORDER BY pct_not_good DESC;

-- Q2. Regional daily rainfall index (mean of gauges, Suspect excluded)
CREATE VIEW IF NOT EXISTS v_rain_daily AS
SELECT r.date, AVG(r.value) AS rain_mm
FROM fact_daily_readings r
JOIN dim_station s ON s.station = r.station
WHERE s.measure = 'Rainfall' AND r.quality <> 'Suspect'
GROUP BY r.date;

-- Q3. Annual rainfall and wettest month per year
WITH monthly AS (
  SELECT d.year, d.month, d.month_num, SUM(v.rain_mm) AS rain_mm
  FROM v_rain_daily v JOIN dim_date d ON d.date = v.date
  GROUP BY d.year, d.month_num
)
SELECT year,
       ROUND(SUM(rain_mm)) AS annual_mm,
       (SELECT m2.month FROM monthly m2 WHERE m2.year = m.year
        ORDER BY m2.rain_mm DESC LIMIT 1) AS wettest_month
FROM monthly m GROUP BY year ORDER BY year;

-- Q4. Rolling 14-day rainfall and Exe flow (window function)
CREATE VIEW IF NOT EXISTS v_rain_flow AS
SELECT v.date,
       v.rain_mm,
       SUM(v.rain_mm) OVER (ORDER BY v.date ROWS BETWEEN 13 PRECEDING AND CURRENT ROW) AS rain_14d,
       SUM(v.rain_mm) OVER (ORDER BY v.date ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)  AS rain_2d,
       f.value AS exe_flow
FROM v_rain_daily v
LEFT JOIN fact_daily_readings f ON f.date = v.date AND f.station = 'Exe_Thorverton';

-- Q5. Flow response: average Exe flow by 14-day rainfall band
SELECT CASE WHEN rain_14d < 20  THEN '1: <20 mm'
            WHEN rain_14d < 50  THEN '2: 20-50 mm'
            WHEN rain_14d < 100 THEN '3: 50-100 mm'
            ELSE '4: >=100 mm' END AS rain_14d_band,
       COUNT(*) AS days,
       ROUND(AVG(exe_flow), 1) AS avg_flow_m3s
FROM v_rain_flow
WHERE rain_14d IS NOT NULL AND exe_flow IS NOT NULL
GROUP BY 1 ORDER BY 1;

-- Q6. Low-flow days per year (Exe below its own 10th percentile) - water resources angle
WITH ranked AS (
  SELECT date, value,
         PERCENT_RANK() OVER (ORDER BY value) AS pr
  FROM fact_daily_readings WHERE station = 'Exe_Thorverton' AND value IS NOT NULL
)
SELECT substr(date, 1, 4) AS year,
       SUM(pr <= 0.10) AS low_flow_days,
       ROUND(MIN(value), 2) AS min_flow_m3s
FROM ranked GROUP BY 1 ORDER BY 1;

-- Q7. Overflows: wet days vs other days (2025)
SELECT CASE WHEN rf.rain_2d >= 10 THEN 'Wet (>=10 mm in 2 days)' ELSE 'Other' END AS day_type,
       COUNT(*) AS days,
       ROUND(AVG(e.events)) AS avg_events,
       ROUND(AVG(e.discharge_hours)) AS avg_discharge_hours
FROM fact_edm_daily e JOIN v_rain_flow rf ON rf.date = e.date
GROUP BY 1;

-- Q8. Top 10 sites by total discharge hours (events > 7 days excluded)
SELECT site_id,
       COALESCE(NULLIF(site_name, 'Unknown'), '(no name)') AS site_name,
       COUNT(*) AS events,
       ROUND(SUM(hours)) AS discharge_hours,
       ROUND(100.0 * SUM(hours) / (SELECT SUM(hours) FROM fact_edm_events WHERE too_long = 0), 2) AS pct_of_total
FROM fact_edm_events
WHERE too_long = 0
GROUP BY site_id, site_name
ORDER BY discharge_hours DESC
LIMIT 10;

-- Q9. Share of all discharge hours caused by the worst 10% of sites (concentration)
WITH site AS (
  SELECT site_id, SUM(hours) AS h FROM fact_edm_events WHERE too_long = 0 GROUP BY site_id
), ranked AS (
  SELECT h, NTILE(10) OVER (ORDER BY h DESC) AS decile FROM site
)
SELECT decile, COUNT(*) AS sites, ROUND(100.0 * SUM(h) / (SELECT SUM(h) FROM site), 1) AS pct_of_hours
FROM ranked GROUP BY decile ORDER BY decile;

-- Q10. Anomaly check: monitors with suspiciously long events (>7 days)
SELECT site_id, COALESCE(NULLIF(site_name,'Unknown'),'(no name)') AS site_name,
       COUNT(*) AS long_events, ROUND(MAX(hours)) AS longest_hours
FROM fact_edm_events WHERE too_long = 1
GROUP BY site_id ORDER BY longest_hours DESC LIMIT 10;

-- Q11. Anomaly: days whose event count is >2 SD above that month's average (spikes to investigate)
WITH m AS (
  SELECT e.date, e.events, rf.rain_2d, substr(e.date,1,7) AS ym FROM fact_edm_daily e
  JOIN v_rain_flow rf ON rf.date = e.date
), stats AS (
  SELECT ym, AVG(events) AS mu, AVG(events*events) - AVG(events)*AVG(events) AS var FROM m GROUP BY ym
)
SELECT m.date, m.events, ROUND(m.rain_2d,1) AS rain_2d_mm,
       ROUND((m.events - s.mu) / NULLIF(SQRT(s.var),0), 2) AS z_in_month
FROM m JOIN stats s USING (ym)
WHERE (m.events - s.mu) / NULLIF(SQRT(s.var),0) > 2
ORDER BY z_in_month DESC LIMIT 10;
