#!/usr/bin/env python3
"""Check supplied evidence completeness, not product correctness or authorization."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

STAGES = ("source", "build", "runtime")
STATUSES = {"missing", "partial", "not-run", "failed", "passed"}

def tree_revision(root: Path) -> str:
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ValueError("candidate must be a directory")
    records = {}
    for p in sorted(root.rglob("*")):
        if p.is_symlink():
            raise ValueError("candidate symlinks are not supported")
        if p.is_file():
            records[p.relative_to(root).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return hashlib.sha256(json.dumps(records, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

def log_file(root: Path, name: object) -> Path:
    if not isinstance(name, str) or not name or "\\" in name:
        raise ValueError("missing or invalid logPath")
    rel = Path(name)
    if rel.is_absolute() or any(x in ("..", ".") for x in rel.parts):
        raise ValueError("log path must be relative without traversal")
    p = root / rel
    current = root
    for part in rel.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError("symlink evidence is not supported")
    p = p.resolve(strict=True)
    if not p.is_relative_to(root) or not p.is_file() or p.stat().st_size > 32 * 1024 * 1024:
        raise ValueError("invalid, escaped or oversized log")
    return p

def evaluate(document: object, root: Path, revision: str) -> dict:
    """A passing result means the supplied required evidence records are complete."""
    root = root.resolve(strict=True)
    errors: list[str] = []
    results: list[dict] = []
    if not isinstance(document, dict) or document.get("schemaVersion") != 1:
        return {"status": "BLOCKED", "errors": ["unsupported evidence schema"], "capabilities": []}
    if document.get("candidateRevision") != revision:
        errors.append("candidate revision mismatch")
    capabilities = document.get("capabilities")
    if not isinstance(capabilities, list) or not capabilities or len(capabilities) > 128:
        return {"status": "BLOCKED", "errors": errors + ["capabilities must contain 1..128 entries"], "capabilities": []}
    seen: set[str] = set()
    for item in capabilities:
        local: list[str] = []
        if not isinstance(item, dict):
            errors.append("malformed capability")
            continue
        ident = item.get("id")
        if not isinstance(ident, str) or not ident or ident in seen:
            errors.append("missing or duplicate capability id")
            continue
        seen.add(ident)
        # No optional/suppressed capability bypass in this tool. Supply the desired feature scope explicitly.
        expectations = item.get("expectedEnvironment", {})
        if not isinstance(expectations, dict):
            expectations = {}
        for stage in STAGES:
            record = item.get(stage)
            if not isinstance(record, dict):
                local.append(f"{stage}: missing record")
                continue
            status = record.get("status")
            if status not in STATUSES:
                local.append(f"{stage}: invalid status")
            if status != "passed":
                local.append(f"{stage}: {status}")
                continue
            if record.get("candidateRevision") != revision:
                local.append(f"{stage}: stale candidate")
            expected = expectations.get(stage)
            if not isinstance(expected, str) or not expected or record.get("environment") != expected:
                local.append(f"{stage}: environment mismatch or unspecified expectation")
            if record.get("exitCode") != 0 or isinstance(record.get("exitCode"), bool):
                local.append(f"{stage}: exitCode must be integer zero")
            for field in ("command", "recordedAt"):
                if not isinstance(record.get(field), str) or not record[field].strip():
                    local.append(f"{stage}: missing {field}")
            try:
                log = log_file(root, record.get("logPath"))
                digest = hashlib.sha256(log.read_bytes()).hexdigest()
                if record.get("logSHA256") != digest:
                    local.append(f"{stage}: log hash mismatch")
            except (ValueError, OSError) as ex:
                local.append(f"{stage}: {ex}")
        reviewer = item.get("reviewer")
        if not isinstance(reviewer, dict) or not isinstance(reviewer.get("name"), str) or not reviewer["name"].strip() or reviewer.get("decision") != "accepted":
            local.append("manual reviewer acceptance missing")
        results.append({"id": ident, "status": "BLOCKED" if local else "EVIDENCE_COMPLETE", "errors": local})
        errors.extend(f"{ident}: {x}" for x in local)
    return {"status": "BLOCKED" if errors else "EVIDENCE_COMPLETE", "candidateRevision": revision,
            "scope": "supplied capabilities only; no semantic, identity or release certification", "errors": errors, "capabilities": results}

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--evidence-root", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        if args.input.stat().st_size > 1024 * 1024:
            raise ValueError("evidence document exceeds 1 MiB")
        result = evaluate(json.loads(args.input.read_text()), args.evidence_root, tree_revision(args.candidate))
    except (OSError, ValueError) as ex:
        result = {"status": "BLOCKED", "errors": [str(ex)]}
    text = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text)
    print(text, end="")
    return 0 if result["status"] == "EVIDENCE_COMPLETE" else 2

if __name__ == "__main__":
    raise SystemExit(main())
