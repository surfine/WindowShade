#!/usr/bin/env python3
"""Compile the exact current production font-layout helper with independent cases."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
root=Path(__file__).resolve().parents[2]
out=Path(sys.argv[1]).resolve();out.mkdir(parents=True,exist_ok=True)
source=root/'prototype/App/FileShelfView.swift'
text=source.read_text()
start=text.index('@MainActor\nenum FileShelfNameLayout')
end=text.index('/// 一格：76',start)
helper=text[start:end]
entry=(root/'tools/design-qa/FileNameChecks.swift').read_text()
with tempfile.TemporaryDirectory(prefix='fileshelf-font-check-') as work:
    work=Path(work);combined=work/'Checks.swift';binary=work/'checks'
    combined.write_text('import Cocoa\n'+helper+entry.removeprefix('import Cocoa\n'))
    subprocess.run(['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library',str(combined),'-framework','Cocoa','-o',str(binary)],check=True)
    subprocess.run([str(binary),str(out/'name-checks.json')],check=True)
    (out/'compiled-check-source.swift').write_bytes(combined.read_bytes())
receipt={'exit_code':0,'exact_product_helper_extracted':True,'helper_sha256':hashlib.sha256(helper.encode()).hexdigest(),'product_source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'cases':len(json.loads((out/'name-checks.json').read_text())),'scope':'actual font widths and same production helper; not app runtime or live hardware'}
(out/'name-checks-exit.json').write_text(json.dumps(receipt,indent=2)+'\n')
