<#
.SYNOPSIS
    Stages, commits, and pushes whatever changes exist in a git repo.

.DESCRIPTION
    Convenience script for the AFRO-Dash workflow: shows you what changed,
    asks for a commit message (or accepts one as a parameter), commits,
    and pushes to the given branch. Safe by default -- it always shows you
    the changed files and asks for confirmation before staging anything,
    and it does nothing (no empty commit) if there are no changes.

.PARAMETER Path
    Path to the git repository. Defaults to the AFRO-Dash repo.

.PARAMETER Message
    Commit message. If omitted, you'll be prompted for one interactively.

.PARAMETER Branch
    Branch to push to. Defaults to "main".

.PARAMETER Force
    Skip the confirmation prompt and commit/push immediately.

.EXAMPLE
    .\git-commit-push.ps1
    Runs interactively against the default AFRO-Dash repo path.

.EXAMPLE
    .\git-commit-push.ps1 -Message "Fix district performance filter" -Force
    Commits and pushes immediately with the given message, no prompts.

.EXAMPLE
    .\git-commit-push.ps1 -Path "C:\path\to\other-repo" -Branch "dev"
    Runs against a different repo/branch.
#>

param(
    [string]$Path = "C:\Users\TOURE\Documents\Gith_repositories\AFRO-Dash",
    [string]$Message = "",
    [string]$Branch = "main",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Fail($msg) {
    Write-Host $msg -ForegroundColor Red
    exit 1
}

# --- Move into the repo ---
if (-not (Test-Path $Path)) {
    Fail "Path not found: $Path"
}
Set-Location $Path

if (-not (Test-Path ".git")) {
    Fail "Not a git repository: $Path"
}

Write-Host "Repository: $Path" -ForegroundColor Cyan
Write-Host "Branch:     $Branch" -ForegroundColor Cyan
Write-Host ""

# --- Show current state ---
$status = git status --short
if (-not $status) {
    Write-Host "No changes to commit. Working tree is clean." -ForegroundColor Yellow
    exit 0
}

Write-Host "Changes detected:" -ForegroundColor Cyan
git status --short
Write-Host ""

# --- Confirm before staging (unless -Force) ---
if (-not $Force) {
    $confirm = Read-Host "Stage, commit, and push all of the above? (y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Aborted -- nothing was staged, committed, or pushed." -ForegroundColor Yellow
        exit 0
    }
}

# --- Determine commit message ---
if (-not $Message) {
    $Message = Read-Host "Commit message (leave blank for an auto-generated one)"
}
if (-not $Message) {
    $Message = "Update $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
}

# --- Stage ---
Write-Host ""
Write-Host "Staging changes..." -ForegroundColor Cyan
git add -A
if ($LASTEXITCODE -ne 0) { Fail "git add failed." }

# --- Commit ---
Write-Host "Committing..." -ForegroundColor Cyan
git commit -m "$Message"
if ($LASTEXITCODE -ne 0) { Fail "git commit failed." }

# --- Push ---
Write-Host "Pushing to origin/$Branch..." -ForegroundColor Cyan
git push origin $Branch
if ($LASTEXITCODE -ne 0) { Fail "git push failed. Your commit was created locally but NOT pushed -- resolve the error above, then run: git push origin $Branch" }

Write-Host ""
Write-Host "Done. Changes committed and pushed to origin/$Branch." -ForegroundColor Green
