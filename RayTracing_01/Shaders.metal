//------------------------------------------------------------------------------
//  Shaders.metal
//------------------------------------------------------------------------------
#include <metal_stdlib>
#include <simd/simd.h>
#import "ShaderTypes.h"

using namespace metal;

//------------------------------------------------------------------------------
// Vertex types
//------------------------------------------------------------------------------
struct VertexIn
{
    float2 position [[attribute(0)]];
};
//---------------------------------------------
struct VertexOut
{
    float4 position [[position]];
    float2 uv;
};
//------------------------------------------------------------------------------
// Fullscreen quad vertex shader
//------------------------------------------------------------------------------
vertex VertexOut conicVertex(uint vertexID [[vertex_id]],
                             constant float2 *vertices [[buffer(BufferIndexVertices)]])
{
    VertexOut out;
    float2 pos = vertices[vertexID];
    out.position = float4(pos, 0.0, 1.0);
    //----------------------------
    // Map from [-1,1] to [0,1]
    //----------------------------
    out.uv = pos * 0.5 + 0.5;
    return out;
}
//------------------------------------------------------------------------------
// Ray tracing helpers
//------------------------------------------------------------------------------
struct Ray
{
    float3 origin;
    float3 direction;
};
//------------------------------------------------------------------------------
struct Hit
{
    float t;
    float3 normal;
    float4 color;
    bool valid;
    int objectID; // 0 = cone, 1 = plane
};
//------------------------------------------------------------------------------
// Intersect an infinite double cone:
//   x² + z² = (y * k)²
// where k = tan(halfAngle).
// The cone's apex is at 'apex', axis along Y.
//------------------------------------------------------------------------------
Hit intersectDoubleCone(Ray ray, float3 apex,
                        float halfAngle, float height, float4 color)
{
    Hit hit;
    hit.valid = false;
    hit.t = 1e20;

    float k = tan(halfAngle);
    float k2 = k * k;
    //---------------------------------------------
    // Shift ray origin relative to apex
    //---------------------------------------------
    float3 o = ray.origin - apex;
    float3 d = ray.direction;
    //---------------------------------------------
    // Quadratic coefficients for
    //   (ox+t*dx)² + (oz+t*dz)² - k²*(oy+t*dy)² = 0
    //---------------------------------------------
    float a = d.x * d.x + d.z * d.z
    - k2 * d.y * d.y;
    float b = 2.0 * (o.x * d.x + o.z * d.z
                     - k2 * o.y * d.y);
    float c = o.x * o.x + o.z * o.z
    - k2 * o.y * o.y;

    float disc = b * b - 4.0 * a * c;
    if (disc < 0.0) return hit;

    float sqrtDisc = sqrt(disc);
    float inv2a = 1.0 / (2.0 * a);
    //---------------------------------------------
    // Check both roots
    //---------------------------------------------
    for (int i = 0; i < 2; i++)
    {
        float t = (-b + (i == 0 ? -1.0 : 1.0)
                   * sqrtDisc) * inv2a;
        if (t < 0.001) continue;

        float3 p = o + t * d;

        //---------------------------------------------
        // Clamp to finite height
        //---------------------------------------------
        if (abs(p.y) > height) continue;

        if (t < hit.t)
        {
            hit.t = t;
            hit.valid = true;

            //---------------------------------------------
            // Normal on cone surface
            // Gradient of f = x²+z²-k²y²
            //---------------------------------------------
            float3 n = 2.0 * float3(p.x, -k2 * p.y, p.z);
            hit.normal = normalize(n);

            //---------------------------------------------
            // Flip normal to face the ray
            //---------------------------------------------
            if (dot(hit.normal, d) > 0.0)
                hit.normal = -hit.normal;

            hit.color = color;
            hit.objectID = 0;
        }
    }
    return hit;
}
//------------------------------------------------------------------------------
// Intersect a plane: dot(p, normal) = offset
//------------------------------------------------------------------------------
Hit intersectPlane(Ray ray, float3 planeNormal,
                   float planeOffset, float radius, float4 color)
{
    Hit hit;
    hit.valid = false;
    hit.t = 1e20;

    float denom = dot(ray.direction, planeNormal);
    if (abs(denom) < 1e-6) return hit;

    float t = (planeOffset
               - dot(ray.origin, planeNormal)) / denom;
    if (t < 0.001) return hit;

    float3 p = ray.origin + t * ray.direction;

    //---------------------------------------------
    // Limit plane to a circular disc
    //---------------------------------------------
    float3 center = planeNormal * planeOffset;
    float dist = length(p - center);
    if (dist > radius) return hit;

    hit.t = t;
    hit.valid = true;
    hit.normal = planeNormal;
    if (denom > 0.0)
        hit.normal = -hit.normal;
    hit.color = color;
    hit.objectID = 1;

    return hit;
}
//------------------------------------------------------------------------------
// Lighting
//------------------------------------------------------------------------------
float3 shade(float3 point,
             float3 normal,
             float3 viewDir,
             float4 objColor,
             float3 lightDir)
{
    float3 baseColor = objColor.rgb;

    //---------------------------------------------
    // Ambient
    //---------------------------------------------
    float3 ambient = 0.15 * baseColor;
    //---------------------------------------------
    // Diffuse
    //---------------------------------------------
    float NdotL = max(dot(normal, lightDir), 0.0);
    float3 diffuse = 0.7 * NdotL * baseColor;
    //---------------------------------------------
    // Specular (Blinn-Phong)
    //---------------------------------------------
    float3 halfVec = normalize(lightDir + viewDir);
    float NdotH = max(dot(normal, halfVec), 0.0);
    float spec = pow(NdotH, 64.0);
    float3 specular = 0.5 * spec * float3(1.0);

    return ambient + diffuse + specular;
}
//------------------------------------------------------------------------------
// Fragment shader (ray tracer)
//------------------------------------------------------------------------------
fragment float4 conicFragment(VertexOut in [[stage_in]],
                              constant Uniforms &uniforms
                              [[buffer(BufferIndexUniforms)]])
{
    //---------------------------------------------
    // Build ray from camera through pixel
    //---------------------------------------------
    float2 res = uniforms.resolution;
    float2 pixelNDC = in.uv;
    //---------------------------------------------
    // Map to clip space [-1, 1]
    //---------------------------------------------
    float2 clip = pixelNDC * 2.0 - 1.0;
    //---------------------------------------------
    // Flip Y for Metal's coordinate system
    //---------------------------------------------
    clip.y = -clip.y;
    //---------------------------------------------
    // Unproject near and far points
    //---------------------------------------------
    float4 nearClip = float4(clip, 0.0, 1.0);
    float4 farClip  = float4(clip, 1.0, 1.0);

    float4 nearWorld =
    uniforms.inverseViewProjection * nearClip;
    float4 farWorld  =
    uniforms.inverseViewProjection * farClip;
    nearWorld /= nearWorld.w;
    farWorld  /= farWorld.w;

    Ray ray;
    ray.origin = nearWorld.xyz;
    ray.direction = normalize(farWorld.xyz - nearWorld.xyz);

    //---------------------------------------------
    // Scene setup
    //---------------------------------------------
    float3 coneApex = float3(0.0, 0.0, 0.0);
    float coneHalfAngle = 0.45; // radians (~26°)
    float coneHeight = 2.5;
    float k_scene = tan(coneHalfAngle);
    float k2_scene = k_scene * k_scene;

    //---------------------------------------------
    // Transparent cyan cone
    //---------------------------------------------
    float4 coneColor = float4(0.0, 0.85, 0.95, 0.2);

    //---------------------------------------------
    // Animated plane — sweeps through all
    // conic sections by tilting the normal
    // from Y axis (circle) toward X (hyperbola)
    //
    // Angle of normal from Y:
    //   0°           → circle
    //   0°–64°       → ellipse
    //   64° (90-half)→ parabola
    //   64°–85°      → hyperbola
    //---------------------------------------------
    float sweep = uniforms.time * 0.15;
    // Ping-pong between 0 and ~85 degrees
    float maxTilt = 1.48; // ~85 degrees
    float raw = fmod(sweep, 2.0 * maxTilt);
    float tilt = (raw <= maxTilt)
    ? raw : (2.0 * maxTilt - raw);

    float3 planeNormal = normalize(float3(sin(tilt), cos(tilt), 0.0));
    float planeOffset = 0.5;
    float planeRadius = 3.5;

    //---------------------------------------------
    // Transparent amber/gold plane
    //---------------------------------------------
    float4 planeColor = float4(1.0, 0.7, 0.15, 0.40);

    //---------------------------------------------
    // Light direction
    //---------------------------------------------
    float3 lightDir = normalize(float3(1.0, 1.0, 0.8));

    //---------------------------------------------
    // Collect all hits (up to 4: 2 cone + 1 plane
    //   + we check both sides of cone)
    //---------------------------------------------
    Hit hits[3];
    int hitCount = 0;

    Hit coneHit = intersectDoubleCone(ray, coneApex,
                                      coneHalfAngle, coneHeight,
                                      coneColor);
    //---------------------------------------------
    // The cone can have 2 intersections
    // Get the first (nearest) hit
    //---------------------------------------------
    if (coneHit.valid)
    {
        hits[hitCount] = coneHit;
        hitCount++;

        //------------------------------------
        // Find second cone hit (far side)
        //------------------------------------
        float k = tan(coneHalfAngle);
        float k2 = k * k;
        float3 o = ray.origin - coneApex;
        float3 d = ray.direction;
        float a = d.x*d.x + d.z*d.z - k2*d.y*d.y;
        float b = 2.0*(o.x*d.x + o.z*d.z
                       - k2*o.y*d.y);
        float c = o.x*o.x + o.z*o.z - k2*o.y*o.y;
        float disc = b*b - 4.0*a*c;
        if (disc >= 0.0)
        {
            float sqrtDisc = sqrt(disc);
            float inv2a = 1.0 / (2.0 * a);
            float t1 = (-b - sqrtDisc) * inv2a;
            float t2 = (-b + sqrtDisc) * inv2a;
            //-----------------------
            // Use the farther hit
            //-----------------------
            float tFar = max(t1, t2);
            if (tFar > 0.001)
            {
                float3 p = o + tFar * d;
                if (abs(p.y) <= coneHeight)
                {
                    Hit h;
                    h.t = tFar;
                    h.valid = true;
                    float3 n = 2.0*float3(p.x, -k2*p.y, p.z);
                    h.normal = normalize(n);
                    if (dot(h.normal, d) > 0.0)
                        h.normal = -h.normal;
                    h.color = coneColor;
                    h.objectID = 0;
                    hits[hitCount] = h;
                    hitCount++;
                }
            }
        }
    }
    //---------------------------------------------
    Hit planeHit = intersectPlane(ray, planeNormal, planeOffset,
                                  planeRadius, planeColor);
    if (planeHit.valid)
    {
        hits[hitCount] = planeHit;
        hitCount++;
    }
    //---------------------------------------------
    // No hits — dark gradient background
    //---------------------------------------------
    if (hitCount == 0)
    {
        float grad = 0.08 + 0.06 * in.uv.y;
        return float4(grad, grad, grad * 1.2, 1.0);
    }
    //---------------------------------------------
    // Sort hits by distance (simple bubble sort)
    //---------------------------------------------
    for (int i = 0; i < hitCount - 1; i++)
    {
        for (int j = i + 1; j < hitCount; j++)
        {
            if (hits[j].t < hits[i].t)
            {
                Hit tmp = hits[i];
                hits[i] = hits[j];
                hits[j] = tmp;
            }
        }
    }
    //---------------------------------------------
    // Composite front-to-back with alpha
    //---------------------------------------------
    float3 viewDir = -ray.direction;
    float3 accum = float3(0.0);
    float alphaAccum = 0.0;

    //---------------------------------------------
    // Highlight color for the conic section
    //---------------------------------------------
    float3 highlightColor = float3(1.0, 1.0, 0.4);
    float lineWidth = 0.06;

    for (int i = 0; i < hitCount; i++)
    {
        if (alphaAccum >= 0.98) break;

        float3 point = ray.origin
        + hits[i].t * ray.direction;

        float3 litColor = shade(point, hits[i].normal,
                                viewDir, hits[i].color, lightDir);

        float alpha = hits[i].color.a;

        //---------------------------------------------
        // Check proximity to intersection curve
        // On cone: check distance TO the plane
        // On plane: check distance TO the cone
        //---------------------------------------------
        float3 rel = point - coneApex;
        float proximity;
        if (hits[i].objectID == 0)
        {
            //-----------------------
            // On cone — distance to plane
            //-----------------------
            proximity = abs( dot(point, planeNormal)
                            - planeOffset);
        }
        else
        {
            //-----------------------
            // On plane — linearized distance
            // to cone surface:
            // sqrt(x²+z²) - k*|y|
            //-----------------------
            float r = length(rel.xz);
            proximity = abs(r - k_scene * abs(rel.y));
        }
        float glow = smoothstep(lineWidth, 0.0, proximity
                                );

        //---------------------------------------------
        // Blend highlight into the surface color
        //---------------------------------------------
        litColor = mix(litColor, highlightColor, glow * 0.9);
        alpha = max(alpha, glow * 0.85);

        //---------------------------------------------
        // Front-to-back compositing
        //---------------------------------------------
        float contrib = alpha * (1.0 - alphaAccum);
        accum += litColor * contrib;
        alphaAccum += contrib;
    }

    //---------------------------------------------
    // Blend with background
    //---------------------------------------------
    float grad = 0.08 + 0.06 * in.uv.y;
    float3 bg = float3(grad, grad, grad * 1.2);
    accum += bg * (1.0 - alphaAccum);

    return float4(accum, 1.0);
}

