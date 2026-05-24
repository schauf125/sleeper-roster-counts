param(
    [string]$LeagueId = "1314091850864279552",
    [switch]$ShowPlayers,
    [string]$CsvPath
)

$ErrorActionPreference = "Stop"

function Get-SleeperApi {
    param([string]$Path)

    $uri = "https://api.sleeper.app/v1/$Path"
    Invoke-RestMethod -Uri $uri -Headers @{ "Accept" = "application/json" }
}

function Get-PlayerValue {
    param(
        [object]$Players,
        [string]$PlayerId
    )

    if (-not $PlayerId -or $PlayerId -eq "0") {
        return $null
    }

    $prop = $Players.PSObject.Properties[$PlayerId]
    if ($prop) {
        return $prop.Value
    }

    return $null
}

function Get-PlayerName {
    param(
        [object]$Player,
        [string]$PlayerId
    )

    if ($Player -and $Player.full_name) {
        return $Player.full_name
    }

    if ($Player -and $Player.position -eq "DEF") {
        return "$PlayerId Defense"
    }

    return $PlayerId
}

function Get-RosterSection {
    param(
        [string]$PlayerId,
        [string[]]$ReserveIds,
        [string[]]$TaxiIds
    )

    if ($ReserveIds -contains $PlayerId) {
        return "IR"
    }

    if ($TaxiIds -contains $PlayerId) {
        return "Taxi"
    }

    return "Main"
}

function Get-TaxiEligibility {
    param(
        [object]$Player,
        [int]$TaxiYears
    )

    if (-not $Player) {
        return [pscustomobject]@{
            NextYearEligible = "Unknown"
            CurrentYearsExp = $null
            NextYearsExp = $null
            Reason = "Player metadata was not found."
        }
    }

    if ($Player.position -eq "DEF") {
        return [pscustomobject]@{
            NextYearEligible = "No"
            CurrentYearsExp = $null
            NextYearsExp = $null
            Reason = "Team defenses are not taxi candidates."
        }
    }

    if ($null -eq $Player.years_exp) {
        return [pscustomobject]@{
            NextYearEligible = "Unknown"
            CurrentYearsExp = $null
            NextYearsExp = $null
            Reason = "Sleeper did not provide years_exp."
        }
    }

    $currentYearsExp = [int]$Player.years_exp
    $nextYearsExp = $currentYearsExp + 1
    $eligible = $nextYearsExp -le $TaxiYears

    if ($eligible) {
        $reason = "Projected $nextYearsExp years exp is within taxi_years=$TaxiYears."
        $eligibleText = "Yes"
    } else {
        $reason = "Projected $nextYearsExp years exp exceeds taxi_years=$TaxiYears."
        $eligibleText = "No"
    }

    return [pscustomobject]@{
        NextYearEligible = $eligibleText
        CurrentYearsExp = $currentYearsExp
        NextYearsExp = $nextYearsExp
        Reason = $reason
    }
}

$league = Get-SleeperApi -Path "league/$LeagueId"
$rosters = Get-SleeperApi -Path "league/$LeagueId/rosters"
$users = Get-SleeperApi -Path "league/$LeagueId/users"
$players = Get-SleeperApi -Path "players/nfl"

$usersById = @{}
foreach ($user in $users) {
    $usersById[$user.user_id] = $user
}

$taxiYears = [int]$league.settings.taxi_years
$taxiSlots = [int]$league.settings.taxi_slots
$nextSeason = [int]$league.season + 1

