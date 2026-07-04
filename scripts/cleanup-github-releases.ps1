# 列出并删除 GitHub Release（含无 tag 孤儿、草稿；Releases 页可能看不到）
# 用法：
#   gh auth login
#   .\scripts\cleanup-github-releases.ps1 -KeepTag v2026-07-04-moses
#   .\scripts\cleanup-github-releases.ps1 -ListOnly   # 只查看，不删除

param(
    [string]$Repo = "keller-cc/ihope",
    [string]$KeepTag = "",
    [switch]$ListOnly
)

$ErrorActionPreference = "Stop"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "Install GitHub CLI: winget install GitHub.cli"
}

gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Run: gh auth login"
}

# 完整 API 列表（含 draft、tag_name 为空的孤儿 Release；gh release list 会漏掉后者）
$releases = gh api "repos/$Repo/releases?per_page=100" | ConvertFrom-Json

if (-not $releases -or $releases.Count -eq 0) {
    Write-Host "No releases found."
    exit 0
}

Write-Host "All releases ($($releases.Count)):"
foreach ($r in $releases) {
    $tag = if ($r.tag_name) { $r.tag_name } else { "(no tag / orphan)" }
    $flags = @()
    if ($r.draft) { $flags += "draft" }
    if ($r.prerelease) { $flags += "prerelease" }
    $flagStr = if ($flags.Count) { " [$($flags -join ', ')]" } else { "" }
    Write-Host "  id=$($r.id) tag=$tag name=$($r.name)$flagStr"
}

if ($ListOnly) { exit 0 }

foreach ($r in $releases) {
    if ($KeepTag -and $r.tag_name -eq $KeepTag) {
        Write-Host "Keeping $($r.tag_name) (id=$($r.id))"
        continue
    }
    Write-Host "Deleting release id=$($r.id) tag=$($r.tag_name) name=$($r.name)..."
    gh api -X DELETE "repos/$Repo/releases/$($r.id)"
}

Write-Host "`nRemaining:"
gh api "repos/$Repo/releases?per_page=100" -q '.[] | {id, tag: .tag_name, name, draft}' 
