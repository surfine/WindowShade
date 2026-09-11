// WindowShade fold optics.
//
// Geometry. The page is hinged along its bottom edge. At fold angle θ a point at
// page depth d (0 at the hinge, 1 at the top) sits at
//     screen y = 1 - d·cos θ        glass depth = d·sin θ
// and a viewer at focal distance f, measured in page heights, projects it to
//     y' = 0.5 + (0.5 - d·cos θ) · f / (f - d·sin θ)
// with the same magnification applied horizontally. A long focal length keeps the
// fold flat; a short one leans the page toward the viewer.
//
// Defocus. Blur grows with how far the page has receded behind the glass. A
// thirteen-tap hexagonal disk approximates the circle of confusion; every tap is
// read from the page pyramid at the level that matches the tap spacing, so the
// pattern stays smooth without a dense kernel. Cost per pixel is one fetch while
// the page is close to the glass and thirteen once it is fully blurred, against
// thirty-two for a plain disk.

#include <metal_stdlib>
using namespace metal;

struct Varying { float4 position [[position]]; float2 uv; };
struct Uniforms { float4 geometry; float4 optics; float4 shape; float4 content; float4 resolution; };

constant float kTau = 6.28318530717958648;
constant float kMotionBlur = 0.028;

vertex Varying duoVertex(uint i [[vertex_id]]) {
    float2 p = float2((i << 1) & 2, i & 2);
    return { float4(p * 2 - 1, 0, 1), float2(p.x, 1 - p.y) };
}

static float tiltNoise(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123) * kTau;
}

/// Untouched capture, mapped through the content rect. Sharp endpoints and title
/// bars are composited from this sampler so they never pass through the pyramid.
static float4 sourceSample(texture2d<float> src, float2 uv, constant Uniforms &u) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 c = clamp(uv, float2(0.0, u.geometry.z > 0.5 ? u.geometry.y : 0.0), 1.0);
    return src.sample(s, u.content.xy + c * u.content.zw);
}

/// `page` holds exactly the content rect, so its own mip chain is the defocus
/// pyramid: level L averages a radius of roughly 2^L texels of the page.
static float4 pageSample(texture2d<float> page, float2 uv, float lod) {
    constexpr sampler s(address::clamp_to_edge, filter::linear, mip_filter::linear);
    return page.sample(s, clamp(uv, 0.0, 1.0), level(max(lod, 0.0)));
}

/// Builds the pyramid's base level from the content rect of the capture.
fragment float4 duoPage(Varying in [[stage_in]], texture2d<float> src [[texture(0)]],
                        constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    return src.sample(s, u.content.xy + in.uv * u.content.zw);
}

constant float kHexStep = 1.0471975512;
constant float kHexOffset = 0.5235987756;

static float4 defocus(texture2d<float> page, float2 uv, float radius, float2 pixel) {
    float pixels = radius * float(page.get_height());
    if (pixels < 1.0) { return pageSample(page, uv, 0.0); }
    // Pre-filter to the spacing of the taps themselves; denser kernels only add
    // fetches once the pyramid already removes the detail they would have caught.
    float lod = log2(max(pixels * 0.28, 1.0));
    float rotation = tiltNoise(pixel);
    float4 sum = pageSample(page, uv, lod);
    float weight = 1.0;
    for (int ring = 0; ring < 2; ++ring) {
        float scale = ring == 0 ? 0.52 : 0.86;
        for (int tap = 0; tap < 6; ++tap) {
            float angle = rotation + float(tap) * kHexStep + float(ring) * kHexOffset;
            sum += pageSample(page, uv + float2(cos(angle), sin(angle)) * radius * scale, lod);
            weight += 1.0;
        }
    }
    return sum / weight;
}

fragment float4 duoFragment(Varying in [[stage_in]], texture2d<float> src [[texture(0)]],
                            texture2d<float> backdrop [[texture(1)]],
                            texture2d<float> page [[texture(2)]],
                            constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float amount = clamp(u.geometry.x, 0.0, 1.0);
    float2 uv = in.uv;
    float2 pixel = in.position.xy;
    bool window = u.geometry.z > 0.5;
    float top = u.geometry.y;
    float2 motion = u.shape.yz;
    float motionMagnitude = length(motion);
    bool moving = motionMagnitude > 1e-4;
    float angle = amount * u.shape.x;
    if ((amount <= 0 && !moving) || (!window && angle < 1e-5 && !moving) || (window && uv.y <= top)) {
        // Title and fully open endpoints are sampled without any optical processing.
        return sourceSample(src, uv, u) * u.geometry.w;
    }
    if (window) {
        float4 bg = backdrop.sample(s, uv);
        if (amount >= 1) return bg;
        float body = (uv.y - top) / max(0.001, 1 - top);
        // Coverage follows the progress of the gesture; only the defocus radius
        // tracks the fold angle.
        float height = max(0.0001, cos(amount * M_PI_F * 0.5));
        float coverage = 1 - smoothstep(height - fwidth(body), height + fwidth(body), body);
        float depth = body / height;
        float2 mapped = float2(0.5 + (uv.x - 0.5) * (1 + amount * depth * 0.45),
                               top + (1 - top) * depth);
        float radius = u.optics.y * (clamp(depth, 0.0, 1.0) * sin(angle) + u.optics.w * amount);
        float aspect = max(u.resolution.x, 1.0) / max(u.resolution.y, 1.0);
        float2 feather = max(float2(radius / aspect, radius), fwidth(mapped));
        float edge = smoothstep(-feather.x, feather.x, mapped.x)
                   * (1 - smoothstep(1 - feather.x, 1 + feather.x, mapped.x));
        float4 color = defocus(page, mapped, radius, pixel);
        color.rgb *= max(1 - u.optics.z * radius, 0.0);
        return mix(bg, color, coverage * edge * u.geometry.w);
    }
    // Keep the captured desktop attached to the glass with a bounded shift.
    // This path is independent from the hinge fold amount, so the effect is
    // still visible at the open endpoint.
    float2 shifted = clamp(uv + motion * float2(0.055, 0.040) * (0.35 + 0.65 * (1.0 - uv.y)),
                           0.0, 1.0);
    float depth = 1 - shifted.y;
    float focal = max(u.optics.x, 0.5);
    float magnification = focal / max(focal - depth * sin(angle), 0.05);
    float2 hit = float2(0.5 + (shifted.x - 0.5) * magnification,
                        0.5 + (0.5 - depth * cos(angle)) * magnification);
    float radius = u.optics.y * (depth * sin(angle) + u.optics.w + motionMagnitude * kMotionBlur);
    if (any(hit < -radius) || any(hit > 1.0 + radius)) return float4(0, 0, 0, 1);
    float4 color = defocus(page, hit, radius, pixel);
    color.rgb *= max(1 - u.optics.z * radius, 0.0);
    return float4(color.rgb, 1) * u.geometry.w;
}

// The optical pass may run on a smaller intermediate surface. Sharp endpoints, title bars
// and uncovered background are composited at the original output resolution.
fragment float4 duoComposite(Varying in [[stage_in]], texture2d<float> src [[texture(0)]],
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
