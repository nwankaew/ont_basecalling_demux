import sys
from pathlib import Path
import csv
import re
import shutil
import hashlib

# ---------- Setup ---------- #
if len(sys.argv) != 3:
    print("Usage: python rename_file.py <fastq_directory> <csv_file>")
    sys.exit(1)

base_dir = Path(sys.argv[1]).resolve()
csv_path = Path(sys.argv[2]).resolve()

print(f"[INFO] Base FASTQ directory: {base_dir}")
print(f"[INFO] CSV metadata file: {csv_path}")

if not base_dir.exists():
    print(f"[ERROR] FASTQ directory does not exist: {base_dir}")
    sys.exit(1)

if not csv_path.exists():
    print(f"[ERROR] CSV file does not exist: {csv_path}")
    sys.exit(1)

# ---------- Load CSV ---------- #
def load_alias_mapping(csv_file):
    alias_map = {}
    with csv_file.open(newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            alias = row['alias'].strip()
            sample_id = row['sample_id'].strip()
            alias_map[alias] = sample_id
            print(f"[DEBUG] Mapping alias: {alias} → sample_id: {sample_id}")
    return alias_map

# ---------- Rename Files (if needed) ---------- #
def rename_hash_prefixed_files(directory):
    hash_pattern = re.compile(r'^([a-f0-9]{40})_(.+\.fastq\.gz)$')
    renamed = []

    for file_path in directory.glob("*.fastq.gz"):
        match = hash_pattern.match(file_path.name)
        if not match:
            continue

        new_name = match.group(2)
        new_path = directory / new_name
        try:
            file_path.rename(new_path)
            print(f"[RENAME] {file_path.name} → {new_name}")
            renamed.append(new_name)
        except Exception as e:
            print(f"[ERROR] Failed to rename {file_path.name}: {e}")

    return renamed

# ---------- Move Files to Sample Folder ---------- #
def move_files_to_sample_folders(directory, alias_map):
    for file_path in directory.glob("*.fastq.gz"):
        for alias, sample_id in alias_map.items():
            if file_path.name.startswith(f"{alias}.fastq.gz"):
                target_dir = directory / sample_id
                target_dir.mkdir(exist_ok=True)
                target_path = target_dir / file_path.name

                if target_path.exists():
                    print(f"[SKIP] Already moved: {target_path}")
                    continue

                try:
                    shutil.move(str(file_path), str(target_path))
                    print(f"[MOVE] {file_path.name} → {target_dir}")
                except Exception as e:
                    print(f"[ERROR] Failed to move {file_path.name}: {e}")
                break
        else:
            print(f"[WARN] No alias match for: {file_path.name}")

# ---------- Generate MD5SUMs ---------- #
def generate_md5sums(directory):
    print("\n[INFO] Generating MD5 checksums...")
    md5_file = directory / "md5sums.txt"

    with md5_file.open("w") as out:
        for fastq_path in directory.rglob("*.fastq.gz"):
            try:
                md5 = hashlib.md5()
                with fastq_path.open("rb") as f:
                    for chunk in iter(lambda: f.read(8192), b""):
                        md5.update(chunk)
                checksum = md5.hexdigest()
                out.write(f"{checksum}  {fastq_path.relative_to(directory)}\n")
                print(f"[MD5] {fastq_path.name}: {checksum}")
            except Exception as e:
                print(f"[ERROR] Failed to compute md5 for {fastq_path}: {e}")

    print(f"[DONE] Checksums saved to: {md5_file}")

# ---------- Main ---------- #
if __name__ == "__main__":
    alias_map = load_alias_mapping(csv_path)
    rename_hash_prefixed_files(base_dir)
    move_files_to_sample_folders(base_dir, alias_map)
    generate_md5sums(base_dir)
