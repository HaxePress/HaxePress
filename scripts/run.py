#!/usr/bin/env python3
"""Run the JVM application; it renders every page itself, without a Node.js process."""

from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def main():
    binary = ROOT / "Export/jvm/hxwell.jar"
    if not binary.exists():
        raise SystemExit("Run make build first.")
    app = None
    try:
        app = subprocess.Popen(
            ["java", "--enable-native-access=ALL-UNNAMED", "-jar", str(binary), "start"], cwd=ROOT
        )
        return app.wait()
    except KeyboardInterrupt:
        return 130
    finally:
        stop(app)


if __name__ == "__main__":
    sys.exit(main())
