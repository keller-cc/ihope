# 删除 GitHub 上所有 Release 与远程 tag（需 gh 已登录：gh auth login）
# 用法：.\scripts\cleanup-github-releases.ps1
# 可选：-KeepTag v2026-07-04-moses  保留指定 tag

param(
    [string]$Repo = "keller-cc/ihope",
    [string]$KeepTag = ""
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

$releases = gh release list --repo $Repo --limit 200 --json tagName,id 2>$null | ConvertFrom-Json
if ($releases) {
    foreach ($r in $releases) {
        if ($KeepTag -and $r.tagName -eq $KeepTag) { continue }
        Write-Host "Deleting release $($r.tagName)..."
        gh release delete $r.tagName --repo $Repo --yes --cleanup-tag 2>$null
        if ($LASTEXITCODE -ne 0) {
            gh release delete $r.tagName --repo $Repo --yes
        }
    }
}

$tags = gh api "repos/$Repo/tags" --paginate -q '.[].name' 2>$null
foreach ($t in $tags) {
    if ($KeepTag -and $t -eq $KeepTag) { continue }
    Write-Host "Deleting tag $t..."
    gh api -X DELETE "repos/$Repo/git/refs/tags/$t" 2>$null
}

Write-Host "Done. Remaining tags:"
gh release list --repo $Repo --limit 10
