# 设计取舍

这份文档记录本配置为什么长成现在这样。如果你想改，先读这里，能省掉很多试错。

结论先行：**「四码上屏」「五笔候选优先」「无前缀五笔拼音自由混输」三者在 RIME 里数学上不可兼得，必须放弃一个。** 本配置选择放弃第三个，用 `z` 引导拼音。

---

## 一、四码上屏的触发机制

先看 librime 的源码（`src/rime/gear/speller.cc`，以 1.16.0 为准）：

```cpp
ProcessResult Speller::ProcessKeyEvent(const KeyEvent& key_event) {
  ...
  // handles input beyond max_code_length when auto_select is false.
  if (is_initial && AutoSelectAtMaxCodeLength(ctx)) { ... }
```

```cpp
bool Speller::AutoSelectAtMaxCodeLength(Context* ctx) {
  if (max_code_length_ <= 0) return false;
  if (!ctx->HasMenu()) return false;
  auto cand = ctx->GetSelectedCandidate();
  if (cand && reached_max_code_length(cand, max_code_length_) &&
      is_auto_selectable(cand, ctx->input(), delimiters_)) {
    ctx->ConfirmCurrentSelection();
    return true;
  }
  return false;
}
```

关键在 `is_auto_selectable()`：

```cpp
static bool is_auto_selectable(const an<Candidate>& cand,
                               const string& input,
                               const string& delimiters) {
  return
      cand->end() == input.length() &&                    // 候选覆盖到输入末尾
      (is_table_entry(cand) || is_simple_candidate(cand)) &&
      input.find_first_of(delimiters, cand->start()) == string::npos;
}

static inline bool is_table_entry(const an<Candidate>& cand) {
  const auto& type = Candidate::GetGenuineCandidate(cand)->type();
  return type == "table" || type == "user_table";
}
```

**四码上屏只对 `table` / `user_table` 类型的候选生效。** 注意 `AutoSelectAtMaxCodeLength` 并不检查 `auto_select_`，所以哪怕只设了 `max_code_length` 也会顶字上屏。

各翻译器产出的候选类型：

| 翻译器 | 候选 type | 会被四码上屏顶掉 |
|---|---|---|
| `table_translator` | `table` / `user_table` / `sentence` / `completion` | **会** |
| `script_translator` | `phrase` / `user_phrase` / `completion` | 不会 |
| `reverse_lookup_translator` | 继承 `TableTranslation` → `table` | **会** |

---

## 二、于是冲突就出现了

如果做「无前缀自由混输」并让五笔优先，那么输入第 4 个字母时排在首位的必然是五笔的 `table` 候选，于是 `AutoSelectAtMaxCodeLength` 触发，**正在输入的拼音被拦腰截断**。

这不是理论风险。用本仓库自带的两个词库实测：

```
五笔 4 码总数: 71824（4 码空间 25^4 = 390625，覆盖率 18.4%）

高频前  1000 个拼音词: 前 4 字母撞五笔码  147 个 (14.7%)
高频前  5000 个拼音词: 前 4 字母撞五笔码  701 个 (14.0%)
高频前 20000 个拼音词: 前 4 字母撞五笔码 2615 个 (13.1%)
```

撞的还全是最高频的词：

```
不是(bushi) → bush      问题(wenti)  → went     但是(danshi) → dans
如果(ruguo) → rugu      觉得(juede)  → jued     北京(beijing)→ beij
上海(shanghai)→ shan    电话(dianhua)→ dian     网站(wangzhan)→ wang
用户(yonghu)→ yong      通过(tongguo)→ tong     数据(shuju)  → shuj
```

**每 7 个拼音词就有 1 个会在第 4 个字母被顶掉。** 这个概率没法用。

复现脚本见 [`tools/collision_check.py`](../tools/collision_check.py)。

---

## 三、解法：`z` 引导拼音

为什么是 `z`：

```
$ awk -F'\t' 'NF>=2 && $2 ~ /^z/' wubi86_jidian.dict.yaml | head
(空)
```

**五笔86 码表里没有任何以 z 开头的编码**（`wubi86_jidian.dict.yaml` 的 `encoder/exclude_patterns` 也写死了 `^z.*$`）。z 在五笔里是保留键，所以拿它当拼音引导键零冲突。

配置上用 `affix_segmentor` 把拼音切成独立分段：

```yaml
segmentors:
  - affix_segmentor@pinyin_hint
translators:
  - table_translator                # 五笔
  - script_translator@pinyin_hint   # 拼音
recognizer:
  patterns:
    pinyin_hint: "^z[a-z]*'?$"      # 必需，见下
```

