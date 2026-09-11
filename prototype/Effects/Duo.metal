// Adapted from DuoBook fd7b0fc, Copyright (c) 2026 Madhav Oberoi (MIT).
// See ThirdParty/DuoBook/LICENSE. Desktop optics, Vogel taps and presets retain upstream math.
// WindowShade additions: source content rect, title-bar isolation and window coverage.
#include <metal_stdlib>
using namespace metal;
struct Varying { float4 position [[position]]; float2 uv; };
struct Uniforms { float4 geometry; float4 optics; float4 shape; float4 content; float4 resolution; };
vertex Varying duoVertex(uint i [[vertex_id]]) {
    float2 p=float2((i<<1)&2,i&2);
    return {float4(p*2-1,0,1),float2(p.x,1-p.y)};
}
static float hash21(float2 p) { return fract(sin(dot(p,float2(12.9898,78.233)))*43758.5453); }
static float4 sampleContent(texture2d<float> src, float2 uv, constant Uniforms &u) {
    constexpr sampler s(address::clamp_to_edge,filter::linear);
    uv=clamp(uv,float2(0,u.geometry.z>0.5 ? u.geometry.y : 0),float2(1));
    return src.sample(s,u.content.xy+uv*u.content.zw);
}
static float4 frost(texture2d<float> src,float2 hit,float2 size,float radius,float2 pixel,constant Uniforms &u) {
    float attenuation=max(1-u.optics.z*radius,0.0);
    if(radius<0.5) { float4 c=sampleContent(src,hit/size,u); c.rgb*=attenuation; return c; }
    int taps=clamp(int(radius*2),6,32);
    float rotation=hash21(pixel)*6.28318530717958648;
    float4 sum=0;
    for(int i=0;i<taps;i++) {
        float r=radius*sqrt((float(i)+0.5)/float(taps));
        float a=float(i)*2.39996322972865332+rotation;
        sum+=sampleContent(src,(hit+r*float2(cos(a),sin(a)))/size,u);
    }
    sum/=float(taps); sum.rgb*=attenuation; return sum;
}
fragment float4 duoFragment(Varying in [[stage_in]],texture2d<float> src [[texture(0)]],
                           texture2d<float> backdrop [[texture(1)]],constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge,filter::linear);
    float amount=clamp(u.geometry.x,0.0,1.0);
    float2 size=float2(1000*u.resolution.x/u.resolution.y,1000);
    float2 uv=in.uv, pixel=in.position.xy;
    bool window=u.geometry.z>0.5;
    float top=u.geometry.y;
    float2 motion=u.shape.yz;
    float motionMagnitude=length(motion);
    bool moving=motionMagnitude>1e-4;
    if((amount<=0 && !moving) || (!window && amount*u.shape.x<1e-5 && !moving) || (window && uv.y<=top)) {
        // Title and fully open endpoints are sampled without any optical processing.
        constexpr sampler sharp(address::clamp_to_edge,filter::linear);
        return src.sample(sharp,u.content.xy+uv*u.content.zw)*u.geometry.w;
    }
    float tilt=amount*u.shape.x;
    if(window) {
        float4 bg=backdrop.sample(s,uv);
        if(amount>=1) return bg;
        float body=(uv.y-top)/max(0.001,1-top);
        float height=max(0.0001,cos(amount*M_PI_F*0.5));
        float coverage=1-smoothstep(height-fwidth(body),height+fwidth(body),body);
        float depth=body/height;
        float2 mapped=float2(0.5+(uv.x-0.5)*(1+amount*depth*0.45),top+(1-top)*depth);
        float radius=u.optics.y*(clamp(depth,0.0,1.0)*size.y*sin(tilt)+u.optics.w*amount);
        float2 feather=max(float2(radius)/size,fwidth(mapped));
        float edge=smoothstep(-feather.x,feather.x,mapped.x)*(1-smoothstep(1-feather.x,1+feather.x,mapped.x));
        float4 color=frost(src,mapped*size,size,radius,pixel,u);
        return mix(bg,color,coverage*edge*u.geometry.w);
    }
    // Keep the captured desktop attached to the glass with a bounded shift.
    // This path is independent from the hinge fold amount, so the effect is
    // still visible at the open endpoint.
    float2 movedUV=clamp(uv+motion*float2(0.055,0.040)*(0.35+0.65*(1.0-uv.y)),0.0,1.0);
    float d=size.y-movedUV.y*size.y;
    float3 glass=float3(movedUV.x*size.x,size.y-d*cos(tilt),d*sin(tilt));
    float3 eye=float3(size*0.5,u.optics.x);
    float depth=eye.z-glass.z;
    if(depth<=1e-3) return float4(0,0,0,1);
    float2 hit=eye.xy+(glass.xy-eye.xy)*(eye.z/depth);
    float radius=u.optics.y*(glass.z+u.optics.w+motionMagnitude*28.0);
    if(any(hit < -radius) || any(hit > size+radius)) return float4(0,0,0,1);
    float4 c=frost(src,hit,size,radius,pixel,u);
    return float4(c.rgb,1)*u.geometry.w;
}

// The optical pass may run on a smaller intermediate surface. Sharp endpoints, title bars
// and uncovered background are composited at the original output resolution.
fragment float4 duoComposite(Varying in [[stage_in]],texture2d<float> src [[texture(0)]],
                            texture2d<float> backdrop [[texture(1)]],
                            texture2d<float> optical [[texture(2)]],constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge,filter::linear);
    bool window=u.geometry.z>0.5;
    float amount=clamp(u.geometry.x,0.0,1.0);
    float motionMagnitude=length(u.shape.yz);
    bool moving=motionMagnitude>1e-4;
    if((amount<=0 && !moving) || (!window && amount*u.shape.x<1e-5 && !moving) || (window && in.uv.y<=u.geometry.y))
        return src.sample(s,u.content.xy+in.uv*u.content.zw)*u.geometry.w;
    if(window && amount>=1) return backdrop.sample(s,in.uv);
    return optical.sample(s,in.uv);
}
