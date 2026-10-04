<div align="center">

<img src="docs/images/icon.png" width="128" alt="Numo 图标">

# Numo

**macOS 上的记事本式计算器。** 像写笔记一样逐行输入算式，结果实时显示在右侧。

[English](README.md) | 简体中文

[![Build](https://github.com/imelonkid/numo/actions/workflows/build.yml/badge.svg)](https://github.com/imelonkid/numo/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/imelonkid/numo?include_prereleases&sort=semver)](https://github.com/imelonkid/numo/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-black.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)

<img src="docs/images/light.png" width="49%" alt="Numo 浅色模式"> <img src="docs/images/dark.png" width="49%" alt="Numo 深色模式">

</div>

## ✨ 特性

- **实时出结果**：不用按「=」也不用回车，边输入边计算。
- **精确的十进制**：`0.1 + 0.2` 就是 `0.3`，没有浮点误差。
- **货币换算**：`100$ to ¥`、`50 eur in usd`、`100美元换成人民币`，汇率自动更新，离线时使用缓存。
- **自然的百分比**：`20% of 150`、`200 + 10%`、`50 / 200 to %`。
- **变量、上一行与合计**：给中间结果起名字，用 `prev` 引用上一行，用 `合计` / `sum` 对一个块求和。
- **数学函数**：`√`、`∛`、`sin 30°`、`log`、`ln`、`abs`、`round`、`5!`、`π`、`e`……
- **纯文本笔记**：每个笔记都是一个 `.txt` 文件，以标签页打开；自动保存、打开最近使用、重新命名、复原，都是熟悉的 macOS 文档操作。
- **原生、克制**：AppKit 原生实现，毛玻璃背景，浅色 / 深色 / 跟随系统，配色克制；`⌥Space` 随时呼出。

## 📦 安装

1. 从 [**Releases**](https://github.com/imelonkid/numo/releases) 下载最新的 `Numo-x.y.z.dmg`。
2. 打开 DMG，把 **Numo** 拖进「应用程序」。
3. Numo 暂未经过 Apple 公证，第一次打开会被系统拦截。可以在 **系统设置 → 隐私与安全性** 中点「仍要打开」，或者运行：

   ```bash
   xattr -dr com.apple.quarantine /Applications/Numo.app
   ```

需要 macOS 14 Sonoma 及以上版本（支持 Apple 芯片和 Intel）。

## 🚀 语法

| 类别 | 示例 |
|---|---|
| 基础运算 | `1 + 2 × 3`、`(1 + 2) × 3`、`2 ^ 10`、`17 mod 5`、`5!`、`2(3 + 4)`、`1,000,000 ÷ 4`、`1.5e3` |
| 根号、常量与函数 | `√16`、`∛27`、`2π`、`sin 30°`、`cos(π / 3)`、`log 1000`、`ln e`、`log2 1024`、`abs(−8)`、`round 3.6` |
| 百分比 | `20% of 150`、`200 + 10%`、`200 − 25%`、`50 / 200 to %` |
| 货币换算 | `100$ to ¥`、`100 usd in eur`、`1$ = ¥`、`100美元换成人民币`、`50€ + 20$`、`1000 jpy to ¥` |
| 变量 | `单价 = 299 × 0.85`、`单价 × 3`、`prev − 10%` |
| 进制与格式 | `0xFF + 0b1010`、`255 in hex`、`10 to bin`、`1234567 to sci` |
| 标签与合计 | `房租 3000¥`、`餐饮 200$`，再写 `合计` / `sum` / `total`（对上方直到空行为止的内容求和） |
| 注释 | `# 标题`、`1 + 1 // 备注` |

- `to`、`in`、`=`、`→` 都表示换算。`¥` 表示人民币，日元请写 `jpy` 或 `日元`。
- 输入的 `*`、`-` 会显示为 `×`、`−`；全角输入（`１＋１`）也能识别。
- 普通数字默认最多显示 4 位小数（可在设置中调整），货币按币种的位数显示。
- 完整的语法参考已内置在 App 里：**帮助 → 语法速查**（`⌘?`）。

## ⌨️ 快捷键

| 快捷键 | 功能 |
|---|---|
| `⌥ Space` | 在任何地方呼出 / 隐藏 Numo |
| `⌘N` / `⌘O` | 新建笔记（标签页）/ 打开笔记 |
| `⌘S` / `⇧⌘S` | 保存 / 另存为 |
| 单击结果后 `⌘C` | 拷贝结果（纯数字，不带千分位和货币符号） |
| `⇧⌘C` | 拷贝光标所在行的结果 |
| `⌘R` | 立即更新汇率 |
| `⌘,` | 设置 |
| `⌘?` | 语法速查 |

## ⚙️ 设置

<img src="docs/images/settings.png" width="420" alt="设置窗口" align="right">

**外观**：跟随系统 / 浅色 / 深色、毛玻璃、字号、行距、结果颜色、小数位数、高亮当前行。

**通用**：默认保存位置、启动时打开上次的笔记、汇率状态。

<br clear="right">

## 🛠 从源码构建

只需要 Swift 6 工具链，装 Xcode 或 Command Line Tools 都可以。

```bash
git clone https://github.com/imelonkid/numo.git
cd numo
scripts/test.sh          # 运行 NumoCore 测试
scripts/build-app.sh     # 构建 build/Numo.app（ad-hoc 签名）
scripts/make-dmg.sh      # 打包 build/Numo-<版本号>.dmg
open build/Numo.app
```

目录结构：

```
Sources/NumoCore/   计算引擎：词法分析 → Pratt 解析器 → 求值 → 格式化（Decimal 精度，不依赖 UI）
Sources/Numo/       AppKit 应用：编辑器与结果列、文档与标签页、设置、汇率、全局快捷键
Tests/              NumoCore 的 swift-testing 测试
scripts/            构建、测试、图标与 DMG 打包脚本
```

更多开发细节见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。每次推送到 `main`，[GitHub Actions](https://github.com/imelonkid/numo/actions) 都会构建一个 DMG；推送 `v*` 标签时会自动发布到 Releases。

## 🗺 路线图

- [ ] 物理单位（`5 km to mi`、`1 GB in MB`）
- [ ] 日期与时间计算（`今天 + 30 天`）
- [ ] 菜单栏模式、可自定义的全局快捷键
- [ ] 代码签名与 Apple 公证

## 🤝 参与贡献

欢迎提交 Issue 和 Pull Request。提交前请运行 `scripts/test.sh`；新增语法请在 `Tests/NumoCoreTests` 中补充测试。

## 📄 开源协议

[MIT](LICENSE) © melonkid

## 🙏 致谢

灵感来自 [Numi](https://numi.app) 和 [Soulver](https://soulver.app)。汇率数据来自 [ExchangeRate-API](https://www.exchangerate-api.com)（open.er-api.com）。
