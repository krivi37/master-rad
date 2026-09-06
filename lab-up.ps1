#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Bring the lab up (Windows/PowerShell). Twin of lab-up.sh.

.DESCRIPTION
    First regenerates docker-compose.override.yml from the copy counts, then runs
    `docker compose up`. When either count is > 1 the extra web app copies are
    generated and started; when both are 1 only the base apps come up.

.EXAMPLE
    ./lab-up.ps1
    ./lab-up.ps1 3 2
    ./lab-up.ps1 3 2 -- --no-build
#>
param(
    [int]$RtiCopies = -1,
    [int]$SiCopies = -1,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ComposeArgs
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# Export explicit counts so keycloak-init / compose resolve the same values. When
# a count is omitted, clear any value left from an earlier call in this session so
# it falls back to .env / default instead of sticking (PowerShell keeps $env:* set).
if ($RtiCopies -ge 0) { $env:WEBAPP_RTI_COPIES = "$RtiCopies" }
else { Remove-Item Env:WEBAPP_RTI_COPIES -ErrorAction SilentlyContinue }
if ($SiCopies -ge 0) { $env:WEBAPP_SI_COPIES = "$SiCopies" }
else { Remove-Item Env:WEBAPP_SI_COPIES -ErrorAction SilentlyContinue }

& "$PSScriptRoot/generate-webapp-copies.ps1" -RtiCopies $RtiCopies -SiCopies $SiCopies

# Drop a leading "--" separator if present.
if ($ComposeArgs -and $ComposeArgs[0] -eq '--') { $ComposeArgs = $ComposeArgs[1..($ComposeArgs.Count - 1)] }

Write-Host "Starting stack: docker compose up -d --build $ComposeArgs"
docker compose up -d --build @ComposeArgs
