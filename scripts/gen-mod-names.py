#!/usr/bin/env python3
"""把 assets/mod-names-zh.json 嵌入为 Swift 源文件，使启动器离线时也有中文名。"""
import json, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
data = json.loads((root / "assets/mod-names-zh.json").read_text(encoding="utf-8"))
compact = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
assert '"#' not in compact
(root / "Sources/LauncherCore/Community/ModNamesEmbedded.swift").write_text(
    "// 由 scripts/gen-mod-names.py 从 assets/mod-names-zh.json 生成，请勿手动编辑\n\n"
    "enum ModNamesEmbedded {\n"
    f"    static let json = #\"{compact}\"#\n"
    "}\n", encoding="utf-8")
print(f"已嵌入 {len(data['mods'])} 条 Mod 中文名")
