# Sleeper Roster Counts

Small Sleeper utility for quickly counting player totals in a dynasty league and checking taxi eligibility for the next league year.

The default league is:

```text
1314091850864279552
```

## Web App

Open the hosted app:

```text
https://schauf125.github.io/sleeper-roster-counts/
```

It runs entirely in the browser and calls Sleeper's public read-only API.

The page shows:

- main roster, IR, and taxi counts by team
- open taxi slots
- next-year taxi eligibility by player
- filtered CSV export

The player metadata fetched from Sleeper is cached in the browser for 24 hours.

## PowerShell CLI

The original CLI is still available.

```powershell
.\Get-SleeperRosterCounts.ps1
```

Show every player with section and taxi eligibility:

```powershell
.\Get-SleeperRosterCounts.ps1 -ShowPlayers
```

Export player detail to CSV:

```powershell
.\Get-SleeperRosterCounts.ps1 -ShowPlayers -CsvPath .\sleeper-roster-detail.csv
```

Use another league:

```powershell
.\Get-SleeperRosterCounts.ps1 -LeagueId 123456789012345678
```

## What It Counts

- `Main`: players on the roster who are not on IR and not on taxi
- `IR`: players in Sleeper's `reserve` array
- `Taxi`: players in Sleeper's `taxi` array
- `TaxiEligibleNextYear`: players whose projected next-year experience is within the league's `taxi_years`

For taxi eligibility, the script uses Sleeper's current `years_exp` value and projects next year as `years_exp + 1`. Team defenses are marked ineligible for taxi.
