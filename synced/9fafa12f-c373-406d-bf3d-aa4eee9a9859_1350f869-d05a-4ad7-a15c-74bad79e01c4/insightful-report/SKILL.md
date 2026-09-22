---
name: insightful-report
description: "Generates the weekly tech team productivity report from Insightful and sends it via Slack DM."
---

Every time the user asks to generate the weekly productivity report, follow these exact steps:

## Week logic
- Get current date from Insightful's get_current_datetime tool
- Find most recent Monday: current_monday = today - timedelta(days=today.weekday())
- Last week = current_monday - 1 week (Mon) → current_monday - 1 week + 6 days (Sun)
- 2 weeks ago = current_monday - 2 weeks (Mon) → current_monday - 2 weeks + 6 days (Sun)
- Never include the current week. Convert to Unix ms timestamps using calendar.timegm (UTC).

## Data fetching
- Call get_timesheets_per_day for LAST WEEK with all 12 tech team IDs
- Call get_timesheets_per_day for 2 WEEKS AGO with same IDs
- Aggregate per employee: sum productiveTotalTime across all days. Ignore all other fields.

Tech team IDs:
wypakesijvzckfr=Kdabra CRM, waan8eta1i6tphu=Kdabra Retail, w6f-fed1mm3petn=Kdabra Logistics, wrsj1o6xlwu9mr8=Driver App, wuzvhaakucoak9l=Lojas UX, wyhlqfgq2gquq06=Lojas QA, wyyahyunwf6qtd7=Lojas Web & Platform, w7fgftugetinpmm=Lojas Totem, wxlrcadjivmvlls=Managers, wdmsjv29gqmmvmu=Lojas App Android, wmc1o7-9hqvhcuz=Lojas App iOS, wm-a8fuqnpqf9nz=Lojas Managers

## Calculations
- All times as H:MM (e.g. 27:30, 960:59) — never decimals
- Prod % = productive_minutes / (44 * 60) * 100, rounded to integer (44h = expected week)
- Trend hrs diff = (last_week_ms - two_weeks_ms) → format as +H:MM or -H:MM
- Trend % = ((last_week - two_weeks) / two_weeks) * 100, 1 decimal, prefixed + or -
- Summary avg prod % = total_prod_minutes / (employee_count * 44 * 60) * 100

## Excel file — single sheet named "Productivity Report", no other sheets, tab color 16A34A
Colors: BG=F7F8FA, SURFACE=FFFFFF, SURFACE2=F0F2F5, HDR_BG=1A1C21, HDR_FG=9A9FA8, TITLE_FG=1A1C21, MUTED=6B7280, DARK=111827, ACCENT=16A34A, ACCENT2=15803D, BLUE=2563EB, RED_C=DC2626, AMBER=D97706, BORDER=E5E7EB

Layout:
- Row 1 (h=18): padding
- Row 2 (h=40): Title "Tech Team — Weekly Productivity Report" Arial 18 bold TITLE_FG
- Row 3 (h=18): "Generated {date}  •  Expected hours per employee: 44h/week" Arial 9 MUTED
- Row 4 (h=14): padding
- Rows 5–9: 3 summary cards side by side on SURFACE background
  - Card 1 cols B–D: label=LAST WEEK PRODUCTIVE HRS / value=total HH:MM / sub=date range
  - Card 2 cols E–F: label=AVG PROD vs 44h / value=avg_pct% in ACCENT2 / sub=N employees tracked
  - Card 3 cols G–I: label=TREND vs 2 WEEKS AGO / value=+X.X% (+H:MM) green if positive RED_C if negative / sub=2 wks ago: HH:MM
- Row 10 (h=8): padding
- Row 11 (h=18): "EMPLOYEE BREAKDOWN — N tech employees" Arial 8 MUTED
- Row 12 (h=18): week group sub-headers on HDR_BG — cols D–E=Last week MMM DD–DD in ACCENT, cols F–G=2 weeks ago in BLUE, cols H–I=Trend in AMBER, cols B–C empty HDR_BG
- Row 13 (h=20): column headers on HDR_BG, text HDR_FG, bot border #444444 — B=EMPLOYEE, C=SQUAD, D=PROD HRS, E=PROD %, F=PROD HRS, G=PROD %, H=HRS DIFF, I=% DIFF
- Rows 14+: one row per employee (h=19), alternating SURFACE/SURFACE2, sorted by last week prod hrs descending
  - Name: DARK left; Squad: MUTED left; Hours: DARK center; Prod %: ≥90% ACCENT ≥70% AMBER <70% RED_C center
  - Trend HRS DIFF and % DIFF: ACCENT if positive, RED_C if negative, MUTED if zero
  - Bottom border BORDER on every cell
- Last row+2 (h=14): footer italic MUTED Arial 8 — "Prod % = productive hours ÷ 44h expected  •  Trend compares last week vs 2 weeks ago"

Column widths: A=1.5, B=26, C=20, D=13, E=10, F=13, G=10, H=13, I=10, J=1.5

## Delivery
1. Save as weekly_productivity_report.xlsx, copy to /mnt/user-data/outputs/, present with present_files
2. Send a Slack DM to ULCDA965S (Thiago Moraes Stefani) with a formatted summary including total hours, avg prod %, trend, and a monospace table of all employees with columns: Employee, Squad, LW Hrs, LW%, 2WA Hrs, 2WA%, Diff, %Diff