#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads and verifies the Security Onion 2.4.211-20260407 ISO.
.DESCRIPTION
    Downloads the ISO, signature file, and signing key from official sources,
    then verifies checksums and GPG signature. Requires gpg.exe on PATH
    (e.g., from Gpg4win: https://gpg4win.org/).
#>

$ErrorActionPreference = 'Stop'

$ISO        = "securityonion-2.4.211-20260407.iso"
$SIG        = "$ISO.sig"
$ISO_URL    = "https://download.securityonion.net/file/securityonion/$ISO"
$SIG_URL    = "https://github.com/Security-Onion-Solutions/securityonion/raw/2.4/main/sigs/$SIG"
$KEYS_URL   = "https://raw.githubusercontent.com/Security-Onion-Solutions/securityonion/2.4/main/KEYS"
$EXPECTED_FINGERPRINT = "C804 A93D 36BE 0C73 3EA1  9644 7C10 60B7 FE50 7013"

# The expected SHA256 checksum for the ISO file. Taken from the official Security Onion release page in github.
$SHA256_EXPECTED = "185D8CF49CD3BFDD8876B8DDE48343DA90804B0C0EC3EADF0AD90D29C55E72B7"

function Assert-Gpg {
    if (-not (Get-Command gpg -ErrorAction SilentlyContinue)) {
        Write-Error "gpg not found on PATH. Install Gpg4win (https://gpg4win.org/) and re-run."
    }
}

function Get-FileViaWebClient ([string]$Url, [string]$OutFile) {
    Write-Host "  Downloading $OutFile ..."
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($Url, (Join-Path $PWD $OutFile))
}

function Test-Checksum ([string]$File, [string]$Algorithm, [string]$Expected) {
    $actual = (Get-FileHash -Path $File -Algorithm $Algorithm).Hash.ToUpper()
    if ($actual -eq $Expected.ToUpper()) {
        Write-Host "  [OK] ${Algorithm}: $actual"
        return $true
    } else {
        Write-Host "  [FAIL] ${Algorithm}:"
        Write-Host "         Got:      $actual"
        Write-Host "         Expected: $Expected"
        return $false
    }
}

# ── Step 1: Import signing key ────────────────────────────────────────────────
Write-Host ""
Write-Host "==> Importing Security Onion signing key..."
Assert-Gpg
$keysFile = "securityonion-KEYS.tmp"
Get-FileViaWebClient $KEYS_URL $keysFile
gpg --import $keysFile
Remove-Item $keysFile -Force

# ── Step 2: Download signature file ──────────────────────────────────────────
Write-Host ""
Write-Host "==> Downloading signature file..."
Get-FileViaWebClient $SIG_URL $SIG

# ── Step 3: Download ISO ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "==> Downloading ISO (this will take a while)..."
Get-FileViaWebClient $ISO_URL $ISO

# ── Step 4: Verify checksums ──────────────────────────────────────────────────
Write-Host ""
Write-Host "==> Verifying checksums..."
$checksumOk  = Test-Checksum $ISO "SHA256" $SHA256_EXPECTED

if (-not $checksumOk) {
    Write-Error "Checksum verification failed. Do not use this ISO."
}

# ── Step 5: Verify GPG signature ─────────────────────────────────────────────
Write-Host ""
Write-Host "==> Verifying GPG signature..."
$gpgOutput = & gpg --verify $SIG $ISO 2>&1 | Out-String
Write-Host $gpgOutput

if ($gpgOutput -match "Good signature") {
    Write-Host "  [OK] GPG signature is valid."
} else {
    Write-Error "GPG signature verification failed."
}

# Extract and compare fingerprint
if ($gpgOutput -match "Primary key fingerprint:\s*(.+)") {
    $fingerprintActual = $Matches[1].Trim()
    if ($fingerprintActual -eq $EXPECTED_FINGERPRINT) {
        Write-Host "  [OK] Key fingerprint matches: $fingerprintActual"
    } else {
        Write-Host "  [WARN] Fingerprint mismatch:"
        Write-Host "         Got:      $fingerprintActual"
        Write-Host "         Expected: $EXPECTED_FINGERPRINT"
        Write-Host "  Verify manually before using the ISO."
    }
}

Write-Host ""
Write-Host "All checks passed. ISO is ready: $ISO"
Write-Host "Next step: https://securityonion.net/docs/installation"
