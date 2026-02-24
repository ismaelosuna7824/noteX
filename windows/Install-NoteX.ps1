# Install-NoteX.ps1 — NoteX Windows Installer
# Place this file next to NoteX-windows.msix and NoteX-cert.cer, then right-click → Run with PowerShell

# Self-elevate to Administrator if needed
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cerPath  = Join-Path $dir "NoteX-cert.cer"
$msixPath = Join-Path $dir "NoteX-windows.msix"

Write-Host "NoteX Installer" -ForegroundColor Cyan
Write-Host "----------------" -ForegroundColor Cyan

# 1 — Install certificate
if (Test-Path $cerPath) {
    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($cerPath)
    Import-Certificate -Certificate $cert -CertStoreLocation "Cert:\LocalMachine\Root"         | Out-Null
    Import-Certificate -Certificate $cert -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" | Out-Null
    Write-Host "Certificado instalado correctamente." -ForegroundColor Green
} else {
    Write-Host "ERROR: No se encontro NoteX-cert.cer junto a este script." -ForegroundColor Red
    Read-Host "Presiona Enter para salir"
    exit 1
}

# 2 — Install MSIX
if (Test-Path $msixPath) {
    Write-Host "Instalando NoteX..." -ForegroundColor Cyan
    Add-AppxPackage -Path $msixPath
    Write-Host "NoteX instalado exitosamente!" -ForegroundColor Green
} else {
    Write-Host "ERROR: No se encontro NoteX-windows.msix junto a este script." -ForegroundColor Red
    exit 1
}

Read-Host "Presiona Enter para cerrar"
