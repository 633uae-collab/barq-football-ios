"""Run unchanged app persistence sources and XCTest cases on macOS.
This proves host persistence behavior only, not iOS UI or live Groq.
L is the sole host adapter: the app's language selector is fixed to Arabic.
No provider calls, simulator, entry files, recording, or deployment.
"""
from pathlib import Path
import hashlib
import json
import shutil

root = Path(__file__).resolve().parents[1]
out = root / "out"
package = out / "core-persistence-package"
sources = package / "Sources" / "BARQ"
tests = package / "Tests" / "BARQTests"
sources.mkdir(parents=True, exist_ok=True)
tests.mkdir(parents=True, exist_ok=True)
process_sources = package / "Sources" / "CorePersistenceProcess"
process_sources.mkdir(parents=True, exist_ok=True)
manifest = {}
for relative, destination in [
    ("BARQ/Core/AnalystChat.swift", sources),
    ("BARQ/Core/AnalystConversations.swift", sources),
    ("BARQTests/AnalystConversationTests.swift", tests),
]:
    original = root / relative
    target = destination / original.name
    shutil.copyfile(original, target)
    assert original.read_bytes() == target.read_bytes()
    manifest[relative] = hashlib.sha256(original.read_bytes()).hexdigest()
    if relative.startswith("BARQ/Core/"):
        shutil.copyfile(original, process_sources / original.name)
        assert original.read_bytes() == (process_sources / original.name).read_bytes()
(sources / "HostLanguage.swift").write_text('enum L { static let lang = "ar" }\n')
(process_sources / "HostLanguage.swift").write_text('enum L { static let lang = "ar" }\n')
shutil.copyfile(root / "ci/CorePersistenceProcess.swift", process_sources / "CorePersistenceProcess.swift")
(package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CorePersistenceHost", platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "CorePersistenceProcess"), .target(name: "BARQ"), .testTarget(name: "BARQTests", dependencies: ["BARQ"])])
''')
(out / "source-sha256.json").write_text(json.dumps(manifest, indent=2) + "\n")
print("Copied original sources and tests byte-for-byte; host language adapter only.")
