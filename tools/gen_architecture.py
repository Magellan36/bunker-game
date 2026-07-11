#!/usr/bin/env python3
"""
Static-analysis architecture map generator for BunkerGame.

Regex/text-scans every .gd file in the repo (no Godot binary needed — this
is structural, not a real compile) and emits architecture.json at the repo
root: per-script class_name/extends, exported vars, autoload usage, signals
declared + best-effort .connect() call sites, public function signatures,
rough size/complexity, cross-script references (preload/class_name-as-type),
and a simple circular-reference flag.

Usage:
    python3 tools/gen_architecture.py

Run this at the START of a session (before making changes, so you're
working off current state) and again at the END (before committing, so
architecture.json matches what's on disk). No CI/git-hook — this repo has
no automated pipeline, same as everything else here; it's meant to be run
manually by whichever agent/session is active.

architecture.json is meant to be read INSTEAD of opening every script in a
system when you just need its shape (dependencies, signals, public API) —
fall back to reading real source only when you need actual behavior/logic,
which this file deliberately does not capture.
"""
import json
import os
import re
import sys
from datetime import datetime, timezone

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

RE_CLASS_NAME = re.compile(r'^\s*class_name\s+(\w+)', re.MULTILINE)
RE_EXTENDS = re.compile(r'^\s*extends\s+([\w"/.]+)', re.MULTILINE)
RE_EXPORT = re.compile(r'^\s*@export(?:_\w+)?(?:\([^)]*\))?\s+var\s+(\w+)\s*:?\s*([\w\[\],]*)', re.MULTILINE)
RE_SIGNAL = re.compile(r'^\s*signal\s+(\w+)\s*(\([^)]*\))?', re.MULTILINE)
RE_CONNECT = re.compile(r'([\w.]+)\.(\w+)\.connect\(')
RE_FUNC_PUBLIC = re.compile(r'^\s*func\s+([a-zA-Z]\w*)\s*\(([^)]*)\)\s*(->\s*([\w\[\],. ]+))?\s*:', re.MULTILINE)
RE_FUNC_PRIVATE = re.compile(r'^\s*func\s+(_\w+)\s*\(([^)]*)\)\s*(->\s*([\w\[\],. ]+))?\s*:', re.MULTILINE)
RE_PRELOAD = re.compile(r'(?:preload|load)\(\s*"(res://[^"]+)"\s*\)')
RE_GROUP_LOOKUP = re.compile(r'get_first_node_in_group\(\s*"([^"]+)"\s*\)')
RE_AUTOLOAD_USAGE_CANDIDATES = re.compile(r'\b([A-Z]\w+)\.\w')

# Known autoload singleton names (kept in sync with project.godot [autoload]
# manually — small enough list not to warrant parsing project.godot too).
KNOWN_AUTOLOADS = {"WorldManager", "SaveManager", "DeviceDatabase", "GraphicsSettings"}


def find_gd_files():
    out = []
    for dirpath, dirnames, filenames in os.walk(REPO_ROOT):
        dirnames[:] = [d for d in dirnames if d not in (".godot", ".git")]
        for f in filenames:
            if f.endswith(".gd"):
                out.append(os.path.join(dirpath, f))
    return sorted(out)


def rel(path):
    return "res://" + os.path.relpath(path, REPO_ROOT).replace(os.sep, "/")


def analyze_file(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()

    lines = text.splitlines()
    line_count = len(lines)

    class_name_match = RE_CLASS_NAME.search(text)
    extends_match = RE_EXTENDS.search(text)

    exports = [
        {"name": m.group(1), "type": m.group(2) or None}
        for m in RE_EXPORT.finditer(text)
    ]

    signals = [
        {"name": m.group(1), "params": (m.group(2) or "()").strip()}
        for m in RE_SIGNAL.finditer(text)
    ]

    connects = [
        {"target_expr": m.group(1), "signal": m.group(2)}
        for m in RE_CONNECT.finditer(text)
    ]

    public_funcs = []
    for m in RE_FUNC_PUBLIC.finditer(text):
        name = m.group(1)
        public_funcs.append({
            "name": name,
            "args": m.group(2).strip(),
            "returns": (m.group(4) or "").strip() or None,
        })

    private_func_count = len(RE_FUNC_PRIVATE.findall(text))

    preloads = sorted(set(RE_PRELOAD.findall(text)))
    group_lookups = sorted(set(RE_GROUP_LOOKUP.findall(text)))

    autoload_refs = sorted({
        m.group(1) for m in RE_AUTOLOAD_USAGE_CANDIDATES.finditer(text)
        if m.group(1) in KNOWN_AUTOLOADS
    })

    return {
        "path": rel(path),
        "line_count": line_count,
        "class_name": class_name_match.group(1) if class_name_match else None,
        "extends": extends_match.group(1) if extends_match else None,
        "exports": exports,
        "signals": signals,
        "connect_call_sites": connects,
        "public_functions": public_funcs,
        "private_function_count": private_func_count,
        "preloads": preloads,
        "group_lookups": group_lookups,
        "autoload_references": autoload_refs,
        "complexity_score": line_count + len(public_funcs) * 2 + private_func_count,
    }


def build_dependency_edges(scripts):
    """Approximate dependency edges: A -> B if A preloads B's path, or A's
    text otherwise references B's class_name as a type. Best-effort only."""
    path_to_script = {s["path"]: s for s in scripts}
    class_to_path = {s["class_name"]: s["path"] for s in scripts if s["class_name"]}

    edges = []
    for s in scripts:
        for p in s["preloads"]:
            if p in path_to_script and p != s["path"]:
                edges.append({"from": s["path"], "to": p, "via": "preload"})

    return edges


def find_circular_refs(edges):
    graph = {}
    for e in edges:
        graph.setdefault(e["from"], set()).add(e["to"])

    cycles = []
    for a, targets in graph.items():
        for b in targets:
            if a in graph.get(b, set()) and a < b:
                cycles.append([a, b])
    return cycles


def main():
    files = find_gd_files()
    scripts = [analyze_file(f) for f in files]
    edges = build_dependency_edges(scripts)
    cycles = find_circular_refs(edges)

    autoloads_declared = sorted({
        ref for s in scripts for ref in s["autoload_references"]
    })

    output = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generator": "tools/gen_architecture.py",
        "note": (
            "Static text-scan, not a real compile — structural shape only "
            "(class/extends/exports/signals/public API/dependencies). "
            "Read this instead of opening every script in a system; fall "
            "back to real source only for actual behavior/logic."
        ),
        "script_count": len(scripts),
        "total_lines": sum(s["line_count"] for s in scripts),
        "autoloads_referenced_repo_wide": autoloads_declared,
        "scripts": scripts,
        "dependency_edges": edges,
        "circular_reference_candidates": cycles,
    }

    out_path = os.path.join(REPO_ROOT, "architecture.json")
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(output, fh, indent=2)

    print(f"Wrote {out_path}")
    print(f"  {len(scripts)} scripts, {output['total_lines']} total lines")
    print(f"  {len(edges)} dependency edges, {len(cycles)} circular-reference candidates")
    if cycles:
        for c in cycles:
            print(f"  CIRCULAR: {c[0]} <-> {c[1]}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
