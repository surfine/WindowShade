import Foundation
import Metal

/// Alternates A/B order on identical frames, one GPU submission at a time.
/// Usage: benchmark reference.metallib candidate.metallib output.json
@main struct OptimizationBenchmark {
  static func main() throws {
    let args = CommandLine.arguments
    precondition(args.count == 4)
    let device = MTLCreateSystemDefaultDevice()!, queue = device.makeCommandQueue()!
    func pipelines(_ path: String) throws -> [MTLRenderPipelineState] {
      let library = try device.makeLibrary(URL: URL(fileURLWithPath: path))
      return try ["duoFragment", "duoComposite"].map { name in
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "duoVertex")
        d.fragmentFunction = library.makeFunction(name: name)
        d.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try device.makeRenderPipelineState(descriptor: d)
      }
    }
    let states = try [pipelines(args[1]), pipelines(args[2])]
    func texture(_ width: Int, _ height: Int, shared: Bool = false) -> MTLTexture {
      let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
        width: width, height: height, mipmapped: false)
      d.storageMode = shared ? .shared : .private
      d.usage = [.renderTarget, .shaderRead]
      return device.makeTexture(descriptor: d)!
    }
    let width = 3420, height = 2214, opticalWidth = 960
    let source = texture(width, height, shared: true), output = texture(width, height)
    let optical = texture(opticalWidth, Int((Double(opticalWidth * height) / Double(width)).rounded()))
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for i in pixels.indices where i % 4 != 3 { pixels[i] = UInt8((i * 7) % 256) }
    source.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
      withBytes: pixels, bytesPerRow: width * 4)
    var times = [[Double](), [Double]()]
    for iteration in 0..<260 {
      for variant in (iteration % 2 == 0 ? [0, 1] : [1, 0]) {
        var uniforms: [Float] = [Float(0.5 + 0.4 * sin(Double(iteration) * 0.1)), 0, 0, 1,
          2254, 0.12, 0.015, 12, 0.45, 0, 0, 0, 0, 0, 1, 1, Float(width), Float(height), 0, 0]
        let command = queue.makeCommandBuffer()!
        for (target, state) in zip([optical, output], states[variant]) {
          let pass = MTLRenderPassDescriptor()
          pass.colorAttachments[0].texture = target
          pass.colorAttachments[0].loadAction = .dontCare
          pass.colorAttachments[0].storeAction = .store
          let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
          encoder.setRenderPipelineState(state)
          encoder.setFragmentTexture(source, index: 0)
          encoder.setFragmentTexture(source, index: 1)
          encoder.setFragmentTexture(optical, index: 2)
          encoder.setFragmentBytes(&uniforms, length: uniforms.count * 4, index: 0)
          encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
          encoder.endEncoding()
        }
        command.commit(); command.waitUntilCompleted()
        precondition(command.status == .completed)
        if iteration >= 20 { times[variant].append((command.gpuEndTime - command.gpuStartTime) * 1000) }
      }
    }
    let reports = times.enumerated().map { index, values -> [String: Any] in
      let sorted = values.sorted()
      return ["variant": index == 0 ? "ported" : "disk-basis", "samples": sorted.count,
        "gpuP50ms": sorted[sorted.count / 2], "gpuP95ms": sorted[Int(Double(sorted.count) * 0.95)],
        "gpuMeanMs": sorted.reduce(0, +) / Double(sorted.count)]
    }
    let result: [String: Any] = ["device": device.name, "outputPixels": [width, height],
      "opticalWidth": opticalWidth, "alternatingOrder": true, "results": reports]
    print(result)
    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
      .write(to: URL(fileURLWithPath: args[3]))
  }
}
