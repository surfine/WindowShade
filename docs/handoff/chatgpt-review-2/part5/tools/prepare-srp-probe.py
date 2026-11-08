#!/usr/bin/env python3
"""Create an isolated dependency/typecheck probe. Does not resolve dependencies or edit the app."""
import argparse, hashlib, json, shutil
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('--out',type=Path,required=True); args=p.parse_args()
root=Path(__file__).resolve().parents[1]; out=args.out.resolve()
if out.exists() or root==out or root in out.parents: p.error('output must be a new directory outside this delivery')
adapter=root/'optional-srp/Sources/WS2SRPAdapter/WS2SRPAdapter.swift'
primitive=(root/'overlay/prototype/Support/WS2PairSetupCrypto.swift').read_text().split('#if canImport(CryptoKit)')[0]
out.mkdir(parents=True); target=out/'Sources/WS2SRPAdapter'; target.mkdir(parents=True)
shutil.copy2(adapter,target/adapter.name); (target/'Primitive.swift').write_text(primitive)
(out/'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name:"WS2SRPDependencyProbe", platforms:[.macOS(.v14)],
 products:[.library(name:"WS2SRPAdapter",targets:["WS2SRPAdapter"])],
 dependencies:[.package(url:"https://github.com/adam-fowler/swift-srp.git",revision:"1345dfeff4d1bc54fc36257325371df3d1d7a813")],
 targets:[.target(name:"WS2SRPAdapter",dependencies:[.product(name:"SRP",package:"swift-srp")])])
''')
(out/'README.md').write_text('''# Isolated Mac dependency probe
This is not the WindowShade build and does not prove SRP interoperability or constant-time behavior.
Run on a network-enabled Mac: `swift package resolve`, then `swift build -Xswiftc -swift-version -Xswiftc 6 -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`.
Preserve generated Package.resolved and compiler output. Inspect all resolved source licenses and BigNum/crypto backends before admitting a dependency into the real app. The primitive protocol is copied verbatim only for this isolated build, not a second app type. No Package.resolved is invented here.
''')
(out/'input-hashes.json').write_text(json.dumps({'adapter_sha256':hashlib.sha256(adapter.read_bytes()).hexdigest(),'primitive_sha256':hashlib.sha256(primitive.encode()).hexdigest(),'upstream_revision':'1345dfeff4d1bc54fc36257325371df3d1d7a813'},indent=2)+'\n')
print(json.dumps({'created':str(out),'resolved':False,'compiled':False}))
