"""Build cross-platform commands for project-owned CI tools.

Why
---
Lix exposes Haxe through an extensionless Node shim. Git Bash can execute that shim directly on
Windows, but native Python ``subprocess`` cannot resolve it as a Windows executable.

What
----
``project_haxe_command`` returns a command that launches the repository-pinned Lix Haxe shim through
the active Node executable instead of relying on shell-specific shim behavior.

How
---
The caller supplies ordinary Haxe arguments. The helper validates both Node and the installed project
shim, then returns a list suitable for ``subprocess.run(..., shell=False)`` on Unix and Windows.
"""

from __future__ import annotations

from pathlib import Path
import shutil


def project_haxe_command(root: Path, arguments: list[str]) -> list[str]:
    node = shutil.which("node")
    if node is None:
        raise AssertionError("project Haxe command requires Node on PATH")

    shim = root / "node_modules" / "lix" / "bin" / "haxeshim.js"
    if not shim.is_file():
        raise AssertionError(f"project Lix Haxe shim is missing: {shim}")

    return [node, str(shim), *arguments]
