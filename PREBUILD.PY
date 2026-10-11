"""Create the output directories required by the WRK and ProjectOZ makefiles."""

from pathlib import Path


repo_root = Path(__file__).resolve().parent
ntos_root = repo_root / "WRK-V1.2" / "BASE" / "NTOS"

# Only source BUILD directories need object directories. Searching the entire
# checkout also enters generated build trees and creates unrelated outputs.
for build_directory in ntos_root.rglob("BUILD"):
    if build_directory.is_dir() and (build_directory / "MAKEFILE").is_file():
        for architecture in ("OBJI386", "OBJAMD64"):
            (build_directory / architecture).mkdir(exist_ok=True)

for relative_directory in (
    "WRK-V1.2/BASE/NTOS/BUILD/EXE",
    "ProjectOZ/BasicOZ/OBJI386",
    "ProjectOZ/SPACE/OBJI386",
    "ProjectOZ/runx86",
    "ProjectOZ/files/i386",
):
    (repo_root / relative_directory).mkdir(parents=True, exist_ok=True)
