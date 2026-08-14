<#
.SYNOPSIS
    이 PC 에서 새 버전을 배포합니다.

.DESCRIPTION
    바뀐 파일을 커밋·푸시한 뒤 GitHub Actions 의 release 워크플로를 실행합니다.
    버전 기록, 압축, 릴리스 등록은 모두 GitHub 쪽에서 처리하므로
    웹에서 [Run workflow] 를 누른 것과 결과가 완전히 같습니다.

.EXAMPLE
    .\Publish-Release.ps1 -Version 3.1.0 -Notes "채팅방 읽기 정확도 개선"
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+(\.\d+){1,3}$')]
    [string]$Version,

    [string]$Notes = '',

    [switch]$SkipCommit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $root

function Assert-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "$Name 을(를) 찾을 수 없습니다. $Hint" }
}

Assert-Command 'git' 'https://git-scm.com 에서 설치하세요.'
Assert-Command 'gh'  'https://cli.github.com 에서 설치한 뒤 gh auth login 을 실행하세요.'

Write-Host "[1/4] 스크립트 자체 점검" -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $root 'KakaoRoomScheduler.ps1') -SelfTest
if ($LASTEXITCODE -ne 0) { throw '자체 점검에 실패했습니다. 배포를 중단합니다.' }

if (-not $SkipCommit) {
    Write-Host "[2/4] 변경사항 커밋 및 푸시" -ForegroundColor Cyan
    $status = @(git status --porcelain)
    if ($status.Count -gt 0) {
        git add -A
        $message = if ($Notes) { "chore: $Notes" } else { "chore: v$Version 준비" }
        git commit -m $message
    } else {
        Write-Host "      커밋할 변경사항이 없습니다."
    }
    $branch = (git rev-parse --abbrev-ref HEAD).Trim()
    git push origin $branch
} else {
    Write-Host "[2/4] 커밋 단계를 건너뜁니다." -ForegroundColor DarkGray
}

Write-Host "[3/4] release 워크플로 실행 (v$Version)" -ForegroundColor Cyan
$arguments = @('workflow', 'run', 'release.yml', '-f', "version=$Version")
if ($Notes) { $arguments += @('-f', "notes=$Notes") }
& gh @arguments
if ($LASTEXITCODE -ne 0) { throw '워크플로 실행에 실패했습니다.' }

Write-Host "[4/4] 진행 상황" -ForegroundColor Cyan
Start-Sleep -Seconds 5
& gh run list --workflow release.yml --limit 3

$repo = (& gh repo view --json nameWithOwner --jq .nameWithOwner).Trim()
Write-Host ""
Write-Host "배포를 요청했습니다. 완료되면 아래에서 확인할 수 있습니다." -ForegroundColor Green
Write-Host "  https://github.com/$repo/actions"
Write-Host "  https://github.com/$repo/releases"
Write-Host ""
Write-Host "사용자는 프로그램의 [설정] → [업데이트 확인] 에서 새 버전을 받을 수 있습니다."
