"""Prepara um patch revisável do pacote da montanha sem alterar arquivos compartilhados do jogo."""
from __future__ import annotations

import argparse
import difflib
import hashlib
import json
from pathlib import Path


def prepare(root: Path, spec_path: Path, output: Path) -> dict:
    spec = json.loads(spec_path.read_text(encoding="utf-8-sig"))
    changes: list[str] = []
    records: list[dict] = []
    previews: list[tuple[Path, str]] = []
    for entry in spec["files"]:
        relative = Path(entry["path"])
        source = (root / relative).resolve()
        if relative.is_absolute() or not source.is_relative_to(root):
            raise ValueError(f"Source outside project: {relative}")
        raw = source.read_bytes()
        original = raw.decode("utf-8-sig").replace("\r\n", "\n")
        revised = original
        applied: list[str] = []
        present: list[str] = []
        for edit in entry["edits"]:
            before, after = edit["before"], edit["after"]
            if before == after or not before or not after:
                raise ValueError(f"Empty/no-op edit: {relative}: {edit['id']}")
            if revised.count(after) == 1:
                present.append(edit["id"])
                continue
            matches = revised.count(before)
            if matches != 1:
                raise ValueError(
                    f"Shared source changed: {relative}: {edit['id']} has "
                    f"{matches} matching contexts; inspect current work before rebuilding."
                )
            revised = revised.replace(before, after, 1)
            applied.append(edit["id"])
        name = relative.as_posix()
        changes.extend(difflib.unified_diff(
            original.splitlines(keepends=True), revised.splitlines(keepends=True),
            fromfile=f"a/{name}", tofile=f"b/{name}", n=5,
        ))
        records.append({
            "path": name,
            "source_sha256": hashlib.sha256(raw).hexdigest(),
            "preview_sha256": hashlib.sha256(revised.encode("utf-8")).hexdigest(),
            "prepared_edits": applied,
            "already_present": present,
        })
        previews.append((output / "preview" / (name + ".txt"), revised))

    # Reconfere toda fonte depois que todos os contextos passam. Nunca publica patch montado
    # sobre versões mudando de um arquivo que é do outro agente da campanha.
    for record in records:
        current = (root / record["path"]).read_bytes()
        if hashlib.sha256(current).hexdigest() != record["source_sha256"]:
            raise ValueError(f"Source changed during preparation: {record['path']}")
    output.mkdir(parents=True, exist_ok=True)
    for destination, preview in previews:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(preview, encoding="utf-8", newline="\n")
    patch = output / "mountain-pack.patch"
    patch.write_text("".join(changes), encoding="utf-8", newline="\n")
    report = {"mode": "preview_only", "shared_files_written": 0,
              "patch": str(patch), "files": records}
    (output / "manifest.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--spec", type=Path,
                        default=Path(__file__).with_name("integration_edits.json"))
    parser.add_argument("--output", type=Path,
                        default=Path("evidence/mountain-pack-20261005/integration"))
    args = parser.parse_args()
    root = args.root.resolve()
    output = args.output if args.output.is_absolute() else root / args.output
    report = prepare(root, args.spec.resolve(), output.resolve())
    print(json.dumps({"mode": report["mode"], "shared_files_written": 0,
                      "patch": report["patch"], "files": len(report["files"])},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
