# automotion

通用的口播视频成片自动化 skill（v0.1.0）：提供「文案 + 录音」，自动完成
转录分段 → 镜头匹配 → 工作台定稿 → 整片合成导出，输出
1920×1080@30 mp4（带字幕与口播、无 BGM）。

## 安装

Codex 用户：

- 用 skill-installer 安装：触发 `$skill-installer`，从 GitHub 仓库路径
  `scpcn01vision-oss/automotion-skill` 安装
- 或手动：`git clone https://github.com/scpcn01vision-oss/automotion-skill`
  到 `~/.codex/skills/automotion`

## 使用

对话中触发 `$automotion`，提供「文案 + 录音」即可。完整流程见
[SKILL.md](SKILL.md)。首次使用会自动安装工具链（clone 工具仓库到
`~/.automotion/` 并装依赖），无需手动准备环境。

## 依赖

工具本体（122 镜头库、工作台、合成组件、转录脚本）在
[automotion](https://github.com/scpcn01vision-oss/automotion) 仓库
（Apache-2.0）。

## License

Apache-2.0。skill 内容为原创说明文档；镜头代码来源与修改声明见工具仓库
automotion 的 NOTICE。
