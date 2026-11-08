// swift-tools-version: 5.9
import PackageDescription
let package = Package(name:"WS2SRPDependencyProbe", platforms:[.macOS(.v14)],
 products:[.library(name:"WS2SRPAdapter",targets:["WS2SRPAdapter"])],
 dependencies:[.package(url:"https://github.com/adam-fowler/swift-srp.git",revision:"1345dfeff4d1bc54fc36257325371df3d1d7a813")],
 targets:[.target(name:"WS2SRPAdapter",dependencies:[.product(name:"SRP",package:"swift-srp")])])