`affix_segmentor` 会把前缀切成一个带 `phony` 标签的独立分段（不上屏），剩下的编码单独成段：

```cpp
// affix_segmentor.cc
prefix_segment.tags.insert("phony");  // do not commit raw input
...
Segment code_segment(j, k);
code_segment.tags.insert(tag_);
```

注意它开头有一道门槛：

```cpp
if (!segmentation->back().HasTag(tag_)) { ... return true; }
```

**分段必须先带上目标标签，`affix_segmentor` 才会去剥前缀**——所以 `recognizer/patterns` 里那条规则不是可选项，删了整个拼音功能就废了。

这样一来：

- 五笔和拼音在**不同分段**里，根本不在同一个候选列表竞争，「五笔优先」自动成立，比调 `initial_quality` 权重更彻底
- 拼音候选是 `script_translator` 产出的 `phrase` 类型，`is_auto_selectable()` 不认，**四码上屏永远不会误伤拼音**

拼音翻译器特意用 `script_translator` 而非 `reverse_lookup_translator`，就是因为后者继承 `TableTranslation`、产出 `table` 类型，会重新掉进同一个坑。

---

## 四、边打拼音边学五笔

用 `reverse_lookup_filter` 给拼音候选标注该字的五笔编码：

```yaml
filters:
  - reverse_lookup_filter@wubi_code_hint

wubi_code_hint:
  tags: [ pinyin_hint ]        # 只作用于拼音分段
  dictionary: wubi86_jidian
  overwrite_comment: true
```

`tags` 能用是因为这个 filter 继承了 `TagMatching`：

```cpp
// reverse_lookup_filter.h
class ReverseLookupFilter : public Filter, TagMatching {
  virtual bool AppliesToSegment(Segment* segment) { return TagsMatch(segment); }
```

于是打 `zweixiao` 出「微笑」时，候选后面显示的是它的五笔编码而不是拼音——不会打的字用拼音打出来，顺手就把五笔码记住了。

另外，纯五笔方案里 `translator/comment_format` **不要**写 `xform/.+//`。上游默认带这一行，它会把候选后面的编码提示全部抹掉，配合 `enable_completion: true` 本来是最有效的盲打练习方式。

---

## 五、Emoji 与四码上屏的相互作用

emoji 通过 `simplifier` 挂在候选文字上，所以理论上五笔拼音都能触发。但实际上：

```
能出 emoji 的字词共 2089 个
其中五笔码短于 4 码的只有 136 个（6.5%）
```

**其余 93.5% 打满 4 码就被顶字上屏了，emoji 候选来不及选。** 能选到的只有简码字：

```
火 → o    日 → j    口 → k    山 → m    牙 → ah
```

所以 emoji 的正确用法是走 `z` 拼音：`zweixiao` → 微笑 😊。拼音分段不受四码上屏影响。

好消息是 emoji 数据缺失时不会出问题：

```cpp
// simplifier.cc
an<Translation> Simplifier::Apply(...) {
  if (!engine_->context()->get_option(option_name_)) return translation;
  if (!opencc_) return translation;      // 数据没加载成功 → 静默跳过
```

所以 `install.sh --no-emoji`，或者下载失败，输入法都照常工作。

---

## 六、如果你想要无前缀自由混输

也可以，代价是放弃四码上屏。改 `wubi86_jidian_pinyin.schema.yaml`：

```yaml
speller:
  alphabet: abcdefghijklmnopqrstuvwxyz
  # max_code_length: 4        ← 注释掉这两行
  # auto_select: true
```

然后把拼音从 `affix_segmentor` 换成与五笔同段（去掉 prefix，让两个 translator 共用 `abc` 标签），用 `initial_quality` 控制五笔优先。此时改用空格上屏。

注意上游 oh-my-rime 也走了类似的取舍——它为了兼容英文混输，在 `speller` 里把 `max_code_length` 和 `auto_select` 整段注释掉了，并注明「为了兼容 英文混输，取消自动上屏」。

---

## 七、为什么没有英文混输

同一个原因。英文单词普遍超过 4 个字母，一开四码上屏，打 `hello` 到第 4 码就被顶上屏了。本配置假定你用 Shift 切换中英（`default.custom.yaml` 里 `Shift_L/Shift_R: commit_code`），把四码上屏的手感完整留给五笔。

想要英文混输，参考 oh-my-rime 的 `melt_eng` 方案，并同步关掉四码上屏。
