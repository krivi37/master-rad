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

$envPath = Join-Path $PSScriptRoot '.env'
$envExamplePath = Join-Path $PSScriptRoot '.env.example'
if (-not (Test-Path -LiteralPath $envPath)) {
    if (-not (Test-Path -LiteralPath $envExamplePath -PathType Leaf)) {
        throw 'Cannot create .env because .env.example is missing.'
    }

    $envContent = [System.IO.File]::ReadAllText($envExamplePath)
    $passwords = [ordered]@{
        LDAP_RTI_ADMIN_PASSWORD      = 'admin-ldap'
        LDAP_SI_ADMIN_PASSWORD       = 'admin-ldap'
        KEYCLOAK_ADMIN_PASSWORD      = 'admin-keycloak'
        KEYCLOAK_LDAP_BIND_PASSWORD  = 'admin-ldap'
        WEBAPP_B_SESSION_SECRET      = 'webapp-si-saml-session-pass'
    }

    foreach ($password in $passwords.GetEnumerator()) {
        $pattern = '(?m)^' + [regex]::Escape($password.Key) + '=.*$'
        if (-not [regex]::IsMatch($envContent, $pattern)) {
            throw "Missing $($password.Key) in .env.example."
        }
        $envContent = [regex]::Replace($envContent, $pattern, "$($password.Key)=$($password.Value)")
    }

    Copy-Item -LiteralPath $envExamplePath -Destination $envPath
    [System.IO.File]::WriteAllText($envPath, $envContent, [System.Text.UTF8Encoding]::new($false))
    Write-Host 'Created .env from .env.example with lab development passwords.'
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker CLI is not installed or is not available in PATH.'
}

function Test-DockerRunning {
    $ErrorActionPreference = 'SilentlyContinue'
    docker info *> $null
    return $LASTEXITCODE -eq 0
}

if (-not (Test-DockerRunning)) {
    Write-Host 'Docker is not running. Starting Docker Desktop...'
    docker desktop start

    $dockerReady = $false
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        Start-Sleep -Seconds 2
        if (Test-DockerRunning) {
            $dockerReady = $true
            break
        }
    }

    if (-not $dockerReady) {
        throw 'Docker did not become ready within 120 seconds.'
    }
}

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