$summaryRows = foreach ($roster in ($rosters | Sort-Object roster_id)) {
    $user = $usersById[$roster.owner_id]
    $teamName = $null
    if ($user -and $user.metadata -and $user.metadata.team_name) {
        $teamName = $user.metadata.team_name
    }
    if (-not $teamName -and $user) {
        $teamName = $user.display_name
    }
    if (-not $teamName) {
        $teamName = "Roster $($roster.roster_id)"
    }

    $playerIds = @($roster.players) | Where-Object { $_ -and $_ -ne "0" }
    $reserveIds = @($roster.reserve) | Where-Object { $_ -and $_ -ne "0" }
    $taxiIds = @($roster.taxi) | Where-Object { $_ -and $_ -ne "0" }
    $mainIds = $playerIds | Where-Object { ($reserveIds -notcontains $_) -and ($taxiIds -notcontains $_) }

    $eligibleNextYear = 0
    foreach ($playerId in $playerIds) {
        $player = Get-PlayerValue -Players $players -PlayerId $playerId
        $eligibility = Get-TaxiEligibility -Player $player -TaxiYears $taxiYears
        if ($eligibility.NextYearEligible -eq "Yes") {
            $eligibleNextYear += 1
        }
    }

    [pscustomobject]@{
        Roster = $roster.roster_id
        Team = $teamName
        User = if ($user) { $user.display_name } else { $roster.owner_id }
        Total = $playerIds.Count
        Main = @($mainIds).Count
        IR = $reserveIds.Count
        Taxi = $taxiIds.Count
        TaxiSlots = $taxiSlots
        TaxiOpen = [Math]::Max(0, $taxiSlots - $taxiIds.Count)
        TaxiEligibleNextYear = $eligibleNextYear
    }
}

$playerRows = foreach ($roster in ($rosters | Sort-Object roster_id)) {
    $user = $usersById[$roster.owner_id]
    $teamName = $null
    if ($user -and $user.metadata -and $user.metadata.team_name) {
        $teamName = $user.metadata.team_name
    }
    if (-not $teamName -and $user) {
        $teamName = $user.display_name
    }
    if (-not $teamName) {
        $teamName = "Roster $($roster.roster_id)"
    }

    $reserveIds = @($roster.reserve) | Where-Object { $_ -and $_ -ne "0" }
    $taxiIds = @($roster.taxi) | Where-Object { $_ -and $_ -ne "0" }

    foreach ($playerId in (@($roster.players) | Where-Object { $_ -and $_ -ne "0" } | Sort-Object)) {
        $player = Get-PlayerValue -Players $players -PlayerId $playerId
        $eligibility = Get-TaxiEligibility -Player $player -TaxiYears $taxiYears

        [pscustomobject]@{
            Roster = $roster.roster_id
            Team = $teamName
            User = if ($user) { $user.display_name } else { $roster.owner_id }
            Section = Get-RosterSection -PlayerId $playerId -ReserveIds $reserveIds -TaxiIds $taxiIds
            PlayerId = $playerId
            Player = Get-PlayerName -Player $player -PlayerId $playerId
            Position = if ($player) { $player.position } else { $null }
            NFLTeam = if ($player) { $player.team } else { $null }
            Status = if ($player) { $player.status } else { $null }
            CurrentYearsExp = $eligibility.CurrentYearsExp
            NextYearsExp = $eligibility.NextYearsExp
            TaxiEligibleInNextSeason = $eligibility.NextYearEligible
            TaxiReason = $eligibility.Reason
        }
    }
}

Write-Host ""
Write-Host "$($league.name) roster counts for Sleeper league $LeagueId"
Write-Host "Current league season: $($league.season); next league year checked: $nextSeason"
Write-Host "Taxi settings: $taxiSlots slots, taxi_years=$taxiYears, taxi_allow_vets=$($league.settings.taxi_allow_vets)"
Write-Host "Taxi eligibility assumes next year experience = Sleeper years_exp + 1."
Write-Host ""

$summaryRows | Format-Table -AutoSize

if ($ShowPlayers) {
    Write-Host ""
    Write-Host "Player detail"
    $playerRows |
        Select-Object Roster, Team, Section, Player, Position, NFLTeam, CurrentYearsExp, NextYearsExp, TaxiEligibleInNextSeason |
        Format-Table -AutoSize
}

if ($CsvPath) {
    $playerRows | Export-Csv -Path $CsvPath -NoTypeInformation
    Write-Host ""
    Write-Host "Wrote player detail CSV to $CsvPath"
}
