"""A declared transport adapter in a disposable build, not a production change."""
import hashlib, json, pathlib, shutil
api = pathlib.Path('BARQ/Core/API.swift')
original = api.read_bytes()
needle = b'static let shared = API()'
replacement = b'static let shared = API(protocolClasses: [AnalystSyntheticProtocol.self], fixedBase: "https://fotiq-synthetic.invalid")'
assert original.count(needle) == 1, 'API initializer changed; review adapter before continuing'
modified = original.replace(needle, replacement)
api.write_bytes(modified)
shutil.copyfile('ci/fixtures/AnalystSyntheticProtocol.swift', 'BARQ/Core/AnalystSyntheticProtocol.swift')
unchanged = ['BARQ/Views/AnalystChatView.swift', 'BARQ/Core/AnalystConversations.swift', 'BARQ/Core/AnalystChat.swift']
pathlib.Path('out').mkdir(exist_ok=True)
pathlib.Path('out/synthetic-adapter.json').write_text(json.dumps({
    'kind': 'synthetic transport injection only; not live acceptance or a shipping binary',
    'API-original-sha256': hashlib.sha256(original).hexdigest(),
    'API-adapted-sha256': hashlib.sha256(modified).hexdigest(),
    'replacement': replacement.decode(),
    'unchanged-source-sha256': {p: hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest() for p in unchanged},
}, indent=2)+'\n')
# Controlled candidate: expose the start of a long latest row instead of scrolling
# to its tail. ac1f stored Q2 with a responsive MainActor, but AX showed no chat
# text at 99% scroll. This does not claim to fix the separate live CPU stall.
view = pathlib.Path('BARQ/Views/AnalystChatView.swift')
view_original = view.read_bytes()
old = b'scroll.scrollTo("chat-bottom", anchor: .bottom)'
new = b'if let latest = archive.current.turns.last?.id { scroll.scrollTo(latest, anchor: .top) }'
assert view_original.count(old) == 4, 'Review candidate against changed scroll handlers'
view_modified = view_original.replace(old, new)
view.write_bytes(view_modified)
manifest = pathlib.Path('out/synthetic-adapter.json')
data = json.loads(manifest.read_text())
data['unchanged-source-sha256'].pop(str(view))
data['view-original-sha256'] = hashlib.sha256(view_original).hexdigest()
data['view-candidate-sha256'] = hashlib.sha256(view_modified).hexdigest()
data['view-replacement'] = new.decode()
data['kind'] += '; experimental latest-message top anchor, not a shipping fix'
manifest.write_text(json.dumps(data, indent=2)+'\n')
