"""Isolated prepared-text candidate after stage probes; no shipping source edits."""
import hashlib, json, pathlib, shutil
path = pathlib.Path("BARQ/Views/AnalystChatView.swift")
original = path.read_text()
start = '                                let renderedAnswer = AnalystStageProbe.measure("markdown")'
end = '                                Text((reply.sourceNames'
assert original.count(start) == 1 and original.count(end) == 1
a, b = original.index(start), original.index(end)
old = original[a:b]
assert old.count('AnalystStageProbe.measure("accessibility-text")') == 1
assert '.textSelection(.enabled)' in old and '.contextMenu' in old
replacement = '                                AnalystRenderedAnswer(answer: reply.answer, isLatest: message.id == archive.current.turns.last?.id, english: en)\n'
modified = original[:a] + replacement + original[b:]
# Isolate lazy-row materialization from asynchronous text preparation.
# The failing fifth stored reply never started its rendering task.
container = "LazyVStack(alignment: .leading, spacing: 22)"
assert modified.count(container) == 1
modified = modified.replace(container, "VStack(alignment: .leading, spacing: 22)", 1)
assert modified.count('.glassEffect') == original.count('.glassEffect')
assert modified.count('scroll.scrollTo("chat-bottom", anchor: .bottom)') == 4
path.write_text(modified)
shutil.copyfile("ci/fixtures/AnalystRenderedAnswer.swift", "BARQ/Views/AnalystRenderedAnswer.swift")
manifest = pathlib.Path("out/synthetic-adapter.json")
data = json.loads(manifest.read_text())
data["kind"] += "; experimental prepared-text subview, not a shipping fix"
data["stage-probed-source-sha256"][str(path)] = hashlib.sha256(modified.encode()).hexdigest()
data["render-candidate"] = {
    "before": hashlib.sha256(original.encode()).hexdigest(),
    "after": hashlib.sha256(modified.encode()).hexdigest(),
    "helper": hashlib.sha256(pathlib.Path("BARQ/Views/AnalystRenderedAnswer.swift").read_bytes()).hexdigest(),
    "scope": "Markdown/accessibility text prepared off-main per row/answer; eager transcript container diagnostic; exact storage and original scroll handlers retained",
}
manifest.write_text(json.dumps(data, indent=2) + "\n")
