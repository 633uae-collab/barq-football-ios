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
