import Foundation
import Metal

@main struct GPUBenchmark {
    static func main() throws {
        let device=MTLCreateSystemDefaultDevice()!, queue=device.makeCommandQueue()!
        let library=try device.makeLibrary(URL:URL(fileURLWithPath:".build/duo-metal/Duo.metallib"))
        func pipeline(_ fragment:String) throws -> MTLRenderPipelineState {
            let d=MTLRenderPipelineDescriptor();d.vertexFunction=library.makeFunction(name:"duoVertex");d.fragmentFunction=library.makeFunction(name:fragment);d.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try device.makeRenderPipelineState(descriptor:d)
        }
        let optics=try pipeline("duoFragment"),composite=try pipeline("duoComposite")
        func texture(_ w:Int,_ h:Int,_ shared:Bool=false)->MTLTexture {
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:w,height:h,mipmapped:false)
            d.usage=[.shaderRead,.renderTarget];d.storageMode=shared ? .shared:.private
            return device.makeTexture(descriptor:d)!
        }
        let width=3420,height=2214
        let source=texture(width,height,true),output=texture(width,height)
        var pixels=[UInt8](repeating:255,count:width*height*4)
        for i in pixels.indices where i%4 != 3 { pixels[i]=UInt8((i*7)%256) }
        source.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:pixels,bytesPerRow:width*4)
        var reports:[[String:Any]]=[]
        for optWidth in [1280,960] {
            let reduced=texture(optWidth,Int((Double(optWidth)*Double(height)/Double(width)).rounded()))
            var times:[Double]=[]
            for i in 0..<120 {
                var uniforms:[Float]=[Float(0.5+0.4*sin(Double(i)*0.1)),0,0,1,2254,0.12,0.015,12,0.45,0,0,0,0,0,1,1,Float(width),Float(height),0,0]
                let command=queue.makeCommandBuffer()!
                for (target,state) in [(reduced,optics),(output,composite)] {
                    let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .dontCare;pass.colorAttachments[0].storeAction = .store
                    let encoder=command.makeRenderCommandEncoder(descriptor:pass)!
                    encoder.setRenderPipelineState(state);encoder.setFragmentTexture(source,index:0);encoder.setFragmentTexture(source,index:1)
                    encoder.setFragmentTexture(reduced,index:2);encoder.setFragmentBytes(&uniforms,length:uniforms.count*4,index:0)
                    encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3);encoder.endEncoding()
                }
                command.commit();command.waitUntilCompleted();precondition(command.status == .completed)
                if i>19 { times.append((command.gpuEndTime-command.gpuStartTime)*1000) }
            }
            times.sort()
            let row:[String:Any]=["nativeWidth":width,"nativeHeight":height,"opticalWidth":optWidth,"gpuP50ms":times[times.count/2],"gpuP95ms":times[Int(Double(times.count)*0.95)]]
            print(row);reports.append(row)
        }
        try JSONSerialization.data(withJSONObject:reports,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:".build/duo-tests/gpu-benchmark.json"))
    }
}
