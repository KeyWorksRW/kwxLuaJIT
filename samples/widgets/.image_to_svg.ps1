param(
  [string]$InputPath  = 'C:/rwCode/wxSamples/src/sample.xpm',
  [string]$OutputPath = 'C:/rwCode/wxLanguages/kwxLuaJIT/samples/widgets/sample.svg',
  [int]$MaxRuns = 250000
)
$ErrorActionPreference = 'Stop'
$inv = [System.Globalization.CultureInfo]::InvariantCulture
function Fail($msg) { Write-Output "FAILURE: $msg"; exit 1 }
function Inv($v) { return ([string]$v) }

if (-not (Test-Path -LiteralPath $InputPath)) { Fail "input not found $InputPath" }

$lines = Get-Content -LiteralPath $InputPath

# ---- collect every quoted payload string, in order -------------------------
$quoted = New-Object System.Collections.ArrayList
foreach ($ln in $lines) {
  $ms = [regex]::Matches($ln, '"([^"]*)"')
  foreach ($m in $ms) { [void]$quoted.Add($m.Groups[1].Value) }
}
if ($quoted.Count -lt 2) { Fail "malformed XPM $InputPath — no quoted data" }

# ---- header ---------------------------------------------------------------
$hdr = @($quoted[0] -split '\s+' | Where-Object { $_ -ne '' })
if ($hdr.Count -lt 4) { Fail "malformed XPM $InputPath — bad header" }
$w = [int]$hdr[0]; $h = [int]$hdr[1]; $ncolors = [int]$hdr[2]; $cpp = [int]$hdr[3]
if ($w -le 0 -or $h -le 0 -or $ncolors -le 0 -or $cpp -le 0) { Fail "malformed XPM $InputPath — non-positive header field" }
if ($quoted.Count -lt (1 + $ncolors + $h)) {
  Fail "malformed XPM $InputPath — declared $h pixel lines, file has $($quoted.Count - 1 - $ncolors)"
}

# ---- X11 colour names (only the documented set) ---------------------------
$names = @{
  'black'='000000'; 'white'='FFFFFF'; 'red'='FF0000'; 'green'='00FF00';
  'blue'='0000FF'; 'yellow'='FFFF00'; 'cyan'='00FFFF'; 'magenta'='FF00FF';
  'gray'='808080'; 'grey'='808080'; 'darkgray'='A9A9A9'; 'lightgray'='D3D3D3'
}

