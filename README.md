# rime-wubipinyin

一套 RIME 五笔86 配置：**保留四码上屏的手感，同时能用拼音救场，并且在打拼音时顺手教你五笔编码。**

基于 [KyleBing/rime-wubi86-jidian](https://github.com/KyleBing/rime-wubi86-jidian) 的极点五笔码表重构。

---

## 它解决什么问题

五笔用户常见的两个痛点：

1. **遇到不会打的字就卡住。** 加拼音混输是常规解法，但绝大多数「五笔拼音混输」方案都会悄悄牺牲掉**四码上屏**——而四码上屏恰恰是五笔手感的核心。
2. **拼音一旦能用就懒得学五笔了。** 混输方案往往变成「拼音兜底」，五笔水平原地踏步。

本配置的做法：

- 五笔和拼音**切在不同的分段里**，互不抢候选。四码上屏对五笔完整生效，对拼音完全免疫。
- 拼音候选后面标注的不是拼音，而是**这个字的五笔编码**。打 `zweixiao` 出「微笑」时，你顺手就看到了它怎么拆。
- 五笔候选也保留编码提示，配合 `enable_completion`，打一个字母就能看到一片字各自的完整编码——这是练盲打最有效的方式。

为什么不能既要四码上屏又要无前缀自由混输？这不是没做，是**数学上不可兼得**。实测每 7 个高频拼音词就有 1 个会被顶掉，详细论证和源码依据见 [docs/design.md](docs/design.md)，结论可用 [`tools/collision_check.py`](tools/collision_check.py) 复现。

---

## 特性

| | |
|---|---|
| 四码上屏 | 完整保留，`max_code_length: 4` + `auto_select` |
| 拼音辅助 | `z` 引导，零冲突（五笔86 码表不含任何 z 开头编码） |
| 边打边学 | 拼音候选标注五笔编码；五笔候选显示完整编码 |
| 简拼 | `zzg` → 中国 |
| Emoji | `zweixiao` → 😊，`Ctrl+Shift+E` 开关 |
| 简繁 | 独立的简入繁出方案 |
| 跨平台 | macOS 鼠鬚管 / Windows 小狼毫 / Linux ibus·fcitx5 |
| 中英切换 | Shift 直切，终端和 IDE 可配置为进入即英文 |

不含英文混输。原因同上：英文单词普遍超 4 个字母，与四码上屏冲突。本配置假定你用 Shift 切换。

---

## 安装

需要先装好 RIME：

- **macOS** — [鼠鬚管 Squirrel](https://rime.im/download/)，或 `brew install --cask squirrel`
- **Windows** — [小狼毫 Weasel](https://rime.im/download/)
- **Linux** — `ibus-rime` 或 `fcitx5-rime`

然后：

```bash
git clone https://github.com/gnfy/rime-wubipinyin.git
cd rime-wubipinyin
./install.sh
```

脚本会自动识别平台、备份你现有的同名配置、拷贝文件、下载 emoji 词表并触发重新部署。

常用参数：

```bash
./install.sh --dry-run     # 只看会做什么，不动文件
./install.sh --no-emoji    # 跳过 emoji（无网络环境）
./install.sh --dir <path>  # 自动识别失败时手动指定 Rime 用户目录
```

装完在输入法菜单里选方案（macOS 默认 <kbd>Ctrl</kbd>+<kbd>`</kbd>）：

- **极点五笔·拼音辅助** ← 推荐，日常用这个
- **极点五笔** ← 纯五笔，不带拼音

还原：

```bash
./uninstall.sh --list   # 看有哪些备份
./uninstall.sh          # 还原到最近一次
```

---

## 用法

### 基本

```
打 g              → 候选：一 g、地 fb、在 d …… 后面跟着各自的完整五笔编码
打满四码          → 唯一候选时自动上屏
打 zzhongguo      → 中国，候选后标注的是「中国」的五笔编码
打 zzg            → 简拼，同样出中国
打 zweixiao       → 微笑 😊
```

`z` 开头即进入拼音，候选框会显示 `〔拼音〕` 提示。五笔码里没有 z，所以永远不会误触发。

### 快捷键

| 按键 | 作用 |
|---|---|
| <kbd>Shift</kbd> | 中英切换（已输入内容上屏） |
| <kbd>;</kbd> <kbd>'</kbd> | 选第 2、3 个候选 |
| <kbd>[</kbd> <kbd>]</kbd> | 上下翻页 |
| <kbd>Tab</kbd> / <kbd>Shift</kbd>+<kbd>Tab</kbd> | 下一页 / 上一页 |
| <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>E</kbd> | Emoji 开关 |
| <kbd>Ctrl</kbd>+<kbd>0</kbd> | 方案选单 |

另外内置了一套 Emacs 风格的编辑键（<kbd>Ctrl</kbd>+<kbd>p</kbd>/<kbd>n</kbd>/<kbd>b</kbd>/<kbd>f</kbd>/<kbd>a</kbd>/<kbd>e</kbd>/<kbd>h</kbd>/<kbd>g</kbd>），见 `rime/default.custom.yaml`。

---

## 目录结构

```
rime/                              安装时整个拷进 Rime 用户目录
├── default.custom.yaml            方案列表、按键绑定、标点
├── squirrel.custom.yaml           macOS 皮肤 + 分 App 的中英文默认
├── weasel.custom.yaml             Windows 皮肤
├── wubi86_jidian_pinyin.schema.yaml   ★ 主方案：五笔 + z 拼音
├── wubi86_jidian.schema.yaml          纯五笔
├── wubi86_jidian_trad*.schema.yaml    简入繁出
├── pinyin_simp.schema.yaml            独立拼音方案
├── numbers.schema.yaml                大写数字
├── wubi86_jidian.dict.yaml            五笔主码表（分层 import）
├── wubi86_jidian_user.dict.yaml       ← 你自己的词放这里
├── wubi86_jidian_extra*.dict.yaml     扩展词库
├── pinyin_simp.dict.yaml              拼音词库
└── opencc/emoji.json                  emoji 适配（词表由 install.sh 下载）

docs/design.md                     设计取舍与源码依据
docs/hamster-ios-keyboard/         iOS 仓输入法键盘布局
tools/collision_check.py           碰撞率数据复现脚本
```

---

## 定制

### 加自己的词

编辑 `wubi86_jidian_user.dict.yaml`，格式是 `词<Tab>编码`：

```
上线	jqxt
```

`install.sh` 检测到这个文件已存在时**不会覆盖**，升级配置不会丢词。

### 加自己的 emoji

编辑 `opencc/emoji.txt`（安装后才有），格式 `词<Tab>词 emoji1 emoji2`：

```
上线	上线 🚀
```

### 换皮肤

改 `squirrel.custom.yaml` 里的 `preset_color_schemes`。注意颜色是 **BGR 倒序**，不是 RGB——`#D1635D` 要写成 `0x5D63D1`，文件开头有说明。

### 想要无前缀自由混输

可以，但要放弃四码上屏，改法见 [docs/design.md](docs/design.md) 第六节。

---

## 已知限制

- **四码及以上的词打不出 emoji。** 打满 4 码就自动上屏了，emoji 候选来不及选。能选到 emoji 的只有简码字（如 `o` → 火 🔥），共 136 个。日常用 `z` 拼音打 emoji。
- **没有英文混输、没有自动造词。** 都与四码上屏冲突，属于有意取舍。
- **拼音要多按一个 `z`。** 这是保住四码上屏的代价，理由见设计文档。

---

## 致谢

- **王永民先生** — 五笔字形输入法发明人
- **[KyleBing/rime-wubi86-jidian](https://github.com/KyleBing/rime-wubi86-jidian)** — 极点五笔码表与基础方案（Apache-2.0）
- **[Mintimate/oh-my-rime](https://github.com/Mintimate/oh-my-rime)** — emoji 词表与工程化思路（GPL-3.0，安装时下载，不随本仓库分发）
- **[RIME / 中州韻輸入法引擎](https://rime.im)** — 输入法引擎

---

## 许可证

[Apache License 2.0](LICENSE)。第三方组件的来源与许可见 [NOTICE](NOTICE)。

安装脚本下载的 `emoji.txt` 来自 oh-my-rime，受 **GPL-3.0** 约束，不包含在本仓库中。不需要可用 `./install.sh --no-emoji` 跳过。
