# Build a portable ZIP from the existing release artifacts.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$staging = Join-Path $env:TEMP "redforge-portable-v0.5.0"

if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
New-Item -ItemType Directory -Force -Path $staging | Out-Null

Copy-Item (Join-Path $root "src-tauri\target\release\redforge.exe") (Join-Path $staging "RedForge.exe")
Copy-Item (Join-Path $root "src-tauri\target\release\redforge-sidecar.exe") (Join-Path $staging "redforge-sidecar.exe")

@"
RedForge Portable v0.5.0
========================
Just double-click RedForge.exe to run.

The exe auto-spawns redforge-sidecar.exe (must be in the same folder).

For the AI Red Team Leader features, also install Ollama:
  https://ollama.com/
Then: ollama pull llama3.1:8b

AUTHORIZED USE ONLY. See https://github.com/synaptechintel/redforge
"@ | Out-File -FilePath (Join-Path $staging "README.txt") -Encoding utf8

$zip = Join-Path $root "RedForge_0.5.0_x64-portable.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $zip -CompressionLevel Optimal

$sizeMB = "{0:N1}" -f ((Get-Item $zip).Length / 1MB)
"Portable ZIP: $sizeMB MB at $zip"
