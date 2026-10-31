#!/usr/bin/env python3
"""MikuFocus 背景图库预处理工具。

把原始图库（默认 ``E:/xiazasi/miku``）按 M500 的 **1280x720 横屏**归一化，
产出可直接打进 APK 的 ``assets/backgrounds/*.webp`` 与 ``manifest.json``，
并把登记表写进 ``docs/10-背景图库登记表.md`` 的生成区。

## 适配规则（与 App 端 lib/core/background/bg_fit.dart 严格同源）

设备物理分辨率 1280x720（屏幕比例 16/9），但**分类阈值是 1.3**
（2026-10-01 用户调参，原用屏幕比例 16/9）。对一张 ``w x h`` 的图：

- **规则 1** ``w/h >= 1.3``：归规则 1 池，按高缩放到 1080。
  其中 ``>= 16/9`` 的那部分真正「高度刚好铺满、固定不动」；
  ``1.3 ~ 16/9`` 的部分因屏幕更宽，cover 只能按宽铺满，纵向溢出 28~265px。
- **规则 2** ``w/h < 1.3``：归规则 2 池，按宽缩放到 1280，
  此时高度 > 1280/1.3 ≈ 985 溢出屏幕 → App 端背景**顶置并随内容滚动**。

对照值用整数交叉相乘判定（``w * RULE_RATIO_DEN >= h * RULE_RATIO_NUM``，
即 ``w * 10 >= h * 13``），避免 ``1300/1000`` 这类正好等于 1.3 的浮点比较抖动。

## 处理方案

| 规则 | 目标 | 缩放基准 | 上采样 | 说明 |
| --- | --- | --- | --- | --- |
| 1 | 高 1080 | 按高 | 不放大 | 渲染时只用到 720 高，留 1.5x 余量给抗锯齿与未来屏 |
| 2 | 宽 1280 | 按宽 | 不放大 | 渲染时 1:1 落屏（宽度方向不缩放），最清晰 |

两规则都再受 ``MAX_EDGE`` 约束（超长图按长边回落），保证单张解码内存可控。
统一编码 WebP（Android 原生格式，体积约为 JPEG 的 70%），质量 82。

用法::

    python tool/miku_bg_prepare.py                 # 用默认源目录
    python tool/miku_bg_prepare.py --src 某目录
    python tool/miku_bg_prepare.py --check         # 只登记不重编码
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone, timedelta

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("需要 Pillow：pip install Pillow")

# ---------------------------------------------------------------- 常量

SCREEN_W = 1280
SCREEN_H = 720
SCREEN_RATIO = SCREEN_W / SCREEN_H  # 16/9 = 1.777…（渲染几何仍以它为准）

# 分类阈值（2026-10-01 用户调参：1.3，原为屏幕比例 16/9）。
# 以 13/10 存储，判定用整数交叉相乘，与 Dart 侧 kBgRuleRatioNum/Den 同源。
RULE_RATIO_NUM = 13
RULE_RATIO_DEN = 10
RULE_RATIO = RULE_RATIO_NUM / RULE_RATIO_DEN  # 1.3

RULE1_TARGET_H = 1080  # 规则 1 目标高度（渲染只用到 720）
RULE2_TARGET_W = 1280  # 规则 2 目标宽度（= 屏幕宽，1:1 落屏）
MAX_EDGE = 4096  # 单边长上限（解码内存护栏）
WEBP_QUALITY = 82
WEBP_METHOD = 6  # 0=最快 6=最慢最优

# 分类：几何分类直接决定适配规则与观感，不含语义分类（无法可靠自动判定）
CATEGORY_A = "A-规则1·宽（≥1.3）"
CATEGORY_B = "B-横构图（1:1 ~ 1.3）"
CATEGORY_C = "C-竖构图（< 1:1）"

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SRC = r"E:\xiazasi\miku"
OUT_DIR = os.path.join(PROJECT_ROOT, "assets", "backgrounds")
MANIFEST_PATH = os.path.join(OUT_DIR, "manifest.json")
DOC_PATH = os.path.join(PROJECT_ROOT, "docs", "10-背景图库登记表.md")

GEN_BEGIN = "<!-- BEGIN:GENERATED -->"
GEN_END = "<!-- END:GENERATED -->"

CST = timezone(timedelta(hours=8))

# 原名 → 稳定 slug（ASCII，便于跨平台与文件名安全）
_SLUG_RULES = (
    (re.compile(r"^link\s*\((\d+)\)\s*$"), lambda m: f"link{int(m.group(1)):02d}"),
    (re.compile(r"^link$"), lambda m: "link00"),
    (re.compile(r"^下载\s*\((\d+)\)\s*$"), lambda m: f"dl{int(m.group(1)):02d}"),
    (re.compile(r"^下载$"), lambda m: "dl00"),
    (re.compile(r"^图片清晰化与格式转换\s*\((\d+)\)\s*$"),
     lambda m: f"conv{int(m.group(1)):02d}"),
    (re.compile(r"^图片清晰化与格式转换$"), lambda m: "conv00"),
)


def slugify(stem: str) -> str:
    """原名去扩展名 → 稳定短 slug；未命中的规则回退到 md5 前缀。"""
    for pattern, build in _SLUG_RULES:
        m = pattern.match(stem.strip())
        if m:
            return build(m)
    ascii_part = re.sub(r"[^A-Za-z0-9_-]", "", stem)[:16]
    digest = hashlib.md5(stem.encode("utf-8")).hexdigest()[:6]
    return f"{ascii_part or 'img'}_{digest}"


# ---------------------------------------------------------------- 规则


def decide_rule(w: int, h: int) -> int:
    """规则 1 = 比例 >= 1.3（高铺满）；规则 2 = 比例 < 1.3（宽铺满/可滚动）。"""
    return 1 if w * RULE_RATIO_DEN >= h * RULE_RATIO_NUM else 2


def category_of(w: int, h: int) -> str:
    if w * RULE_RATIO_DEN >= h * RULE_RATIO_NUM:
        return CATEGORY_A
    if w >= h:
        return CATEGORY_B
    return CATEGORY_C


def target_size(w: int, h: int, rule: int) -> tuple[int, int]:
    """按规则算输出尺寸；只缩不放（源比目标小则保持原尺寸）。"""
    if rule == 1:
        scale = RULE1_TARGET_H / h
        if scale > 1:
            scale = 1.0
    else:
        scale = RULE2_TARGET_W / w
        if scale > 1:
            scale = 1.0
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    longest = max(nw, nh)
    if longest > MAX_EDGE:  # 超长图按长边回落
        back = MAX_EDGE / longest
        nw, nh = max(1, round(nw * back)), max(1, round(nh * back))
    return nw, nh


# ---------------------------------------------------------------- 主流程


def flatten(img: Image.Image) -> tuple[Image.Image, bool]:
    """把带透明通道的图压到**黑底**（App 常驻深色主题，黑底最不显边）。

    为什么非要压平：WebP 有损不带 alpha 通道，透明区会被填成脏色；
    且与 App 内导入（Kotlin `BackgroundImportPlugin.FLATTEN_COLOR`）必须同色，
    否则同一张图随包预处理与 app 内导入会长得不一样。

    返回 (RGB 图, 是否原本含透明)。
    """
    had_alpha = img.mode in ("RGBA", "LA") or (
        img.mode == "P" and "transparency" in img.info
    )
    img = img.convert("RGBA")
    alpha_min, _ = img.getchannel("A").getextrema()
    if alpha_min == 255:
        return img.convert("RGB"), had_alpha
    canvas = Image.new("RGB", img.size, (0, 0, 0))
    canvas.paste(img, mask=img.getchannel("A"))
    return canvas, had_alpha


def collect(src_dir: str) -> tuple[list[dict], list[dict]]:
    """遍历源目录，去重后按规则产出登记行。"""
    rows: list[dict] = []
    dups: list[dict] = []
    seen: dict[str, str] = {}
    names = sorted(
        n for n in os.listdir(src_dir)
        if os.path.isfile(os.path.join(src_dir, n))
        and os.path.splitext(n)[1].lower() in (".jpg", ".jpeg", ".png", ".webp", ".bmp")
    )
    for name in names:
        path = os.path.join(src_dir, name)
        digest = hashlib.md5(open(path, "rb").read()).hexdigest()
        if digest in seen:
            dups.append({"source": name, "duplicateOf": seen[digest]})
            continue
        seen[digest] = name

        with Image.open(path) as im:
            w, h = im.size
            mode = im.mode
        rule = decide_rule(w, h)
        nw, nh = target_size(w, h, rule)
        rows.append({
            "id": f"bg_{slugify(os.path.splitext(name)[0])}",
            "source": name,
            "srcWidth": w,
            "srcHeight": h,
            "srcBytes": os.path.getsize(path),
            "srcMode": mode,
            "rule": rule,
            "category": category_of(w, h),
            "width": nw,
            "height": nh,
            "hadAlpha": False,  # 处理时回填
            "bytes": 0,  # 处理时回填
        })
    return rows, dups


def process(src_dir: str, rows: list[dict], check_only: bool) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for row in rows:
        out = os.path.join(OUT_DIR, row["id"] + ".webp")
        if check_only and os.path.exists(out):
            row["bytes"] = os.path.getsize(out)
            continue
        with Image.open(os.path.join(src_dir, row["source"])) as im:
            flat, had_alpha = flatten(im)
            row["hadAlpha"] = had_alpha
            if flat.size != (row["width"], row["height"]):
                flat = flat.resize((row["width"], row["height"]), Image.LANCZOS)
            flat.save(out, "WEBP", quality=WEBP_QUALITY, method=WEBP_METHOD)
        row["bytes"] = os.path.getsize(out)
        print(f"  {row['id']:<14} {row['srcWidth']}x{row['srcHeight']}"
              f" -> {row['width']}x{row['height']}"
              f"  {row['bytes'] / 1024:.0f}KB  [规则{row['rule']}]")


def write_manifest(rows: list[dict], dups: list[dict], src_dir: str) -> None:
    payload = {
        "schema": "aiclock.bg_library/1",
        "generatedAt": datetime.now(CST).isoformat(timespec="seconds"),
        "sourceDir": src_dir,
        "screen": {"width": SCREEN_W, "height": SCREEN_H, "ratio": SCREEN_RATIO},
        "policy": {
            "ruleRatio": RULE_RATIO,
            "rule1": (
                f"比例 >= {RULE_RATIO}：归规则 1 池，按高缩放到 "
                f"{RULE_RATIO_NUM}/{RULE_RATIO_DEN} 判定"
            ),
            "rule2": f"比例 <  {RULE_RATIO}：归规则 2 池，按宽缩放到 {RULE2_TARGET_W}",
            "rule1TargetHeight": RULE1_TARGET_H,
            "rule2TargetWidth": RULE2_TARGET_W,
            "format": "webp",
            "quality": WEBP_QUALITY,
        },
        "count": len(rows),
        "duplicates": dups,
        "images": [
            {
                "id": r["id"],
                "asset": f"assets/backgrounds/{r['id']}.webp",
                "source": r["source"],
                "width": r["width"],
                "height": r["height"],
                "srcWidth": r["srcWidth"],
                "srcHeight": r["srcHeight"],
                "rule": r["rule"],
                "category": r["category"],
                "bytes": r["bytes"],
            }
            for r in rows
        ],
    }
    with open(MANIFEST_PATH, "w", encoding="utf-8", newline="\n") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")


def md_table(rows: list[dict], dups: list[dict]) -> str:
    total_src = sum(r["srcBytes"] for r in rows)
    total_out = sum(r["bytes"] for r in rows)
    by_rule = {1: 0, 2: 0}
    for r in rows:
        by_rule[r["rule"]] += 1

    lines = [f"> 生成时间：{datetime.now(CST).isoformat(timespec='seconds')}", ""]
    lines.append(f"共 **{len(rows)}** 张（去重后；另有 {len(dups)} 张完全重复已剔除）"
                 f"，源 {total_src / 1024 / 1024:.1f} MB → 输出 "
                 f"**{total_out / 1024 / 1024:.2f} MB**（压缩到 "
                 f"{total_out / total_src * 100:.1f}%）。"
                 f"规则 1：{by_rule[1]} 张；规则 2：{by_rule[2]} 张。")
    lines.append("")
    lines.append("| # | 输出文件 | 原文件名 | 原始分辨率 | 原始比例 | 适配规则 | 分类 | 处理方案 | 输出分辨率 | 输出体积 |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for i, r in enumerate(rows, 1):
        ratio = r["srcWidth"] / r["srcHeight"]
        if r["rule"] == 1:
            plan = f"按高缩放到 {RULE1_TARGET_H}（不放大）"
            rule_text = "**1** 高铺满·背景固定"
        else:
            plan = f"按宽缩放到 {RULE2_TARGET_W}（不放大）"
            rule_text = "**2** 宽铺满·随滚动"
        if (r["width"], r["height"]) == (r["srcWidth"], r["srcHeight"]):
            plan += "，已 ≥ 目标故原尺寸"
        if r["hadAlpha"]:
            plan += "，透明压白底"
        lines.append(
            f"| {i} | `{r['id']}.webp` | {r['source']} | "
            f"{r['srcWidth']}×{r['srcHeight']} | {ratio:.4f} | {rule_text} | "
            f"{r['category']} | {plan} | {r['width']}×{r['height']} | "
            f"{r['bytes'] / 1024:.0f} KB |"
        )
    if dups:
        lines.append("")
        lines.append("**已剔除的重复文件**：" +
                     "、".join(f"`{d['source']}`（同 `{d['duplicateOf']}`）" for d in dups))
    return "\n".join(lines)


def inject_doc(generated: str) -> None:
    if not os.path.exists(DOC_PATH):
        print(f"  ! 文档骨架不存在，跳过注入：{DOC_PATH}")
        return
    with open(DOC_PATH, encoding="utf-8") as f:
        text = f.read()
    if GEN_BEGIN not in text or GEN_END not in text:
        print(f"  ! 文档缺少生成区标记，跳过注入：{DOC_PATH}")
        return
    head, rest = text.split(GEN_BEGIN, 1)
    _, tail = rest.split(GEN_END, 1)
    with open(DOC_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"{head}{GEN_BEGIN}\n{generated}\n{GEN_END}{tail}")


def main() -> None:
    ap = argparse.ArgumentParser(description="MikuFocus 背景图库预处理")
    ap.add_argument("--src", default=DEFAULT_SRC, help="原始图库目录")
    ap.add_argument("--check", action="store_true",
                    help="只重新登记（复用已存在的输出文件，不重编码）")
    args = ap.parse_args()

    if not os.path.isdir(args.src):
        sys.exit(f"源目录不存在：{args.src}")

    print(
        f"屏幕 {SCREEN_W}x{SCREEN_H}（比值 {SCREEN_RATIO:.6f}）"
        f"　分类阈值 {RULE_RATIO}（{RULE_RATIO_NUM}/{RULE_RATIO_DEN}）"
    )
    print(f"源目录 {args.src}")
    rows, dups = collect(args.src)
    print(f"唯一图片 {len(rows)} 张，重复剔除 {len(dups)} 张")
    process(args.src, rows, args.check)
    rows.sort(key=lambda r: (r["rule"], -r["srcWidth"] * r["srcHeight"]))
    write_manifest(rows, dups, args.src)
    inject_doc(md_table(rows, dups))
    print(f"\n输出目录 {OUT_DIR}")
    print(f"清单 {MANIFEST_PATH}")
    print(f"登记表已更新 {DOC_PATH}")


if __name__ == "__main__":
    main()
