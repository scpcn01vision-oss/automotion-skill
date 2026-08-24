param(
    [string]$ToolRoot = $(if ($env:V7_TOOL_DIR) { $env:V7_TOOL_DIR } else { Join-Path $env:USERPROFILE ".automotion" }),
    [string]$RepoUrl = "https://github.com/scpcn01vision-oss/automotion.git",
    [string]$Branch = "fix/toolchain-issues-1-5"
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

function Assert-Cmd([string]$name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Host "[FAIL] 缺少 $name，请先安装（可让 Codex 引导安装）后重试。" -ForegroundColor Red
        exit 1
    }
}

function Require-Path([string]$label, [string]$path) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "[FAIL] 自检未通过：缺少 $label（$path）" -ForegroundColor Red
        exit 1
    }
}

Write-Step "检查运行环境（git / node / npm / python / pip）..."
Assert-Cmd "git"
Assert-Cmd "node"
Assert-Cmd "npm"
Assert-Cmd "python"
Assert-Cmd "pip"

Write-Step "工具仓库目录: $ToolRoot（目标分支: $Branch）"
if (Test-Path (Join-Path $ToolRoot ".git")) {
    Write-Step "已存在，fetch + 切到目标分支 $Branch 并更新..."
    git -C $ToolRoot fetch origin
    if ($LASTEXITCODE -ne 0) { throw "git fetch 失败" }
    git -C $ToolRoot checkout -B $Branch origin/$Branch
    if ($LASTEXITCODE -ne 0) { throw "git checkout $Branch 失败" }
    git -C $ToolRoot pull --ff-only origin $Branch
    if ($LASTEXITCODE -ne 0) { throw "git pull 失败" }
}
else {
    if (Test-Path $ToolRoot) {
        Write-Host "[FAIL] $ToolRoot 已存在但不是 git 仓库，请手动处理该目录。" -ForegroundColor Red
        exit 1
    }
    Write-Step "clone 工具仓库（分支 $Branch）..."
    git clone -b $Branch $RepoUrl $ToolRoot
    if ($LASTEXITCODE -ne 0) { throw "git clone 失败" }
}

Write-Step "npm install（工作台与整片合成依赖）..."
Push-Location $ToolRoot
try {
    npm install
    if ($LASTEXITCODE -ne 0) { throw "npm install 失败" }
}
finally { Pop-Location }

Write-Step "pip install openai-whisper jieba opencc-python-reimplemented（转录依赖）..."
python -m pip install openai-whisper jieba opencc-python-reimplemented
if ($LASTEXITCODE -ne 0) { throw "pip install 失败" }

Write-Step "工具链自检（lenses / registry / generate_cues / whole.tsx / npm / pip）..."
Require-Path "lenses/ 目录" (Join-Path $ToolRoot "lenses")
Require-Path "镜头 registry" (Join-Path $ToolRoot "shared/registry.json")
Require-Path "锚点生成脚本 generate_cues.py" (Join-Path $ToolRoot "scripts/generate_cues.py")
Require-Path "整片入口 templates/whole.tsx" (Join-Path $ToolRoot "templates/whole.tsx")
Assert-Cmd "npm"
Assert-Cmd "pip"

Write-Host ""
Write-Host "[OK] automotion 工具链安装完成：$ToolRoot（分支 $Branch）" -ForegroundColor Green
Write-Host "使用：设置 V7_PROJECT_DIR 指向项目目录后按 SKILL.md 走流程；已有 whisper 模型时转录会直接复用。"
