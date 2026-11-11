"""Synchronous stage probes in a disposable synthetic build; no shipping edits."""
import hashlib, json, pathlib, shutil

patches = {
    "BARQ/Views/AnalystChatView.swift": [
        ('(try? AttributedString(markdown: reply.answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(reply.answer)',
         'AnalystStageProbe.measure("markdown") { (try? AttributedString(markdown: reply.answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(reply.answer) }'),
        ('String(renderedAnswer.characters)', 'AnalystStageProbe.measure("accessibility-text") { String(renderedAnswer.characters) }'),
        ('let history = archive.current.history', 'let history = AnalystStageProbe.measure("history") { archive.current.history }'),
        ('archive.finish(conversation: conversationID, turn: message.id, reply: reply)', 'AnalystStageProbe.measure("finish") { archive.finish(conversation: conversationID, turn: message.id, reply: reply) }'),
    ],
    "BARQ/Core/API.swift": [
        ('try JSONDecoder().decode(AnalystReply.self, from: data)',
         'try AnalystStageProbe.measure("reply-decode") { try JSONDecoder().decode(AnalystReply.self, from: data) }'),
    ],
    "BARQ/Core/AnalystConversations.swift": [
        ('try JSONEncoder().encode(conversations)', 'try AnalystStageProbe.measure("archive-encode") { try JSONEncoder().encode(conversations) }'),
        ('try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])',
         'try AnalystStageProbe.measure("archive-write") { try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }'),
        ('try JSONDecoder().decode([AnalystConversation].self, from: Data(contentsOf: self.url))',
         'try AnalystStageProbe.measure("archive-load") { try JSONDecoder().decode([AnalystConversation].self, from: Data(contentsOf: self.url)) }'),
    ],
}
# Validate all targets before writing any target; never silently instrument a
# different source version or apply twice.
prepared = {}
for path, replacements in patches.items():
    original = pathlib.Path(path).read_text()
    modified = original
    for old, new in replacements:
        assert modified.count(old) == 1, f"Review stage probe target: {path}"
        assert new not in modified, f"Already instrumented: {path}"
        modified = modified.replace(old, new)
    prepared[path] = (original, modified)
manifest = {}
for path, (original, modified) in prepared.items():
    pathlib.Path(path).write_text(modified)
    manifest[path] = {
        "before": hashlib.sha256(original.encode()).hexdigest(),
        "after": hashlib.sha256(modified.encode()).hexdigest(),
        "probe-count": len(patches[path]),
    }
shutil.copyfile("ci/fixtures/AnalystStageProbe.swift", "BARQ/Core/AnalystStageProbe.swift")
pathlib.Path("out/stage-probes.json").write_text(json.dumps({
    "kind": "Synthetic synchronous wall-time probes only; not Instruments CPU samples or a shipping binary",
    "files": manifest,
}, indent=2) + "\n")

transport_manifest = pathlib.Path("out/synthetic-adapter.json")
if transport_manifest.exists():
    transport = json.loads(transport_manifest.read_text())
    for path in prepared:
        transport.get("unchanged-source-sha256", {}).pop(path, None)
    transport["stage-probed-source-sha256"] = {path: values["after"] for path, values in manifest.items()}
    transport["kind"] += "; synchronous stage probes applied after transport adaptation; see stage-probes.json"
    transport_manifest.write_text(json.dumps(transport, indent=2) + "\n")
