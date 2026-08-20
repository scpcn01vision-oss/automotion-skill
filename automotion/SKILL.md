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
2. clone 工具仓库到 `~/.automotion/`（已存在则 `git pull` 更新）
3. `npm install`（工作台与整片合成依赖）
4. `pip install openai-whisper jieba opencc-python-reimplemented`（转录依赖；whisper 首次运行还会自动下载模型）

工具根目录默认 `~/.automotion/`，可用环境变量 `V7_TOOL_DIR` 覆盖（已有本地工具仓库时）。工具链就绪后，为项目建数据目录，记作 `V7_PROJECT_DIR`（环境变量，启动派生/转录/工作台/整片时都要设）。目录初始只需：

- 原始文案（用户稿件）
- 录音 `full.wav`

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

2. AI 为每段补 `summary`（摘要）、`role`（角色牌）、`features`（内容牌）——匹配与工作台左栏依赖这些字段。

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

产出：`transcript.json`（词级）、`subtitles.json`（字幕条）、`storyboard.json`（durationSec 真实化）。

- 字幕切分规则见 [字幕切分规范-M5.md](references/字幕切分规范-M5.md)（语义优先、单条 ≤18 汉字、停顿驱动）
- 段真实时长 = 段内字幕时间跨度（首条开始 → 末条结束）

### Step 3 匹配 Top5（自动，AI 语义对齐）

按 [匹配机制-M3.md](references/匹配机制-M3.md) 执行：

1. 为每段写一句「核心含义」（AI 语义理解，不做关键词机械匹配）
2. 与镜头定位库（`docs/lens-scenes-draft.md`，工具仓库内）的使用场景描述语义对齐
3. 段 role/features 命中镜头场景标签 → 排序靠前（标签是排序信号，不是排除）
4. 防重复：同一镜头间隔 <5 段排除；≥5 段允许复用
5. 输出每段 Top5 候选 + reason，全部展示不折叠

产出物是 MatchResult JSON（结构见工具仓库 `shared/types.ts`：`meta + segments[{id, core, top5:[{lensId, reason}]}]`），写到 `out/match-<项目>.json`。工作台默认读 `out/match-<项目名>.json`（按项目目录名自动推导，通常无需设置）。

- 无准入/无排除/无禁入：任何镜头都可被匹配
- 驳回反馈：镜头被否 → 修该镜头的定位描述/标签，不建黑名单

### Step 4 工作台定稿（人工 + 对话）

设置 `V7_PROJECT_DIR` 后启动工作台（工具仓库）：

```bash
npm run dev
```

浏览器 5173 打开。按 [工作台需求-M4.md](references/工作台需求-M4.md) 操作：

- 左栏段列表 / 中栏镜头预览 + 参数表单 / 右栏 Top5 推荐 + 镜头库（hover 预览）
- **保存式交互**：镜头调整、字幕样式各有「保存」按钮，保存一次写回一次文件
- 进入下一步由用户与 skill 对话决定（如用户说「去预览」）；预览发现问题随时回工作台改、再保存
- 复杂参数调整可回 Codex 对话，用提示词改 storyboard
- 已知问题：部分使用 `public/textures/` 静态图的镜头（如 PageWaterfallWall）在预览窗可能报图片解码失败（EncodingError），属工作台已知问题，不影响其他镜头与保存流程；控制台出现的 Remotion license 提示可忽略

生成镜头参数时读 [自动填参-映射规律-M4.md](references/自动填参-映射规律-M4.md)；镜头参数结构规范见 [参数化设计规范.md](references/参数化设计规范.md)；镜头时间策略（弹刚/口播锚点/固定帧）见 [镜头时间策略声明规范.md](references/镜头时间策略声明规范.md)。

### Step 5 整片合成与导出（自动）

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
- 帧边界逐段 round（`startFrame = round(cumSec×30)`），禁止累计 cursor += round（会漂移）
- `<Audio>` 必须放视频组件内部（不能放 Composition children），src 用 http 地址（server 音频路由）
- 渲染后**必须做响度检测**（ffmpeg volumedetect），口播 mean ≈ -20dB；-91dB 是静音轨道不算有声音

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
