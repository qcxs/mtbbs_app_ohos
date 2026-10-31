# MT 论坛 — Flutter 客户端

> **鸿蒙独立版**：本仓库基于 [qcxs/mtbbs_app](https://github.com/qcxs/mtbbs_app) 的 `lib/`，
> 只面向 HarmonyOS（Flutter-OH）；仓库内不含 Android / Windows 等其它平台工程。
> 鸿蒙专属的 Dart 逻辑写在 `lib/ohos/`（上游永不存在该目录，合并零冲突）。
> 快速开始见 [docs/ohos/02-从零部署指南.md](docs/ohos/02-从零部署指南.md)；
> 与上游同步见 [docs/ohos/03-同步上游.md](docs/ohos/03-同步上游.md)。

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

基于 Flutter 的 Discuz 论坛客户端，适配 **MT 论坛**（[bbs.binmt.cc](https://bbs.binmt.cc)）克米模板。

> 本项目使用 **GNU General Public License v3.0** 开源。  
> 允许自由使用、修改和分发，但**必须**：
> - 注明原作者及原始仓库
> - 修改后的版本也必须以 GPLv3 发布
> - 提供源代码

---

## 已实现功能

| 功能 | 说明 |
|------|------|
| **导读** | 最新/热门/精华/新帖列表 |
| **版块** | 版块分类浏览 + 帖子列表 |
| **帖子详情** | BBCode 渲染、评论、点赞、收藏、评分 |
| **帖子缓存** | 自动缓存新帖（只存已加载评论页，保留最近 3 个正文版本，默认 1 天）；离线副本永不过期；独立管理页支持按帖删除、导入/导出明文 JSON；损坏时禁用并引导备份/重建 |
| **生成图片** | 一键生成分享图：楼层/评论 = 可选评分/截断/二维码的浅色卡片；个人主页 = **整页内容原样** + 站点/用户/二维码水印（存相册，不可用时回退另存为） |
| **编辑器** | 发帖/评论/回复/编辑，BBCode 工具栏，图片管理，MT 图床，粘贴图片上传，快照自动保存 |
| **社区** | 版块帖子列表（路由 `/forum`，带 fid 时显示对应版块帖子） |
| **圈子** | Discuz 群组只读浏览（列表/分类/内容讨论区，入口在「我的」页） |
| **用户空间** | 个人资料、签名 |
| **多站点** | 多站点多账号切换 |
| **设置** | 自定义工具栏、快捷键、颜色主题、BBCode 渲染等 |
| **内置浏览器** | WebView 浏览 |
| **站内搜索** | 原生结果页（`search.php`，随浏览模式适配克米/标准模板） |
| **RSS** | 帖子列表 RSS |
| **排行榜** | 用户排行（美女/帅哥/积分/好友数/邀请/发帖数/在线时间，路由 `/ranklist`） |

## 运行环境

| 工具 | 版本 |
|------|------|
| Flutter-OH SDK | `oh-3.44.9-dev`（Dart 3.12.2，见 `docs/ohos/01-环境与构建.md`） |
| DevEco Studio | 26.0 + HarmonyOS SDK API 26 |
| 产物 | `build/ohos/hap/entry-default-{signed,unsigned}.hap` |

```bash
# 检查代码
flutter analyze lib/

# 测试 API（真实请求探针，docs/10-API探针使用规范.md）
flutter test tool/api_probe_test.dart --dart-define=cmd=help
```

## 本地打包（HAP）

环境搭建、依赖适配、签名与已知坑见 [docs/ohos/01-环境与构建.md](docs/ohos/01-环境与构建.md)。

```powershell
# 依赖解析（pubspec.yaml 的 dependency_overrides 段常驻生效）
& $flutter pub get

# 出包：模拟器用 x64，真机用 arm64；侧载分发加 --no-codesign
# 接续（应用流转）由 Dart 插件 packages/mtbbs_ohos_bridge 自动注册，不需要 --target
& $flutter build hap --debug   --target-platform ohos-x64
& $flutter build hap --release --target-platform ohos-arm64 --no-codesign

# 调试运行（可选）
& $flutter devices
& $flutter run -d <device-id>
```

---

## Fork 与自建教程

如果你想基于此项目适配**你自己的 Discuz 论坛**，Fork 后按以下注意事项配置。

### 1. Fork 仓库

在 GitHub 上点击右上角 **Fork**，将仓库克隆到你的账号下。

```bash
git clone https://github.com/你的用户名/mtbbs_app.git
cd mtbbs_app
```

### 2. 遵守许可证（必须）

本项目为 **GPLv3**，Fork/修改/分发必须：

- 保留代码顶部版权声明与 `LICENSE` 文件（GPLv3 全文）
- 修改后的版本同样以 GPLv3 发布，并提供源代码
- 在 README 或 About 中注明原作者及原始仓库

建议在 README 中添加：

```markdown
> 本分支源自 [qcxs/mtbbs_app](https://github.com/qcxs/mtbbs_app)，基于 GPLv3 许可。
```

### 3. 配置站点信息

修改 `lib/config/site_config.dart`，将预置站点替换为你的论坛地址：

```dart
// 将默认站点改为你的论坛
SiteConfig.sites[0] = SiteInfo(
  name: '我的论坛',
  host: 'your-forum.com',
  ...
);
```

> 本项目针对 MT 论坛的克米模板适配。不同 Discuz 模板/版本的页面结构可能有差异，若解析异常，参考 `docs/03-UA与解析策略.md` 调整。

### 4. 修改鸿蒙应用标识（推荐）

`ohos/AppScope/app.json5` 中的 `bundleName` 是原作者的包名——**Fork 后务必改成你自己的**（如 `com.yourname.discuz`），否则与原版应用冲突：同一设备无法同时安装，也无法覆盖升级。

## 文档

> AI 改代码前必读：见仓库根目录 [AGENTS.md](AGENTS.md)（铁律 + 任务→文档路由表）。
> 只想"了解项目"：按 AGENTS.md 的「了解项目」三步读 `01 + 02 + 07`。

```
docs/
├── 00-文档编写规范.md      文档怎么写：结构 / 写法 / 篇幅 / 索引
├── 01-概述与架构.md        项目架构与分层设计
├── 02-开发规范.md          API 流程、文件规范、UI 约束
├── 03-UA与解析策略.md      UA 与 Discuz 解析策略
├── 04-状态管理.md          状态管理、站点切换、持久化策略
├── 05-快捷键与撤销.md      快捷键系统与编辑器撤销机制
├── 06-编辑器.md            编辑器模式、快照、图床、粘贴
├── 07-经验教训.md          踩坑记录与最佳实践（必读）
├── 08-主题与夜间模式.md    颜色规范与深色主题适配指南
├── 09-依赖清单.md          依赖速查、行为关键点与大忌
├── 10-API探针使用规范.md   探针命令/参数/踩坑
├── 11-新增功能开发流程.md  AI 冷启动手册（新增列表/详情类功能）
├── 12-写操作API文档.md     发帖/评论/回复/修改
├── 13-修改API文档.md       帖子/评论修改
├── 14-新增删除收藏功能文档.md  写功能实战参考
├── 16-应用图标.md          图标设计规范与各尺寸重出流程
├── 17-MCP服务端.md         MCP 只读服务端：分层、安全模型、能力清单、关键决策
├── 18-站内搜索.md           search.php 原生搜索：请求流程、两套模板解析、翻页、探针
├── 19-圈子.md               圈子（Discuz 群组）只读：UA 决策、三层复用、路由映射
├── 20-人机验证与站点防护.md 阿里云 ESA 挑战：机制、两级恢复、自解约束、交互式预案
├── 21-留言板.md             用户留言板（do=wall）：写操作协议、受限渲染、权限、页面
├── 22-生成图片.md           分享图：两条实现路子、复用的公共件、接入步骤、坑索引
├── 23-可选能力与平台降级.md 可选插件/能力注册表、适配器边界、ACW 双路径、鸿蒙仓库边界
├── 24-帖子缓存与离线帖子.md 帖子缓存：独立 threads.sembast、快照 v1 冻结、自动/离线、损坏恢复
├── 25-帖子缓存导出格式与自解析指南.md  导出 JSON 字段、版本/哈希算法、网页与脚本解析示例
├── 26-通用组件与复用清单.md 弹层/列表/状态/页面块/解析样板：先查再写，避免重复实现
├── 27-跨站点会话与多用户.md 身份作用域（SiteSession/SiteScope）、site 参数、默认用户、跨站只读
├── ohos/                   鸿蒙构建与同步上游
│   ├── 01-环境与构建.md       环境 / 依赖适配 / 签名 / 已知坑
│   ├── 02-从零部署指南.md     从零搭建鸿蒙构建环境
│   ├── 03-同步上游.md         与主线 mtbbs 合并更新
│   ├── 04-AI同步提示词.md     AI 执行同步的提示词
│   └── 05-应用流转可行性调研.md 应用接续（Continuity）可行性、代码落点
├── lessons/                经验教训正文（按主题分册；docs/07 是编号索引）
│   ├── 解析与渲染.md          解析与渲染（含三层测试诊断法）
│   ├── 编辑器.md              编辑器
│   ├── 状态与UI架构.md        状态与 UI 架构（设置页/首页信息架构）
│   ├── 图片与网络.md          图片与网络
│   ├── 写操作-搜索-消息.md    写操作 / 搜索 / 消息
│   └── 通用.md                通用（插件/窗口/链接/Cookie/弹层约定）
└── notes/                  临时笔记（不进正式索引）
    └── 精华与帖子标记.md
```

文档聚焦"为什么这样做"，代码细节让 AI 读源码（写作约定见 `docs/00-文档编写规范.md`）。

## 技术栈

| 工具 | 用途 |
|------|------|
| Flutter + Dart | 跨平台 UI |
| Dio | HTTP 客户端 + Cookie 持久化 |
| Provider | 状态管理 |
| GoRouter | 路由 |
| cached_network_image | 图片缓存 |
| photo_view | 图片查看器 |
| flutter_inappwebview | WebView（登录 + 内置浏览器） |
| url_launcher | 外部浏览器打开链接 |
| html | HTML/XML DOM 解析 |

## 核心目录

```
lib/
├── api/            Discuz HTML/XML → JSON 适配器
├── auth/           登录认证与多账号管理
├── config/         站点/导航/工具栏配置
├── controllers/    控制器（如线程列表 controller）
├── core/           BBCode 解析、日志、快捷键等基础工具（parser/utils/app）
├── mcp/            只读 MCP 服务端（本机 Streamable HTTP，AI 客户端直连）
├── models/         纯数据模型
├── pages/          页面组件
│   ├── browser/    内置浏览器
│   ├── community/  社区（版块帖子列表）
│   ├── editor/     编辑器（发帖/评论/回复）
│   ├── group/      圈子（Discuz 群组，只读）
│   ├── guide/      导读
│   ├── home/       首页
│   ├── settings/   设置页及子页面
│   ├── thread/     帖子详情
│   ├── user/       用户主页
│   └── …           其余功能页（消息/搜索/排行/分享/收藏/关注/在线/小黑屋等）
├── providers/      全局状态
├── services/       Dio、MT 图床、剪贴板粘贴等服务
└── widgets/        通用组件
```

## 致谢

- [**PiliPlus**](https://github.com/bggRGjQaUbCoE/PiliPlus)：开源的 B 站客户端标杆，本项目的版本管理与打包流程参考了其成熟实践
- **DeepSeek API**：量大管饱的推理能力，支撑了本项目大量的开发、调试与文档工作
- **Trae**：可视化编辑器，降低了 Flutter 开发的上手门槛，适合小白快速构建应用