// ═══════════════════════════════════════════════
// DEMO 2: Cone & Sphere
// ═══════════════════════════════════════════════

//------------------------------------------------------------------------------
// Intersect a sphere centered at 'center'
// with radius 'r'. Returns up to 2 hits.
//------------------------------------------------------------------------------
void intersectSphere(
                     Ray ray,
                     float3 center,
                     float radius,
                     float4 color,
                     thread Hit *hits,
                     thread int &hitCount)
{
    float3 oc = ray.origin - center;
    float a = dot(ray.direction, ray.direction);
    float b = 2.0 * dot(oc, ray.direction);
    float c = dot(oc, oc) - radius * radius;
    float disc = b * b - 4.0 * a * c;
    if (disc < 0.0) return;

    float sqrtDisc = sqrt(disc);
    float inv2a = 1.0 / (2.0 * a);

    for (int i = 0; i < 2; i++)
    {
        float sign = (i == 0) ? -1.0 : 1.0;
        float t = (-b + sign * sqrtDisc) * inv2a;
        if (t < 0.001) continue;

        Hit h;
        h.t = t;
        h.valid = true;
        h.objectID = 1; // sphere
        float3 p = ray.origin + t * ray.direction;
        h.normal = normalize(p - center);
        if (dot(h.normal, ray.direction) > 0.0)
            h.normal = -h.normal;
        h.color = color;
        hits[hitCount] = h;
        hitCount++;
    }
}
//------------------------------------------------------------------------------
// Intersect a cone with arbitrary axis direction.
// apex: tip of the cone
// axis: unit direction of cone axis
// halfAngle: half-angle in radians
// height: max distance from apex along axis
//------------------------------------------------------------------------------
void intersectConeArbitrary(
                            Ray ray,
                            float3 apex,
                            float3 axis,
                            float halfAngle,
                            float height,
                            float4 color,
                            thread Hit *hits,
                            thread int &hitCount)
{
    float cosA = cos(halfAngle);
    float cos2 = cosA * cosA;

    float3 co = ray.origin - apex;
    float dDotA = dot(ray.direction, axis);
    float coDotA = dot(co, axis);

    //-----------------------------------
    // Quadratic: (d·a)² - cos²α(d·d) = 0
    // expanded for the full cone equation
    //-----------------------------------
    float a = dDotA * dDotA
    - cos2 * dot(ray.direction, ray.direction);
    float b = 2.0 * (dDotA * coDotA - cos2 * dot(co, ray.direction));
    float c = coDotA * coDotA
    - cos2 * dot(co, co);

    float disc = b * b - 4.0 * a * c;
    if (disc < 0.0) return;

    float sqrtDisc = sqrt(disc);
    float inv2a = 1.0 / (2.0 * a);

    for (int i = 0; i < 2; i++)
    {
        float sign = (i == 0) ? -1.0 : 1.0;
        float t = (-b + sign * sqrtDisc) * inv2a;
        if (t < 0.001) continue;

        float3 p = ray.origin + t * ray.direction;
        float3 v = p - apex;
        float along = dot(v, axis);

        //------------------------------
        // Only the forward half of the cone,
        // clamped to height
        //------------------------------
        if (along < 0.0 || along > height)
            continue;

        Hit h;
        h.t = t;
        h.valid = true;
        h.objectID = 0; // cone

        //------------------------------
        // Normal: gradient of cone implicit
        // f(p) = (v·a)² - cos²α |v|² = 0
        //------------------------------
        float3 n = 2.0 * (along * axis - cos2 * v);
        h.normal = normalize(n);
        if (dot(h.normal, ray.direction) > 0.0)
            h.normal = -h.normal;
        h.color = color;
        hits[hitCount] = h;
        hitCount++;
    }
}
//------------------------------------------------------------------------------
vertex VertexOut coneSphereVertex(
                                  uint vertexID [[vertex_id]],
                                  constant float2 *vertices
                                  [[buffer(BufferIndexVertices)]])
{
    VertexOut out;
    float2 pos = vertices[vertexID];
    out.position = float4(pos, 0.0, 1.0);
    out.uv = pos * 0.5 + 0.5;
    return out;
}
//------------------------------------------------------------------------------
fragment float4 coneSphereFragment(VertexOut in [[stage_in]],
                                   constant Uniforms &uniforms
                                   [[buffer(BufferIndexUniforms)]])
{
    //---------------------------------------------
    // Build ray
    //---------------------------------------------
    float2 clip = in.uv * 2.0 - 1.0;
    clip.y = -clip.y;

    float4 nearClip = float4(clip, 0.0, 1.0);
    float4 farClip  = float4(clip, 1.0, 1.0);

    float4 nearWorld = uniforms.inverseViewProjection * nearClip;
    float4 farWorld = uniforms.inverseViewProjection * farClip;

    nearWorld /= nearWorld.w;
    farWorld  /= farWorld.w;

    Ray ray;
    ray.origin = nearWorld.xyz;
    ray.direction = normalize(farWorld.xyz - nearWorld.xyz);

    //---------------------------------------------
    // Scene setup
    //---------------------------------------------
    float3 origin = float3(0.0);
    float sphereRadius = 2.5;
    float coneHalfAngle = 0.4; // ~23°
    float coneHeight = 4.0;

    //---------------------------------------------
    // Rotate cone axis over time
    //---------------------------------------------
    float t = uniforms.time * 0.4;
    float3 coneAxis = normalize(float3(sin(t) * cos(t * 0.7),
                                       cos(t),
                                       sin(t) * sin(t * 0.7)));

    //---------------------------------------------
    // Colors
    //---------------------------------------------
    float4 sphereColor = float4(0.3, 0.6, 1.0, 0.2);
    float4 coneColor = float4(1.0, 0.4, 0.2, 0.25);

    //---------------------------------------------
    // Collect hits (up to 4: 2 sphere + 2 cone)
    //---------------------------------------------
    Hit hits[4];
    int hitCount = 0;

    intersectSphere(ray, origin, sphereRadius,
                    sphereColor, hits, hitCount);
    intersectConeArbitrary(ray, origin, coneAxis,
                           coneHalfAngle, coneHeight,
                           coneColor, hits, hitCount);

    //---------------------------------------------
    // No hits — background
    //---------------------------------------------
    if (hitCount == 0)
    {
        float grad = 0.08 + 0.06 * in.uv.y;
        return float4(grad, grad, grad * 1.2, 1.0);
    }
    //---------------------------------------------
    // Sort hits by distance
    //---------------------------------------------
    for (int i = 0; i < hitCount - 1; i++)
    {
        for (int j = i + 1; j < hitCount; j++)
        {
            if (hits[j].t < hits[i].t)
            {
                Hit tmp = hits[i];
                hits[i] = hits[j];
                hits[j] = tmp;
            }
        }
    }
    //---------------------------------------------
    // Composite with intersection highlight
    //---------------------------------------------
    float3 lightDir = normalize(float3(1.0, 1.0, 0.8));
    float3 viewDir = -ray.direction;
    float3 highlightColor = float3(1.0, 1.0, 0.4);
    float lineWidth = 0.08;

    float cosA = cos(coneHalfAngle);
    float cos2 = cosA * cosA;

    float3 accum = float3(0.0);
    float alphaAccum = 0.0;

    for (int i = 0; i < hitCount; i++)
    {
        if (alphaAccum >= 0.98) break;

        float3 point = ray.origin
        + hits[i].t * ray.direction;

        float3 litColor = shade(point, hits[i].normal,
                                viewDir, hits[i].color, lightDir);
        float alpha = hits[i].color.a;

        //---------------------------------------------
        // Proximity to intersection curve
        //---------------------------------------------
        float3 v = point - origin;
        float proximity;

        if (hits[i].objectID == 1)
        {
            //------------------------------
            // On sphere — distance to cone
            // cone eqn: (v·a)²-cos²α|v|² = 0
            //------------------------------
            float vDotA = dot(v, coneAxis);
            //------------------------------
            // Only highlight forward cone
            //------------------------------
            if (vDotA > 0.0)
            {
                float coneVal = vDotA * vDotA - cos2 * dot(v, v);
                //------------------------------
                // Linearize by dividing by
                // gradient magnitude (~2*|v|)
                //------------------------------
                proximity = abs(coneVal) / (2.0 * length(v));
            }
            else
            {
                proximity = 10.0;
            }
        }
        else
        {
            //------------------------------
            // On cone — distance to sphere
            //------------------------------
            float r = length(v);
            proximity = abs(r - sphereRadius);
        }

        float glow = smoothstep(lineWidth, 0.0, proximity);

        litColor = mix(litColor, highlightColor, glow * 0.9);
        alpha = max(alpha, glow * 0.85);

        float contrib = alpha * (1.0 - alphaAccum);
        accum += litColor * contrib;
        alphaAccum += contrib;
    }

    //---------------------------------------------
    // Background
    //---------------------------------------------
    float grad = 0.08 + 0.06 * in.uv.y;
    float3 bg = float3(grad, grad, grad * 1.2);
    accum += bg * (1.0 - alphaAccum);

    return float4(accum, 1.0);
}
//------------------------------------------------------------------------------
