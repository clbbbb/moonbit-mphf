"""Compile an external package to check that backing storage cannot escape."""

from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
FIELDS = {
    "Mphf": ["values", "key_count", "vertex_count", "seed", "attempts"],
    "StaticSet": ["mphf", "keys_by_slot"],
    "StaticIntMap": ["mphf", "keys_by_slot", "values_by_slot"],
    "StaticIntBiMap": ["forward", "reverse"],
    "StaticIntMultiMap": ["mphf", "keys_by_slot", "offsets_by_slot", "values"],
    "StaticStringSet": ["mphf", "keys_by_slot"],
    "StaticStringIntMap": ["mphf", "keys_by_slot", "values_by_slot"],
    "SegmentedSet": ["segments"],
    "SegmentedIntMap": ["segments"],
    "ShardedSet": ["shard_count", "shards"],
    "ShardedIntMap": ["shard_count", "shards"],
    "StaticSetCursor": ["keys_by_slot", "next_slot"],
    "StaticIntMapCursor": ["keys_by_slot", "values_by_slot", "next_slot"],
    "StaticIntMultiMapCursor": ["keys_by_slot", "offsets_by_slot", "values", "slot", "value_index"],
    "StaticSetPatch": ["additions", "removals"],
    "StaticIntMapPatch": ["upserts", "removals"],
}


def check(package):
    return subprocess.run(
        ["moon", "check", "--no-render", str(package)],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
        timeout=60,
    )


def main():
    with tempfile.TemporaryDirectory(prefix="encapsulation_probe_", dir=ROOT) as directory:
        package = Path(directory)
        (package / "moon.pkg").write_text(
            'import { "clbbbb/moon-mphf" @mphf }\n', encoding="utf-8"
        )
        source = package / "probe.mbt"
        source.write_text(
            'pub fn smoke(value : @mphf.StaticIntMap) -> Int? { value.get(7) }\n',
            encoding="utf-8",
        )
        smoke = check(package)
        if smoke.returncode:
            raise SystemExit("Probe setup failed:\n" + smoke.stdout + smoke.stderr)
        checked = 0
        for type_name, fields in FIELDS.items():
            for field in fields:
                source.write_text(
                    f'pub fn probe(value : @mphf.{type_name}) -> Unit {{ ignore(value.{field}) }}\n',
                    encoding="utf-8",
                )
                result = check(package)
                diagnostics = result.stdout + result.stderr
                if result.returncode == 0:
                    raise SystemExit(f"Backing state is publicly accessible: {type_name}.{field}")
                if field not in diagnostics or not any(
                    phrase in diagnostics.lower() for phrase in ("private", "has no field", "not public")
                ):
                    raise SystemExit("Unexpected compiler failure:\n" + diagnostics)
                checked += 1
        print(f"Encapsulation passed: external access to {checked} backing fields rejected.")


if __name__ == "__main__":
    main()
