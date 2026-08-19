from pathlib import Path
import re

p = Path('ios-src/CTJModernTooliOS/ContentView.swift')
s = p.read_text()

s = s.replace(
    'import SwiftUI\nimport UniformTypeIdentifiers',
    'import SwiftUI\nimport UIKit\nimport UniformTypeIdentifiers'
)

s = s.replace(
    '        .tint(.cyan)\n        .preferredColorScheme(.dark)',
    '        .frame(maxWidth: .infinity, maxHeight: .infinity)\n        .ignoresSafeArea(.container, edges: .bottom)\n        .tint(.cyan)\n        .preferredColorScheme(.dark)'
)

old = re.compile(r'''\n        \.fileImporter\(isPresented:\$importDisc, allowedContentTypes:\[\.item\], allowsMultipleSelection:false\) \{ result in\n            switch result \{\n            case \.success\(let urls\):\n                if let url = urls\.first \{ model\.importDisc\(url:url\) \}\n                else \{ model\.status = "لم يتم اختيار ملف" \}\n            case \.failure\(let e\):\n                model\.status="اختيار الملف فشل: \\(e\.localizedDescription\)"\n            \}\n        \}''')
replacement = '\n        .sheet(isPresented:$importDisc) {\n            AnyFilePicker(\n                onPick: { url in\n                    model.importDisc(url:url)\n                    importDisc = false\n                },\n                onCancel: { importDisc = false }\n            )\n            .ignoresSafeArea()\n        }'
s, count = old.subn(replacement, s)
if count != 1:
    raise SystemExit(f'Could not replace disc fileImporter; replacements={count}')

helper = Path('patches/AnyFilePicker_v11.swift').read_text()
helper = '\n'.join(line for line in helper.splitlines() if not line.startswith('import '))
s += '\n\n' + helper + '\n'
p.write_text(s)
