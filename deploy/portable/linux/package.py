#!/usr/bin/env python3
import argparse
import gzip
import hashlib
import json
import os
import shutil
import tarfile
from pathlib import Path

IMAGE_FIELDS = (
    ("LIBRECHAT_IMAGE", "LIBRECHAT_IMAGE_ID"),
    ("MONGO_IMAGE", "MONGO_IMAGE_ID"),
    ("MEILI_IMAGE", "MEILI_IMAGE_ID"),
)
FILES = ("compose.yaml", "setup.sh", "run.sh", "README.md")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Package the verified portable images for Linux amd64")
    parser.add_argument("--source-bundle", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    return parser.parse_args()


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def add_path(archive: tarfile.TarFile, path: Path, name: str, mode: int) -> None:
    info = archive.gettarinfo(str(path), arcname=name)
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "root"
    info.mode = mode
    if info.isfile():
        with path.open("rb") as source:
            archive.addfile(info, source)
        return
    archive.addfile(info)


def main() -> None:
    args = parse_args()
    source = args.source_bundle.resolve(strict=True)
    output = args.output_dir.resolve()
    manifest_path = source / "manifest.json"
    image_archive = source / "images.tar"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("format") != 1 or manifest.get("platform") != "linux/amd64":
        raise ValueError("Unsupported source bundle")
    images = manifest.get("images")
    if not isinstance(images, list) or len(images) != 3:
        raise ValueError("Source bundle must contain exactly three images")
    if not image_archive.is_file() or image_archive.stat().st_size < 1_000_000:
        raise ValueError("Missing or incomplete images.tar")
    image_hash = manifest.get("sha256")
    if not isinstance(image_hash, str) or len(image_hash) != 64:
        raise ValueError("Invalid source image hash")
    if hash_file(image_archive) != image_hash:
        raise ValueError("Source images.tar SHA256 does not match manifest.json")

    commit = manifest.get("sourceCommit")
    if not isinstance(commit, str) or len(commit) < 9:
        raise ValueError("Invalid source commit")
    version = commit[:9]
    bundle_name = f"librechat-0cherry-{version}-linux-amd64"
    bundle = output / bundle_name
    final_archive = output / f"{bundle_name}.tar.gz"
    checksum_path = output / f"{bundle_name}.tar.gz.sha256"
    if bundle.exists() or final_archive.exists() or checksum_path.exists():
        raise FileExistsError(f"Output exists; nothing was overwritten: {bundle}")

    source_dir = Path(__file__).resolve().parent
    output.mkdir(parents=True, exist_ok=True)
    bundle.mkdir()
    try:
        for filename in FILES:
            shutil.copy2(source_dir / filename, bundle / filename)
        license_path = source_dir.parents[2] / "LICENSE"
        if license_path.is_file():
            shutil.copy2(license_path, bundle / "LICENSE")
        try:
            os.link(image_archive, bundle / "images.tar")
        except OSError:
            shutil.copy2(image_archive, bundle / "images.tar")

        values: list[str] = []
        for index, (tag_field, id_field) in enumerate(IMAGE_FIELDS):
            item = images[index]
            tag = item.get("tag")
            image_id = item.get("id")
            if not isinstance(tag, str) or not isinstance(image_id, str):
                raise ValueError("Invalid image metadata")
            values.extend((f"{tag_field}={tag}", f"{id_field}={image_id}"))
        values.append(f"IMAGES_SHA256={image_hash}")
        (bundle / "images.env").write_text("\n".join(values) + "\n", encoding="utf-8", newline="\n")

        with final_archive.open("xb") as target:
            with gzip.GzipFile(filename="", mode="wb", fileobj=target, compresslevel=6) as compressed:
                with tarfile.open(fileobj=compressed, mode="w|", format=tarfile.PAX_FORMAT) as archive:
                    add_path(archive, bundle, bundle_name, 0o755)
                    for filename in ("compose.yaml", "images.env", "README.md", "LICENSE"):
                        add_path(archive, bundle / filename, f"{bundle_name}/{filename}", 0o644)
                    add_path(archive, bundle / "images.tar", f"{bundle_name}/images.tar", 0o600)
                    for filename in ("setup.sh", "run.sh"):
                        add_path(archive, bundle / filename, f"{bundle_name}/{filename}", 0o755)

        archive_hash = hash_file(final_archive)
        checksum_path.write_text(f"{archive_hash}  {final_archive.name}\n", encoding="utf-8")
        print(f"Ready: {final_archive}")
        print(f"SHA256: {archive_hash}")
        print(f"Bytes: {final_archive.stat().st_size}")
    except BaseException:
        if final_archive.exists():
            final_archive.unlink()
        raise


if __name__ == "__main__":
    main()
