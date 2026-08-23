<#
.SYNOPSIS
  Builds/updates manifest.json for the VB6 auto-updater.

.DESCRIPTION
  Scans your build output (the EXE + the .rpt report files) and writes
  their name/type/checksum/size into manifest.json. If manifest.json
  already exists, any "url" value you already filled in (the OneDrive/
  Google Drive direct-download link for that file) is preserved - only
  checksum/size are refreshed. New files get an empty "url" that you
  must fill in by hand after uploading them.

  If -BaseUrl is supplied (self-hosted server case), url is always
  auto-derived as "$BaseUrl/$fileName" instead - no manual link copying.

.EXAMPLE
  Self-hosted IIS server - copy the new EXE + all .rpt files FLAT into
  the same IIS folder first (no Report subfolder on the server side -
  url is always BaseUrl + filename), then run:
  .\generate_manifest.ps1 -ExePath "C:\inetpub\wwwroot\updates\SSCOCENTRAL.exe" -ReportFolder "C:\inetpub\wwwroot\updates" -ManifestPath "C:\inetpub\wwwroot\updates\manifest.json" -BaseUrl "https://updates.yourcompany.com"

.EXAMPLE
  OneDrive/Google Drive - urls must be pasted in by hand afterward:
  .\generate_manifest.ps1 -ExePath "C:\Build\SSCOCENTRAL.exe" -ReportFolder "C:\Build\Report" -ManifestPath ".\manifest.json"
#>
param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $true)][string]$ReportFolder,
    [string]$ManifestPath = ".\manifest.json",
    [string]$BaseUrl = ""
)

if ($BaseUrl) { $BaseUrl = $BaseUrl.TrimEnd('/') }

function Get-Md5Hex($path) {
    (Get-FileHash -Path $path -Algorithm MD5).Hash.ToLower()
}

$existing = @{}
if (Test-Path $ManifestPath) {
    $json = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    foreach ($f in $json.files) {
        $existing[$f.name] = $f.url
    }
}

$files = New-Object System.Collections.Generic.List[object]

# EXE
if (-not (Test-Path $ExePath)) { throw "EXE not found: $ExePath" }
$exeName = Split-Path $ExePath -Leaf
$files.Add([ordered]@{
    name     = $exeName
    type     = "EXE"
    checksum = Get-Md5Hex $ExePath
    size     = (Get-Item $ExePath).Length
    url      = if ($BaseUrl) { "$BaseUrl/$exeName" } elseif ($existing.ContainsKey($exeName)) { $existing[$exeName] } else { "" }
})

# Reports
if (-not (Test-Path $ReportFolder)) { throw "Report folder not found: $ReportFolder" }
Get-ChildItem -Path $ReportFolder -Filter *.rpt -File | ForEach-Object {
    $files.Add([ordered]@{
        name     = $_.Name
        type     = "RPT"
        checksum = Get-Md5Hex $_.FullName
        size     = $_.Length
        url      = if ($BaseUrl) { "$BaseUrl/$($_.Name)" } elseif ($existing.ContainsKey($_.Name)) { $existing[$_.Name] } else { "" }
    })
}

$manifest = [ordered]@{ files = $files }
$manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $ManifestPath -Encoding utf8

$missingUrls = $files | Where-Object { [string]::IsNullOrWhiteSpace($_.url) }
Write-Host "Wrote $ManifestPath with $($files.Count) file(s)."
if ($missingUrls) {
    Write-Host ""
    Write-Host "These files have NO download url yet - upload them to OneDrive/Google Drive," -ForegroundColor Yellow
    Write-Host "get the direct-download link, and paste it into manifest.json before publishing:" -ForegroundColor Yellow
    $missingUrls | ForEach-Object { Write-Host "  - $($_.name)" -ForegroundColor Yellow }
}
