#!/usr/bin/env python3
"""
复现 docs/design.md 里的碰撞率数据。

背景：RIME 的四码上屏只对 table 类型候选生效（见 docs/design.md 第一节）。
如果做「无前缀五笔拼音混输」并让五笔优先，那么一个拼音词只要前 4 个字母
恰好是合法五笔码，输入到第 4 个字母时就会被五笔候选顶字上屏。

这个脚本量化「恰好」的概率。

用法：
    python3 tools/collision_check.py
    python3 tools/collision_check.py --rime-dir ~/Library/Rime
"""

import argparse
import pathlib
import sys

WUBI_DICT = "wubi86_jidian.dict.yaml"
PINYIN_DICT = "pinyin_simp.dict.yaml"
CODE_LEN = 4  # speller/max_code_length


def load_wubi_codes(path, code_len):
    """收集长度恰为 code_len 的五笔编码集合。"""
    codes = set()
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2 and len(parts[1]) == code_len and parts[1].isalpha():
                codes.add(parts[1])
    return codes


def load_pinyin_words(path, min_len):
    """取多音节拼音词，按权重降序返回 (权重, 词, 连写拼音)。"""
    words = []
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3 or " " not in parts[1]:
                continue  # 只要多音节词
            try:
                weight = float(parts[2])
            except ValueError:
                continue
            code = parts[1].replace(" ", "")
            if len(code) >= min_len:
                words.append((weight, parts[0], code))
    words.sort(reverse=True)
    return words


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--rime-dir",
        default=str(pathlib.Path(__file__).resolve().parent.parent / "rime"),
        help="词库所在目录，默认用仓库里的 rime/",
    )
    ap.add_argument("--code-len", type=int, default=CODE_LEN)
    args = ap.parse_args()

    base = pathlib.Path(args.rime_dir).expanduser()
    wubi_path, pinyin_path = base / WUBI_DICT, base / PINYIN_DICT
    for p in (wubi_path, pinyin_path):
        if not p.exists():
            sys.exit(f"找不到 {p}")

    n = args.code_len
    codes = load_wubi_codes(wubi_path, n)
    space = 25 ** n  # 五笔用 a-y 共 25 键，不含 z
    print(f"五笔 {n} 码总数: {len(codes)}"
          f"（{n} 码空间 25^{n} = {space}，覆盖率 {len(codes) / space * 100:.1f}%）\n")

    words = load_pinyin_words(pinyin_path, n + 1)
    for topn in (1000, 5000, 20000):
        sample = words[:topn]
        if not sample:
            continue
        hits = [w for w in sample if w[2][:n] in codes]
        print(f"高频前 {topn:>5} 个拼音词: 前 {n} 字母撞五笔码 "
              f"{len(hits):>4} 个 ({len(hits) / len(sample) * 100:.1f}%)")

    print(f"\n撞码示例（这些词打到第 {n} 个字母会被五笔顶上屏）：")
    shown = 0
    for _, word, code in words[:20000]:
        if code[:n] in codes:
            print(f"  {word}({code}) 撞 -> {code[:n]}")
            shown += 1
            if shown >= 20:
                break


if __name__ == "__main__":
    main()
