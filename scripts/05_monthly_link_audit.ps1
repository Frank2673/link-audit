param(
  [string]$LinksFile = 'links.txt',
  [string]$OutCsv = 'status.csv'
)

# Monthly audit of official documentation links.
# Probe order: sequential, same-host pacing >= 250ms.
# Verdicts: OK / REDIRECT_OK / NETWORK / PARTIAL / RATE_LIMITED / REJECT_403 / REJECT_HEADERS_OK

$ProgressPreference = 'SilentlyContinue'
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$STD = @('-A', $UA,
  '-H', 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  '-H', 'Accept-Language: zh-CN,zh;q=0.9,en;q=0.8')
$NAV = @(
  '-H', 'sec-ch-ua: "Chromium";v="131", "Not_A Brand";v="24"',
  '-H', 'sec-ch-ua-mobile: ?0',
  '-H', 'sec-ch-ua-platform: "Windows"',
  '-H', 'Sec-Fetch-Dest: document',
  '-H', 'Sec-Fetch-Mode: navigate',
  '-H', 'Sec-Fetch-Site: none',
  '-H', 'Sec-Fetch-User: ?1',
  '-H', 'Upgrade-Insecure-Requests: 1')

function Probe([string]$u, [string[]]$h, [int]$t = 25) {
  $raw = & curl.exe -sS -L --max-redirs 6 --max-time $t -o NUL @h -w '%{http_code},%{num_redirects},%{url_effective}' $u 2>$null
  $p = (($raw -join '') -split ',')
  $final = ''
  if ($p.Count -gt 2) { $final = ($p[2..($p.Count - 1)] -join ',') }
  [pscustomobject]@{
    code      = ($p[0] -replace '\D', '')
    redirects = if ($p.Count -gt 1) { [int]$p[1] } else { 0 }
    final     = $final
    exit      = $LASTEXITCODE
  }
}

$rows = @()
$last = @{}
$lines = @(Get-Content $LinksFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

foreach ($u in $lines) {
  $hst = ([uri]$u).Host
  if ($last.ContainsKey($hst)) {
    $w = 250 - ((Get-Date) - $last[$hst]).TotalMilliseconds
    if ($w -gt 0) { Start-Sleep -Milliseconds $w }
  }
  $r = Probe $u $STD
  $last[$hst] = Get-Date
  $v = if ($r.code -eq '000') { 'NETWORK' }
       elseif ($r.code -eq '429') { 'RATE_LIMITED' }
       elseif ($r.code -eq '200' -and $r.exit -ne 0) { 'PARTIAL' }
       elseif ($r.code -eq '200' -and $r.redirects -eq 0) { 'OK' }
       elseif ($r.code -eq '200') { 'REDIRECT_OK' }
       else { 'REJECT_403' }

  if ($v -eq 'RATE_LIMITED') {
    Start-Sleep -Seconds 3
    $r2 = Probe $u $STD
    if ($r2.code -eq '200') {
      $r = $r2
      $v = if ($r2.exit -ne 0) { 'PARTIAL' } elseif ($r2.redirects -eq 0) { 'OK' } else { 'REDIRECT_OK' }
    }
    else { $r = $r2; $v = 'RATE_LIMITED' }
  }

  if ($v -eq 'PARTIAL') {
    $r2 = Probe $u $STD 40
    if ($r2.code -eq '200' -and $r2.exit -eq 0) {
      $r = $r2
      $v = if ($r2.redirects -eq 0) { 'OK' } else { 'REDIRECT_OK' }
    }
  }

  if ($v -eq 'REJECT_403') {
    Start-Sleep -Milliseconds 300
    $r2 = Probe $u ($STD + $NAV)
    if ($r2.code -ne '200') { Start-Sleep -Seconds 1; $r2 = Probe $u ($STD + $NAV) }
    if ($r2.code -eq '200') { $v = 'REJECT_HEADERS_OK'; $r = $r2 }
  }

  $rows += [pscustomobject]@{
    url           = $u
    http_code     = $r.code
    redirects     = $r.redirects
    effective_url = $r.final
    curl_exit     = $r.exit
    verdict       = $v
    checked_at    = (Get-Date -Format s)
  }
  Write-Host ("[{0:D2}] {1,-5} {2,-17} {3}" -f $rows.Count, $r.code, $v, $u)
}

$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutCsv
$rows | Group-Object verdict | Sort-Object Name | Format-Table Count, Name -AutoSize
"TOTAL=$($rows.Count)"
