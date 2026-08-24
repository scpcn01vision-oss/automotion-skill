---
name: automotion
version: 0.1.0
description: 通用的口播视频成片自动化（automotion 工具链封装）。把用户提供的「文案 + 录音」自动做成完整口播视频：分割定稿 → 派生 → 转录 → 匹配 Top5 → 工作台定稿 → 整片合成 → 导出 mp4（1920×1080@30、带字幕与口播、无 BGM）。触发场景：用户说「做视频」「口播视频」「自动成片」「automotion」；或提供视频文稿/文案 + 录音并要生成完整视频。
---

# automotion

自动化口播视频成片：文案 + 录音 → 成片。人工触点只有三个：**分割版审核**、**工作台定稿**、**整片验收**。

## 用户可见性

用户只接触三样东西：

1. **分割版**（Step 0.5 人工审核定稿）
2. **工作台 UI**（Step 4 分镜与字幕定稿）
3. **整片预览/成片**（Step 5 验收）

`storyboard.json` / `transcript.json` / `subtitles.json` / `match-<项目>.json` 都是系统内部数据（机器格式），用户无需阅读，也不要求手工准备——它们由定稿分割版派生（Step 1）。

## 依赖（工具仓库）

本 skill 是 automotion 工具链的使用说明。工具本体（122 镜头库、工作台、合成组件、转录脚本）在独立仓库 [automotion](https://github.com/scpcn01vision-oss/automotion)（v7 为内部迭代代号，对外统称 automotion）。以下命令均在工具根目录执行。

**首次使用自动安装（用户无需手动操作）**：本 skill 第一次被触发时，自动运行 `scripts/setup-toolchain.ps1` 完成：

1. 检查 git / Node.js / Python 是否就绪，缺失时引导安装
2. clone（或已存在则 fetch + 切到目标分支 `fix/toolchain-issues-1-5`）工具仓库到 `~/.automotion/`
3. `npm install`（工作台与整片合成依赖）
4. `pip install openai-whisper jieba opencc-python-reimplemented`（转录依赖；whisper 首次运行还会自动下载模型）
5. 自检：确认 `lenses/`、`shared/registry.json`、`scripts/generate_cues.py`、`templates/whole.tsx` 就位，且 npm / pip 可用

工具根目录默认 `~/.automotion/`，可用环境变量 `V7_TOOL_DIR` 覆盖（已有本地工具仓库时）。工具链就绪后，为项目建数据目录，记作 `V7_PROJECT_DIR`（环境变量，启动派生/转录/工作台/整片时都要设）。目录初始只需：

- 原始文案（用户稿件）
- 录音 `full.wav`
- 图片素材目录 `pic/`（image 类镜头标准目录，初始化时一并创建）

项目数据只在项目侧流转，不进工具仓库、不进 git。

## 全流程

### Step 0 初始化：文案 → 分割版（AI）

**输入**：原始文案 + `full.wav`

**处理**：AI 把文案按语义单元分割成段，产出分割版 md（`## 段 N` + 段文本）——这是唯一给人看的中间产物，命名如 `<文案名>-分割版.md`。

**输出**：分割版 md。

### Step 0.5 人工审核：分割版定稿（人工）

用户检查分割细度：每段是否语义完整、长短是否合适、切点是否正确；需要修改则直接改分割版文件。

**定稿前不派生任何内部文件**；转录必须等分割定稿并派生后才执行。

### Step 1 派生：定稿分割版 → storyboard.json（脚本 + AI）

1. 运行派生脚本生成骨架（段 text 就位）：

```bash
python scripts/derive-storyboard.py "<V7_PROJECT_DIR>\<文案名>-分割版.md" --project-dir "$env:V7_PROJECT_DIR"
```

2. AI 为每段补 `summary`（摘要）、`role`（角色牌）、`features`（内容牌）——匹配与工作台左栏依赖这些字段。features 判定必须按 [自动填参-映射规律-M4.md](references/自动填参-映射规律-M4.md) 的「内容牌判定规则」：**基于段文本原文特征**（含结构/动作标签），每个标签在 `featuresEvidence` 里记录原文摘录。

**输出**：`storyboard.json`（内部数据，机器格式；durationSec 待转录回填）。

### Step 2 转录、对齐与字幕（自动）

先设置项目目录（Windows PowerShell 示例）：

```powershell
$env:V7_PROJECT_DIR = "E:\路径\到\项目目录"
```

运行工具仓库的转录脚本（whisper 词级转录 → 文案对齐 → 字幕切分 → 更新段真实时长）：

```bash
python scripts/transcribe.py
```

脚本读 `V7_PROJECT_DIR` 定位项目数据（未设置时直接报错退出）。**已有 transcript.json 时加 `--skip-transcribe`**，跳过 whisper（medium 模型很慢），复用词级转录只做对齐/切分/时长更新。

产出：`transcript.json`（词级）、`subtitles.json`（字幕条）、`storyboard.json`（每段写入**绝对时间边界** `startSec`/`endSec` + `durationSec` 真实化）。

- 字幕切分规则见 [字幕切分规范-M5.md](references/字幕切分规范-M5.md)（语义优先、单条 ≤18 汉字、停顿驱动）
- 段绝对时间边界（事实，转录阶段写入 storyboard）：`startSec` = 段首条字幕开始，`endSec` = 段末条字幕结束；`durationSec = endSec - startSec`
- **时间轴上的段位置只能来自测量（绝对时间戳），禁止用 durationSec 累加推算**（见 Step 5 定位规则）
- 转录产物自带硬校验（段字幕与文案逐字一致 / 时间单调不重叠 / 无占位时间戳），校验失败即报错中断——转录通过后段归属与时间轴可信任，无需人工核对

### Step 3 匹配 Top5（自动，AI 语义对齐）

按 [匹配机制-M3.md](references/匹配机制-M3.md) 执行：

1. **先判段的结构类型**（设问-回答 / 揭穿-反转 / 对比-转折 / 列举-展开 / 因果-推论）——结构是语义对齐的第一抓手
2. 为每段写「核心含义」：必须包含**表达动作**（这段在做什么：揭穿/揭示/设问/对比/列举/推论…），不做关键词机械匹配
3. 与镜头定位库（`docs/lens-scenes-draft.md`，工具仓库内）的使用场景描述语义对齐——**以结构/动作对齐优先**，词面/意象联想为次
4. 排序：**语义对齐分 > 标签加权**；段 role/features 命中镜头标签仅作同分 tie-breaker（标签是排序信号，不是排除）
5. 防重复：同一镜头间隔 <5 段排除；≥5 段允许复用
6. 输出每段 Top5 候选 + reason——**reason 必须说明「段的什么结构 → 镜头的什么动作」**，禁止词面硬凑（如"节奏契合一秒"）

产出物是 MatchResult JSON（结构见工具仓库 `shared/types.ts`：`meta + segments[{id, core, top5:[{lensId, reason}]}]`），写到项目侧 `V7_PROJECT_DIR/out/match-<项目>.json`。工作台默认读项目侧 `out/match-<项目名>.json`（按项目目录名自动推导，通常无需设置）。

- 无准入/无排除/无禁入：任何镜头都可被匹配
- 驳回反馈：镜头被否 → 修该镜头的定位描述/标签，不建黑名单
- **镜头可用集约束（2026-08-22 教训）**：候选必须来自镜头 registry（`shared/registry.json`）。整片渲染入口按 registry 动态解析镜头组件，与工作台是同一可用集——registry 内任何镜头都能整片渲染，不存在"能预览不能渲染"。匹配/定稿无需再担心整片缺失。

### Step 3.5 AI 参数生成（必须执行）

**输入**：Step 3 的 Top1 镜头 + `storyboard.json`（各段 text/summary/role/features）+ [自动填参-映射规律-M4.md](references/自动填参-映射规律-M4.md)

**处理**：AI 为每段按自动填参规律生成 `params`，并把 `lensId` 预填为该段 Top1（建议值，非最终定稿）：

- **params 的每个值必须能从该段文案找到依据**——只填文案真实出现的内容，不发明；无依据的字段留空省略，让组件用默认值
- 类型与 `shared/registry.json` 的 props schema 对齐（number/boolean/数组不错型）
- 生成后必须过 `shared/types.ts` 的 `isStoryboard` 校验

**输出**：`storyboard.json`（每段 lensId=Top1 + 内容参数）

**时机**：匹配后、工作台定稿前，**必须执行**——否则工作台打开全是镜头默认参数（与内容无关）。工作台定稿换镜后如需内容参数，回对话按选定镜头 + 该段文案重新生成。

> **注意**：口播锚点（`cueSec`/`revealAtSec`）**不属于本步**。它依赖"已定稿的镜头 + 内容项 + 内容项对应口播哪一句"，属于**定稿后**的对齐行为；在工作台定稿前镜头未定，无法确定画面时机。锚点统一在 Step 4 定稿后生成（见 Step 4）。

### Step 4 工作台定稿（人工 + 对话）

设置 `V7_PROJECT_DIR` 后启动工作台（工具仓库）：

```bash
npm run dev
```

**为项目自动生成「启动工作台.bat」（自包含单文件一键启动工作台）**：skill 在项目目录创建/确保以下 bat（已存在则跳过、不覆盖），用户双击即可启动，无需手动设置任何环境变量：

```bat
@echo off
chcp 65001 >nul
rem 一键启动 automotion 工作台（自动定位项目数据目录与工具库）
for %%i in ("%~dp0.") do set "V7_PROJECT_DIR=%%~fi"
if defined V7_TOOL_DIR (set "TOOL_DIR=%V7_TOOL_DIR%") else (set "TOOL_DIR=%USERPROFILE%\.automotion")
pushd "%TOOL_DIR%"
call npm run dev
popd
```

- **通用性**：`V7_PROJECT_DIR` 恒为 bat 所在项目目录（`%~dp0`）；工具库用 `V7_TOOL_DIR`（已设则尊重）或默认 `%USERPROFILE%\.automotion`。所以任意项目只要设了 `V7_TOOL_DIR` 或本机有标准工具库即可一键启动，无需约定项目在工具库下的相对位置。
- **生成后验证**：见下方「启动脚本验证机制」，必须执行。

浏览器 5173 打开。按 [工作台需求-M4.md](references/工作台需求-M4.md) 操作：

- 左栏段列表 / 中栏镜头预览 + 参数表单 / 右栏 Top5 推荐 + 镜头库（hover 预览）
- 工作台展示的是 Step 3.5 预生成的建议镜头 + 参数（未定稿段自动预选 Top1 并带上预生成参数）；人工微调后点「保存」
- 换镜头时参数重置为该镜头默认值，如需内容参数可回对话按选定镜头 + 该段文案重新生成
- **保存式交互**：镜头调整、字幕样式各有「保存」按钮，保存一次写回一次文件
- 进入下一步由用户与 skill 对话决定（如用户说「去预览」）；预览发现问题随时回工作台改、再保存
- 复杂参数调整可回 Codex 对话，用提示词改 storyboard
- 已知问题：部分使用 `public/textures/` 静态图的镜头（如 PageWaterfallWall）在预览窗可能报图片解码失败（EncodingError），属工作台已知问题，不影响其他镜头与保存流程；控制台出现的 Remotion license 提示可忽略
- **定稿后做口播锚点对齐**（画面出现时机 ↔ 口播词）：`python scripts/generate_cues.py`（项目目录经 `--project-dir` 或 `V7_PROJECT_DIR`）。能自动匹配的自动生成 `cueSec`/`revealAtSec`；匹配不到（多为"提炼文本"而非原文）会列出，由 skill/AI 读该段文案与组件内容项语义补齐（可结合 `scripts/query-cues.py` 查词），补齐后**重跑一次**。注意：段起点必须用**绝对 `startSec`**（第 0 段=0），禁止用 `durationSec` 累加（丢弃段间停顿会整体偏前）。生成后跑 `python scripts/check-cues.py`（项目目录）——声明需对齐的段缺锚点即报错，输出 `[OK]` 才继续。
- **定稿完成、进入整片前跑镜头可用性闸门**：`python scripts/check-whole-lenses.py`（项目目录经 `--project-dir` 或 `V7_PROJECT_DIR` 指定）；输出 `[OK]` 才进入 Step 5，缺一段都会报错停住并列出清单。

生成镜头参数时读 [自动填参-映射规律-M4.md](references/自动填参-映射规律-M4.md)；镜头参数结构规范见 [参数化设计规范.md](references/参数化设计规范.md)；镜头时间策略（弹刚/口播锚点/固定帧）见 [镜头时间策略声明规范.md](references/镜头时间策略声明规范.md)。

### 启动脚本验证机制（skill 生成 bat 后必须执行）
1. 校验项目目录（`V7_PROJECT_DIR`）存在 `storyboard.json`、`subtitles.json`（工作台/整片预览所需文件，缺则先走 Step 1/2 派生）。
2. 校验工具库存在，且含 `package.json`、`templates/whole.tsx`、`lenses/Root.preview.tsx`（缺说明工具库未就绪/版本不符）。
3. 校验 `npm` 命令可用。
4. 整片预览再校验端口 3003 未被占用；被占用则提示先关闭占用进程或用 `--port` 换端口。
任意一项不过 → skill 立即补齐或明确提示用户，**禁止让用户双击后才报错**。

### Step 5 整片合成与导出（自动）

**为项目自动生成「Remotion预览启动.bat」（自包含单文件一键启动整片预览）**：skill 在项目目录创建/确保以下 bat（已存在则跳过），用户双击即可启动整片预览：

```bat
@echo off
chcp 65001 >nul
rem 一键启动 automotion 整片预览（工作台 + 整片 3003）
for %%i in ("%~dp0.") do set "V7_PROJECT_DIR=%%~fi"
if defined V7_TOOL_DIR (set "TOOL_DIR=%V7_TOOL_DIR%") else (set "TOOL_DIR=%USERPROFILE%\.automotion")
pushd "%TOOL_DIR%"
call npm run dev:whole
popd
```

> 整片入口 `templates/whole.tsx` 的 `project-data` 别名由 `V7_PROJECT_DIR` 指向项目目录——**不设该变量会报 `Cannot find module 'project-data/storyboard.json'`**。本 bat 已自动设好，避免此坑。生成后同样要跑「启动脚本验证机制」。

整片预览（工作台 5173 + 整片 3003）：

```bash
npm run dev:whole
```

`dev:whole` 使用通用整片入口 `templates/whole.tsx`（仓库内，所有项目复用同一份，无需按项目复制）。入口关键三点：

```ts
import storyboard from 'project-data/storyboard.json'; // project-data alias → V7_PROJECT_DIR
import subtitles from 'project-data/subtitles.json';
const AUDIO_SRC = 'http://localhost:3004/api/audio/full.wav'; // 必须 http 地址（server 音频路由）
// Composition durationInFrames = round(audioDurationSec × 30)，30fps
```

整片合成与导出严格按 [整片合成方案-M5.md](references/整片合成方案-M5.md) 的教训执行：

- **音频真实时长是 Composition 总时长唯一基准**：`durationInFrames = round(audioDurationSec × 30)`
- **段边界用绝对时间戳定位**：`startFrame = round(seg.startSec × 30)`（第一段从 0 开始，覆盖片头前导静音）。**禁止用 durationSec 累计**——累计会丢弃段间停顿与前导静音，偏差逐段累积（2026-08-22 教训：seg-04 早 ~1s、片尾早 ~5.6s，已改为绝对定位）
- `<Audio>` 必须放视频组件内部（不能放 Composition children），src 用 http 地址（server 音频路由）
- 渲染后**必须做响度检测**（ffmpeg volumedetect），口播 mean ≈ -20dB；-91dB 是静音轨道不算有声音
- **渲染浏览器（2026-08-22 修复）**：`remotion.config.ts` 优先使用本机 Chrome（可用环境变量 `CHROME_PATH` 覆盖），首次渲染不再从 Google storage 下载 headless shell，避免网络不可达时卡死。

导出用 remotion CLI（1920×1080@30，无 BGM）：

```bash
npx remotion render templates/whole.tsx Whole out/whole.mp4                          # 全片
npx remotion render templates/whole.tsx Whole out/check.mp4 --frames=0-299           # 小范围验证
```

- Studio（`dev:whole`）占着 3003 时，渲染命令要换端口：`--port=3005`
- 响度检测：`ffmpeg -i out/whole.mp4 -af volumedetect -f null NUL`（Windows；macOS/Linux 用 `/dev/null`）

## 用户交互约定

- 保存式（非向导式）：每个环节完成后询问用户，由用户决定进入下一步
- 项目数据（storyboard/转录/字幕/录音）在项目侧，不进仓库
- 整片预览验收为人工：发现问题 → 回工作台改对应镜头 → 只重渲染该镜头，其余复用缓存
- 用户可见性：分割版（审核）→ 工作台 UI（定稿）→ 整片预览（验收）；storyboard/transcript/subtitles/match 为系统内部数据