function Resolve-Rgb([string]$cname, [int]$lineNo) {
  $t = $cname.Trim()
  if ($t -ieq 'none') { return $null }              # transparent
  if ($t.StartsWith('#')) {
    $hex = $t.Substring(1)
    if ($hex -match '^[0-9A-Fa-f]{6}$') { return ('#' + $hex.ToUpperInvariant()) }
    if ($hex -match '^[0-9A-Fa-f]{12}$') {
      $r = [Convert]::ToInt32($hex.Substring(0,4),16) -shr 8
      $g = [Convert]::ToInt32($hex.Substring(4,4),16) -shr 8
      $b = [Convert]::ToInt32($hex.Substring(8,4),16) -shr 8
      return ('#{0:X2}{1:X2}{2:X2}' -f $r,$g,$b)
    }
    Fail "malformed XPM $InputPath — unsupported hex colour '$t' at line $lineNo"
  }
  $k = $t.ToLowerInvariant()
  if ($names.ContainsKey($k)) { return ('#' + $names[$k]) }
  Fail "unresolved XPM colour `"$cname`" at line $lineNo — supply an RGB value"
}

# ---- palette --------------------------------------------------------------
$palette = @{}
for ($i = 0; $i -lt $ncolors; $i++) {
  $cl = [string]$quoted[1 + $i]
  if ($cl.Length -lt $cpp) { Fail "malformed XPM $InputPath — colour line $($i+1) shorter than cpp=$cpp" }
  $key = $cl.Substring(0, $cpp)
  $toks = @($cl.Substring($cpp) -split '\s+' | Where-Object { $_ -ne '' })
  $ci = -1
  for ($k = 0; $k -lt ($toks.Count - 1); $k++) { if ($toks[$k] -eq 'c') { $ci = $k + 1; break } }
  if ($ci -lt 0) { Fail "malformed XPM $InputPath — colour line without 'c' key: $cl" }
  $palette[$key] = Resolve-Rgb $toks[$ci] ($i + 1)
}

# ---- pixels ---------------------------------------------------------------
$grid = New-Object 'object[]' $h
for ($y = 0; $y -lt $h; $y++) {
  $pl = [string]$quoted[1 + $ncolors + $y]
  if ($pl.Length -lt ($w * $cpp)) {
    Fail "malformed XPM $InputPath — pixel line $($y+1) has $($pl.Length) chars, needs $($w*$cpp)"
  }
  $row = New-Object 'object[]' $w
  for ($x = 0; $x -lt $w; $x++) {
    $pc = $pl.Substring($x * $cpp, $cpp)
    if (-not $palette.ContainsKey($pc)) {
      Fail "malformed XPM $InputPath — pixel char '$pc' outside palette at row $($y+1), column $($x+1)"
    }
    $row[$x] = $palette[$pc]
  }
  $grid[$y] = $row
}

# ---- horizontal runs, then vertical merge of identical runs ---------------
$rects = New-Object System.Collections.ArrayList
$active = @{}
$horizRuns = 0
$opaque = 0
for ($y = 0; $y -lt $h; $y++) {
  $row = $grid[$y]
  $next = @{}
  $x = 0
  while ($x -lt $w) {
    $col = $row[$x]
    if ($null -eq $col) { $x++; continue }
    $runW = 1
    while (($x + $runW) -lt $w -and $row[$x + $runW] -eq $col) { $runW++ }
    $horizRuns++
    $opaque += $runW
    $key = "$x|$runW|$col"
    if ($active.ContainsKey($key)) {
      $r = $active[$key]
      $r.H = $r.H + 1
      $next[$key] = $r
    } else {
      $r = [pscustomobject]@{ X = $x; Y = $y; W = $runW; H = 1; Color = $col }
      [void]$rects.Add($r)
      $next[$key] = $r
    }
    $x += $runW
  }
  $active = $next
}

$runCount = $rects.Count
if ($runCount -gt $MaxRuns) {
  if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }
  Fail "$runCount runs exceed MAX_RUNS ($MaxRuns) - rerun with MODE: quantize COLORS: 64"
}

# ---- bounds + coverage assertions ----------------------------------------
$covered = 0
foreach ($r in $rects) {
  if (($r.X + $r.W) -gt $w) { Fail "internal: rect x+w exceeds width" }
  if (($r.Y + $r.H) -gt $h) { Fail "internal: rect y+h exceeds height" }
  $covered += ($r.W * $r.H)
}
if ($covered -ne $opaque) { Fail "internal: coverage $covered != opaque pixels $opaque" }

$colorsUsed = @($rects | ForEach-Object { $_.Color } | Sort-Object -Unique).Count

# ---- SVG -----------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("<svg xmlns=""http://www.w3.org/2000/svg"" version=""1.2"" baseProfile=""full"" width=""$(Inv $w)"" height=""$(Inv $h)"" viewBox=""0 0 $(Inv $w) $(Inv $h)"" shape-rendering=""crispEdges"">`n")
[void]$sb.Append("<!-- source: $(Split-Path -Leaf $InputPath) -->`n")
foreach ($r in $rects) {
  [void]$sb.Append("<rect x=""$(Inv $r.X)"" y=""$(Inv $r.Y)"" width=""$(Inv $r.W)"" height=""$(Inv $r.H)"" fill=""$($r.Color)""/>`n")
}
[void]$sb.Append("</svg>`n")

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), $enc)

$bytes = (Get-Item -LiteralPath $OutputPath).Length
Write-Output "RESULT W=$w H=$h cpp=$cpp ncolors=$ncolors horizRuns=$horizRuns rects=$runCount colors=$colorsUsed bytes=$bytes"
exit 0
