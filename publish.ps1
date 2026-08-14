# ============================================================
# YiqiChupian 客户端发布脚本
# 用途: 把 storyboard-client 打包好的安装包发布到 GitHub Releases
# 用法:
#   .\publish.ps1                          # 自动找最新安装包发布
#   .\publish.ps1 -Version 0.2.0           # 指定版本
#   .\publish.ps1 -SourceDir "D:\path\to\release"   # 指定打包目录
#   .\publish.ps1 -SkipGitPush             # 只建 Release, 不提交仓库
# ============================================================
[CmdletBinding()]
param(
    [string]$SourceDir = "D:\work\manju\storyboard-client\release",
    [string]$RepoDir   = $PSScriptRoot,
    [string]$Version,
    [switch]$SkipGitPush
)

$ErrorActionPreference = "Stop"
$GITHUB_REPO = "worldprogramer/yiqichupian"
$GITHUB_BRANCH = "main"

# ---------- 1. 检查 gh CLI ----------
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    $candidate = "C:\Users\pgj\AppData\Local\Programs\GitHubCLI\bin\gh.exe"
    if (Test-Path $candidate) { $gh = Get-Item $candidate } else {
        Write-Host "[ERROR] 未找到 gh CLI, 请先安装: winget install GitHub.cli" -ForegroundColor Red
        exit 1
    }
}
Write-Host "[1/7] gh CLI: $($gh.Source)" -ForegroundColor Cyan

# ---------- 2. 检查/登录 gh ----------
$auth = & $gh.Source auth status 2>&1 | Out-String
if ($auth -match "not logged in") {
    Write-Host "[2/7] 需要登录 GitHub, 请在浏览器中完成授权..." -ForegroundColor Yellow
    & $gh.Source auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] 登录失败" -ForegroundColor Red; exit 1 }
}
Write-Host "[2/7] GitHub 已登录" -ForegroundColor Cyan

# ---------- 3. 定位最新安装包 ----------
$exe = Get-ChildItem -Path $SourceDir -Filter "*Setup-*.exe" -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $exe) { Write-Host "[ERROR] 在 $SourceDir 没有找到 *Setup-*.exe" -ForegroundColor Red; exit 1 }

if (-not $Version) {
    if ($exe.Name -match "Setup-(\d+\.\d+\.\d+)") { $Version = $Matches[1] }
    else { $Version = Read-Host "未识别出版本号, 请输入版本号 (如 0.2.0)" }
}
$blockmap = Get-ChildItem -Path $SourceDir -Filter "$($exe.BaseName).exe.blockmap" -File |
    Select-Object -First 1
$tag = "v$Version"

Write-Host "[3/7] 安装包: $($exe.FullName) ($([math]::Round($exe.Length/1MB,1)) MB)" -ForegroundColor Cyan
Write-Host "      版本号: $Version -> Release 标签: $tag" -ForegroundColor Cyan

# ---------- 4. 拷贝安装包到仓库(仅用于上传 Release, 不进 git) ----------
$releaseDir = Join-Path $RepoDir "release"
New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
Copy-Item $exe.FullName (Join-Path $releaseDir $exe.Name) -Force
$uploadFiles = @((Join-Path $releaseDir $exe.Name))
if ($blockmap) {
    Copy-Item $blockmap.FullName (Join-Path $releaseDir $blockmap.Name) -Force
    $uploadFiles += (Join-Path $releaseDir $blockmap.Name)
    Write-Host "[4/7] 已拷贝安装包 + blockmap 到 $releaseDir" -ForegroundColor Cyan
} else {
    Write-Host "[4/7] 已拷贝安装包到 $releaseDir" -ForegroundColor Cyan
}

# 安装包超过 GitHub 100MB 单文件限制, 用 .gitignore 排除, 只上传到 Releases
$gitignore = Join-Path $RepoDir ".gitignore"
if (-not (Test-Path $gitignore)) {
    Set-Content -Path $gitignore -Value @"
# 安装包超过 GitHub 单文件 100MB 限制, 不提交 git, 只上传到 Releases
release/*.exe
release/*.exe.blockmap
publish.ps1
"@ -Encoding UTF8
}

# ---------- 5. 更新 README 下载链接 ----------
$readme = Join-Path $RepoDir "README.md"
$downloadUrl = "https://github.com/$GITHUB_REPO/releases/download/$tag/$($exe.Name)"
$readmeContent = @"
# YiqiChupian 一起出片

一起出片 桌面客户端安装包发布仓库。

## 最新版本

- 版本: **$Version**
- 标签: `$tag`
- 下载: [$($exe.Name)]($downloadUrl)

## 历史版本

可在 [Releases 页面](https://github.com/$GITHUB_REPO/releases) 查看并下载所有版本。
"@
Set-Content -Path $readme -Value $readmeContent -Encoding UTF8
Write-Host "[5/7] README.md 已更新" -ForegroundColor Cyan

# ---------- 6. 提交并推送仓库 ----------
if (-not $SkipGitPush) {
    git -C $RepoDir add -A
    git -C $RepoDir -c user.name="pgj" -c user.email="pgj@users.noreply.github.com" commit -m "chore: publish v$Version"
    git -C $RepoDir push origin $GITHUB_BRANCH
    if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] git push 失败" -ForegroundColor Red; exit 1 }
    git -C $RepoDir tag -f $tag
    git -C $RepoDir push origin $tag --force
    Write-Host "[6/7] 代码已推送到 $GITHUB_REPO" -ForegroundColor Cyan
} else {
    Write-Host "[6/7] 已跳过 git push (SkipGitPush)" -ForegroundColor Yellow
}

# ---------- 7. 创建/更新 GitHub Release 并上传安装包 ----------
$releaseExists = & $gh.Source release view $tag --repo $GITHUB_REPO 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[7/7] Release $tag 已存在, 更新安装包..." -ForegroundColor Yellow
    & $gh.Source release upload $tag --repo $GITHUB_REPO --clobber $uploadFiles
} else {
    & $gh.Source release create $tag --repo $GITHUB_REPO `
        --title "YiqiChupian v$Version" `
        --notes "一起出片 桌面客户端 v$Version`n`n安装包: $($exe.Name)" `
        $uploadFiles
}
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] Release 上传失败" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "发布完成!" -ForegroundColor Green
Write-Host "  仓库:   https://github.com/$GITHUB_REPO" -ForegroundColor Green
Write-Host "  Release: https://github.com/$GITHUB_REPO/releases/tag/$tag" -ForegroundColor Green
