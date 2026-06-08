# RedForge - Production Build Smoke Test
# Tests every critical API endpoint against the bundled sidecar exe.

param([string]$ExePath = "C:\Users\waspf\rftest\redforge\sidecar\dist\redforge-sidecar.exe")

$ErrorActionPreference = "Stop"
$base = "http://127.0.0.1:18765"

function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Fail($m) { Write-Host "  [!!] $m" -ForegroundColor Red }
function Sec($m)  { Write-Host "`n=== $m ===" -ForegroundColor Cyan }

Get-Process -Name "redforge-sidecar" -ErrorAction SilentlyContinue | Stop-Process -Force

$dataDir = "C:\Users\waspf\rftest\redforge\test-data"
if (Test-Path $dataDir) { Remove-Item -Recurse -Force $dataDir }
$env:REDFORGE_DATA_DIR = $dataDir

Write-Host "Starting bundled sidecar: $ExePath" -ForegroundColor Yellow
$proc = Start-Process -FilePath $ExePath -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 7

$passed = 0
$failed = 0

try {
    # ─── 1. Health ──────────────────────────────────────────────────
    Sec "1. Health endpoint"
    $h = Invoke-RestMethod "$base/health"
    if ($h.status -eq "ok" -and $h.attack_data_loaded) {
        Ok "status=$($h.status), ATT&CK loaded, db_ready=$($h.db_ready)"
        Ok "ATT&CK: $($h.attack_data_stats.total_techniques) techniques, $($h.attack_data_stats.total_tactics) tactics"
        $passed++
    } else { Fail "Health unhealthy: $($h | ConvertTo-Json -Compress)"; $failed++ }

    # ─── 2. Tactics list ────────────────────────────────────────────
    Sec "2. ATT&CK tactics"
    $tactics = Invoke-RestMethod "$base/api/attack/tactics"
    if ($tactics.Count -ge 14) {
        Ok "$($tactics.Count) tactics returned"
        $tactics | Select-Object -First 3 | ForEach-Object { Write-Host "      $($_.external_id) - $($_.name)" -ForegroundColor DarkGray }
        $passed++
    } else { Fail "Only $($tactics.Count) tactics"; $failed++ }

    # ─── 3. Technique search ────────────────────────────────────────
    Sec "3. Technique search ('lsass')"
    $r = Invoke-RestMethod "$base/api/attack/techniques?q=lsass&limit=5"
    if ($r.count -gt 0) {
        Ok "$($r.count) matches"
        $r.techniques | ForEach-Object { Write-Host "      $($_.external_id) - $($_.name)" -ForegroundColor DarkGray }
        $passed++
    } else { Fail "No matches"; $failed++ }

    # ─── 4. Single technique detail ─────────────────────────────────
    Sec "4. Technique detail (T1003.001)"
    $t = Invoke-RestMethod "$base/api/attack/techniques/T1003.001"
    if ($t.name -match "LSASS") {
        Ok "Got: $($t.external_id) - $($t.name)"
        Ok "Tactics: $($t.tactics -join ', ')"
        $passed++
    } else { Fail "Unexpected: $($t | ConvertTo-Json -Compress)"; $failed++ }

    # ─── 5. Create operation ────────────────────────────────────────
    Sec "5. Create operation"
    $op = Invoke-RestMethod "$base/api/operations" -Method Post -ContentType "application/json" -Body '{"name":"Smoke Test Op","description":"prod verify","scope":"lab"}'
    if ($op.id) {
        Ok "Created: id=$($op.id)"
        $passed++
    } else { Fail "No id returned"; $failed++ }

    # ─── 6. Log timeline event ──────────────────────────────────────
    Sec "6. Log timeline event"
    $ev = Invoke-RestMethod "$base/api/operations/$($op.id)/timeline" -Method Post -ContentType "application/json" -Body '{"type":"execution","notes":"smoke test","technique_id":"T1003.001","command":"whoami"}'
    if ($ev.id) {
        Ok "Event logged: $($ev.id) at $($ev.timestamp)"
        $passed++
    } else { Fail "No event id"; $failed++ }

    # ─── 7. Suggest techniques for command ──────────────────────────
    Sec "7. Suggest techniques for 'mimikatz sekurlsa::logonpasswords'"
    $s = Invoke-RestMethod -Method Post -Uri "$base/api/suggest_techniques?command=mimikatz+sekurlsa::logonpasswords&execution_method=local"
    if ($s.suggestions.Count -gt 0) {
        Ok "$($s.suggestions.Count) suggestions"
        $s.suggestions | Select-Object -First 3 | ForEach-Object { Write-Host "      $($_.external_id) - $($_.name) (score=$($_.score))" -ForegroundColor DarkGray }
        $passed++
    } else { Fail "No suggestions"; $failed++ }

    # ─── 8. Local recon scan ────────────────────────────────────────
    Sec "8. Local recon scan (localhost common ports)"
    $rec = Invoke-RestMethod "$base/api/recon/scan" -Method Post -ContentType "application/json" -Body '{"target":"127.0.0.1","ports":"135,445,1433,3389,5985"}'
    Ok "Open ports on localhost: $($rec.open_ports.Count)"
    $rec.open_ports | ForEach-Object { Write-Host "      $($_.host):$($_.port) ($($_.status))" -ForegroundColor DarkGray }
    $passed++

    # ─── 9. Parse pasted nmap output ────────────────────────────────
    Sec "9. Parse nmap-style output"
    $body = @{ raw_output = "Nmap scan report for 10.0.0.5`n22/tcp open ssh`n445/tcp open microsoft-ds`n3389/tcp open ms-wbt-server" } | ConvertTo-Json
    $par = Invoke-RestMethod "$base/api/recon/parse" -Method Post -ContentType "application/json" -Body $body
    if ($par.count -ge 3) {
        Ok "Parsed $($par.count) assets"
        $par.assets | ForEach-Object { Write-Host "      $($_.host):$($_.port) ($($_.service))" -ForegroundColor DarkGray }
        $passed++
    } else { Fail "Expected 3 assets, got $($par.count)"; $failed++ }

    # ─── 10. Generate follow-up command ─────────────────────────────
    Sec "10. Generate follow-up (lateral movement after scan)"
    $body = @{ output = "10.0.0.5`n445/tcp open microsoft-ds"; scenario = "lateral_movement"; target_os = "windows"; output_type = "command" } | ConvertTo-Json
    $gen = Invoke-RestMethod "$base/api/generate_followup" -Method Post -ContentType "application/json" -Body $body
    if ($gen.suggested_command) {
        Ok "Generated: $($gen.suggested_command)"
        Ok "Technique: $($gen.technique)"
        $passed++
    } else { Fail "No command"; $failed++ }

    # ─── 11. Chain builder ──────────────────────────────────────────
    Sec "11. Create + add steps to attack chain"
    $chain = Invoke-RestMethod "$base/api/operations/$($op.id)/chains" -Method Post -ContentType "application/json" -Body '{"name":"Smoke Chain","description":"test chain"}'
    $chain2 = Invoke-RestMethod "$base/api/chains/$($chain.id)/steps?technique_id=T1003.001" -Method Post
    $chain3 = Invoke-RestMethod "$base/api/chains/$($chain.id)/steps?technique_id=T1021.002" -Method Post
    Ok "Chain $($chain.id) created with $($chain3.steps.Count) steps"
    $passed++

    # ─── 12. List operations & verify DB persisted ──────────────────
    Sec "12. List operations & timeline"
    $ops = Invoke-RestMethod "$base/api/operations"
    $tl = Invoke-RestMethod "$base/api/operations/$($op.id)/timeline"
    Ok "Operations: $($ops.Count), Timeline events for op: $($tl.Count)"
    $passed++

    # ─── 13. DB file actually exists & has data ─────────────────────
    Sec "13. DB persistence"
    $dbFile = Join-Path $dataDir "redforge.db"
    if (Test-Path $dbFile) {
        $sz = (Get-Item $dbFile).Length
        Ok "redforge.db exists: $sz bytes"
        $passed++
    } else { Fail "No DB file at $dbFile"; $failed++ }

} catch {
    Fail "EXCEPTION: $_"
    Fail $_.ScriptStackTrace
    $failed++
} finally {
    Get-Process -Name "redforge-sidecar" -ErrorAction SilentlyContinue | Stop-Process -Force
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
if ($failed -eq 0) {
    Write-Host " ALL $passed TESTS PASSED" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host " RESULTS: $passed passed, $failed failed" -ForegroundColor Yellow
    Write-Host "=============================================" -ForegroundColor Cyan
    exit 1
}
