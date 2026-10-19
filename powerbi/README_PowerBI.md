# Power BI build guide (Power BI Desktop, Windows) - target: about 60-90 minutes

## 0. Files in this kit
| File | Rows | Role |
|---|---|---|
| dim_date.csv | 4,018 | Date table 2015-2025 |
| dim_station.csv | 9 | 7 rain gauges + 2 flow stations |
| fact_daily_readings.csv | 32,877 | Daily rain/flow, cleaned, with quality flag |
| fact_edm_daily.csv | 365 | Daily overflow events/hours, 2025 (events > 7 days excluded) |
| fact_edm_events.csv | 209,711 | Every overflow event, 2025, with `too_long` flag |
| measures.dax | | All measures (copy-paste) |
| theme.json | | Colours |

## 1. Load the data
1. Home > Get data > Text/CSV. Load all five CSVs (use **Transform Data**, not Load, for the first one so you can check types).
2. In Power Query check column types for each table:
   - `date` -> **Date** (all tables); `value`, `hours`, `events`, `discharge_hours`, `sites_active` -> numbers; `flag_suspect`, `too_long` -> **True/False**.
   - dim_date: `year`, `month_num`, `water_year` -> Whole number.
3. Close & Apply.

## 2. Model (Model view)
Drag to create these one-to-many relationships (single direction, "one" side first):
- dim_date[date] -> fact_daily_readings[date]
- dim_date[date] -> fact_edm_daily[date]
- dim_date[date] -> fact_edm_events[date]
- dim_station[station] -> fact_daily_readings[station]

Then: select dim_date > Table tools > **Mark as date table** > choose `date`.
Select `dim_date[month]` > Column tools > **Sort by column** > `month_num`.
Select fact_daily_readings[value] > Summarization = **Don't summarize**.

## 3. Measures
Home > Enter data > make an empty table named `_Measures` (just to hold measures). For each block in `measures.dax`: right-click `_Measures` > New measure > paste. Set formats: mm/m3/s measures = Decimal (1 place), % measure = Percentage, event counts = Whole number with thousands separator.

## 4. Theme
View > Themes > Browse for themes > theme.json.

## 5. Pages (16:9, add a title text box on each page)

**Page 1 Overview**
- Cards: Rain Total (mm) [filter year = 2025], Exe Peak Flow (m3/s), EDM Events, Active Sites... (use year slicer)
- Slicers: dim_date[year] (tile style), dim_date[season]
- Clustered column: Axis dim_date[year]; Values Rain Total (mm)
- Line chart: Axis dim_date[date]; Values Exe Flow (m3/s), Fal Flow (m3/s)

**Page 2 Rain -> River**
- Slicer: dim_date[water_year]
- Line and clustered column chart: Shared axis dim_date[date]; Columns Rain Mean Daily (mm); Line Exe Flow (m3/s)
- Scatter: X = Rain 14 Days (mm); Y = Exe Flow (m3/s); Details = dim_date[date]
- Text box (insight): "Exe flow responds within a day, but the last 14 days of rain explain flow far better than same-day rain."

**Page 3 Low flow**
- Clustered column: Axis dim_date[year]; Values Low Flow Days. Expect 2022 = 133, 2018 = 81, 2025 = 65.
- Card: Exe P10 Threshold (m3/s) (about 2.7)
- Text box: "Low-flow days cluster in 2022, 2018 and 2025, relevant to abstraction and supply planning."

**Page 4 Storm overflows 2025**
- Cards: EDM Events, EDM Hours, Active Sites
- Scatter: X = Rain 2 Days (mm); Y = EDM Events; Details = dim_date[date]
- Clustered bar: categories "Wet" and "Dry" is easiest as two cards: Avg Events Wet Days vs Avg Events Dry Days, plus card Wet vs Dry Ratio (about 6.4)
- Bar chart: Axis fact_edm_events[site_name]; Values Sum of hours; filter too_long = False; Top N = 10 by Sum of hours (Filters pane > Top N)
- Column chart: Axis dim_date[year_month]; Values EDM Events

**Page 5 Data quality**
- Matrix: Rows dim_station[station]; Columns fact_daily_readings[quality]; Values Readings
- Cards: Readings Not Good %, Missing Values, EDM Events Excluded (>7 days)
- Text box: "Fal Trenowth had duplicate daily readings for one year; the 09:00 reading was kept. Suspect/Estimated/Unchecked readings are kept but flagged. Events over 7 days are excluded from overflow counts."

**Page 6 Method & limits**
- Text box: sources (Environment Agency Hydrology API; Environment Agency / South West Water 2025 Detailed EDM Data; OGL v3), cleaning decisions, limitations (correlation is not causation; EDM data unverified; event counts are not volumes). Add GitHub link: github.com/su7ri/water-rainfall-river-overflow

## 6. Checks before you publish
- Year slicer = 2025: Rain Total about 1,269 mm, EDM Events about 209,355 (events <= 7 days).
- Low Flow Days per year matches the numbers on Page 3.
- Page 5: Hemyock about 22.9% not Good.
- If a measure errors, copy the error text to Claude.

## 7. Share it
File > Save as `.pbix` into the GitHub repo folder `powerbi/`. Take screenshots of each page (Win+Shift+S) and add them to the README. If you have a Power BI account (work or school email), Publish > "Publish to web" gives a public link (note: anyone can see it; the data here is open data).

## Known gaps
- Bellever Dartmoor and the two flow stations have no coordinates in dim_station, so skip a map.
