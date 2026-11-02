"""Build and verify a runtime-only ZIP from an immutable release tag."""
import argparse
import hashlib
from pathlib import Path, PurePosixPath
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile


ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    args = parser.parse_args()
    version = args.version
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        parser.error("Expected a version such as 2.6.0")
    commit = git("rev-parse", f"refs/tags/{version}^{{commit}}").decode().strip()
    tracked = git("ls-tree", "-r", "--name-only", commit).decode().splitlines()
    files = {}

    def include(name):
        name = name.replace("\\", "/")
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or name not in tracked:
            raise ValueError(f"Missing or unsafe runtime reference: {name}")
        if name in files:
            return
        data = git("show", f"{commit}:{name}")
        files[name] = data
        if path.suffix.lower() == ".toc":
            for line in data.decode("utf-8-sig").splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    include(str(path.parent / line.replace("\\", "/")))
        elif path.suffix.lower() == ".xml":
            for element in ET.fromstring(data).iter():
                reference = element.get("file")
                if reference:
                    include(str(path.parent / reference.replace("\\", "/")))

    include("GrosOrteil.toc")
    toc = files["GrosOrteil.toc"].decode("utf-8-sig")
    if not re.search(rf"^## Version: {re.escape(version)}\s*$", toc, re.M):
        raise ValueError("Tag and TOC versions differ")
    for name in tracked:
        path = PurePosixPath(name)
        if name.startswith("Libs/") and path.name.lower().startswith(("license", "copying")):
            include(name)
    for name in files:
        path = PurePosixPath(name)
        if any(p.startswith(".") or p.lower() in ("cache", "__pycache__", "tests") for p in path.parts):
            raise ValueError(f"Development file in package: {name}")
        if path.name.lower().startswith("readme"):
            raise ValueError(f"README in package: {name}")

    outer = f"GrosOrteil-v{version}"
    prefix = f"{outer}/GrosOrteil/"
    destination = ROOT / "releases" / f"{outer}.zip"
    destination.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(prefix + name)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    with zipfile.ZipFile(destination) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist()) == {prefix + name for name in files}
        for name, data in files.items():
            assert archive.read(prefix + name) == data
    print(f"Tag {version}: {commit}")
    print(f"Verified {len(files)} files: {destination}")
    print(f"SHA256: {hashlib.sha256(destination.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
