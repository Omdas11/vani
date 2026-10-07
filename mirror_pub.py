#!/usr/bin/env python3
"""Offline pub package mirror for sandboxes where `pub get` cannot reach
pub.dev directly (proxy auth issues), but curl can.

- Resolves the dependency closure via the pub.dev API (fresh curl per call).
- Downloads each archive and extracts to .pub_pkgs/<name>-<version>/.
- Writes pubspec_overrides.yaml with path overrides so
  `flutter pub get --offline` succeeds without network.
"""
import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile

import yaml

ROOT = os.path.expanduser("~/workspace/opentune/app")
PKGDIR = os.path.expanduser("~/workspace/opentune/.pub_pkgs")
DART_VERSION = (3, 13, 5)

os.makedirs(PKGDIR, exist_ok=True)


def curl_json(url):
    out = subprocess.run(
        ["curl", "-s", "-m", "30", url], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"curl failed for {url}")
    return json.loads(out.stdout)


def curl_download(url, dest):
    r = subprocess.run(["curl", "-sL", "-m", "120", "-o", dest, url])
    if r.returncode != 0 or not os.path.exists(dest):
        raise RuntimeError(f"download failed: {url}")


def parse_version(v):
    v = v.strip().split("+")[0]
    parts = [int(p) for p in re.findall(r"\d+", v)[:3]]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts)


def satisfies(version, constraint):
    """Minimal pub constraint check: ^, >=, >, <=, <, any, exact, ranges."""
    c = (constraint or "any").strip()
    if c in ("any", ""):
        return True
    # Build metadata (+2, +hotfix) is not part of precedence: strip it so
    # constraints like ^0.3.4+2 match correctly instead of falling through
    # to "any".
    c = re.sub(r"\+[0-9A-Za-z.-]+", "", c)
    v = parse_version(version)
    # caret
    m = re.fullmatch(r"\^(\d+\.\d+\.\d+)", c)
    if m:
        base = parse_version(m.group(1))
        upper = (base[0] + 1, 0, 0) if base[0] > 0 else (
            (0, base[1] + 1, 0) if base[1] > 0 else (0, 0, base[2] + 1))
        return base <= v < upper
    # compound ranges like ">=1.0.0 <2.0.0"
    ok = True
    for part in c.split():
        m = re.fullmatch(r"(>=|>|<=|<|=)?\s*(\d+\.\d+\.\d+)", part)
        if not m:
            continue
        op, ver = m.group(1) or "=", parse_version(m.group(2))
        if op == ">=":
            ok &= v >= ver
        elif op == ">":
            ok &= v > ver
        elif op == "<=":
            ok &= v <= ver
        elif op == "<":
            ok &= v < ver
        else:
            ok &= v == ver
    return ok


def sdk_ok(pubspec):
    env = pubspec.get("environment") or {}
    sdk_c = env.get("sdk")
    if not sdk_c:
        return True
    # check lower bound only (upper bounds like <4.0.0 always hold for 3.13.5)
    lowers = re.findall(r">=\s*(\d+\.\d+\.\d+)", str(sdk_c))
    for lb in lowers:
        if DART_VERSION < parse_version(lb):
            return False
    return True


_meta_cache = {}


def pick_version(name, constraint):
    if name not in _meta_cache:
        _meta_cache[name] = curl_json(
            f"https://pub.dev/api/packages/{name}")
    versions = _meta_cache[name]["versions"]
    cands = []
    for v in versions:
        ver = v["version"]
        if not satisfies(ver, constraint):
            continue
        ps = v.get("pubspec") or {}
        if not sdk_ok(ps):
            continue
        # skip retracted / non-stable unless needed
        cands.append((parse_version(ver), ver, ps))
    if not cands:
        raise RuntimeError(f"no version of {name} satisfies {constraint}")
    cands.sort(reverse=True)
    # prefer stable over dev/preview
    for _, ver, ps in cands:
        if "-" not in ver:
            return ver, ps
    _, ver, ps = cands[0]
    return ver, ps


def main():
    with open(os.path.join(ROOT, "pubspec.yaml")) as f:
        root_ps = yaml.safe_load(f)

    resolved = {}  # name -> (version, pubspec)
    queue = []

    def add_dep(name, constraint):
        # keep the tightest: if already resolved with a version that
        # satisfies the new constraint, keep it.
        if name in resolved:
            ver, _ = resolved[name]
            if satisfies(ver, constraint):
                return
        queue.append((name, constraint))

    for section in ("dependencies", "dev_dependencies"):
        for name, spec in (root_ps.get(section) or {}).items():
            if isinstance(spec, dict):  # e.g. sdk: flutter
                continue
            add_dep(name, str(spec))

    while queue:
        name, constraint = queue.pop(0)
        if name in resolved and satisfies(resolved[name][0], constraint):
            continue
        ver, ps = pick_version(name, constraint)
        resolved[name] = (ver, ps)
        print(f"resolved {name} {ver}", flush=True)
        for section in ("dependencies",):
            for dn, dspec in (ps.get(section) or {}).items():
                if isinstance(dspec, dict):
                    continue  # sdk/path/git deps: skip (none expected)
                add_dep(dn, str(dspec))

    # Download + extract.
    overrides = {}
    for name, (ver, _) in sorted(resolved.items()):
        dest_dir = os.path.join(PKGDIR, f"{name}-{ver}")
        if not os.path.isdir(dest_dir):
            print(f"fetching {name}-{ver}", flush=True)
            with tempfile.TemporaryDirectory() as td:
                tgz = os.path.join(td, "pkg.tgz")
                curl_download(
                    f"https://pub.dev/api/archives/{name}-{ver}.tar.gz", tgz)
                os.makedirs(dest_dir, exist_ok=True)
                with tarfile.open(tgz) as tf:
                    tf.extractall(dest_dir)
        overrides[name] = {"path": dest_dir}

    with open(os.path.join(ROOT, "pubspec_overrides.yaml"), "w") as f:
        yaml.safe_dump({"dependency_overrides": overrides}, f,
                       default_flow_style=False)
    print(f"wrote overrides for {len(overrides)} packages")


if __name__ == "__main__":
    sys.exit(main())
