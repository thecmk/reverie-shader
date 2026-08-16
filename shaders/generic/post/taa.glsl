// https://discord.com/channels/237199950235041794/525510804494221312/955458285367066654
vec4 clipAABB(vec4 prevColor, vec4 minColor, vec4 maxColor) {
    vec4 pClip = 0.5 * (maxColor + minColor); // Center
    vec4 eClip = 0.5 * (maxColor - minColor); // Size

    vec4 vClip = prevColor - pClip;
    vec4 aUnit = abs(vClip / eClip);
    float denom = max(aUnit.x, max(aUnit.y, aUnit.z));

    return denom > 1.0 ? pClip + vClip / denom : prevColor;
}

vec4 neighbourhoodClipping(sampler2D currTex, vec4 CurrentColor, vec4 prevColor, out vec4 maxColor, ivec2 FragCoord) {
    vec4 minColor = CurrentColor;
    maxColor = CurrentColor;

    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            if (x == y && x == 0) continue;
            vec4 color = texelFetch2D(currTex, ivec2(FragCoord + vec2(x, y)), 0);
            minColor = min(minColor, color);
            maxColor = max(maxColor, color);
        }
    }
    return clipAABB(prevColor, minColor, maxColor);
}

vec3 get_closest_depth(ivec2 FragCoord, vec2 Texcoord, out bool IsDH) {
    vec3 MinDepth = vec3(FragCoord, get_depth_solid(Texcoord, IsDH));
    for (int i = -2; i <= 2; i += 4) {
        for (int j = -2; j <= 2; j += 4) {
            ivec2 OffsetCoords = FragCoord + ivec2(i, j);
            float NewDepth = texelFetch(depthtex1, OffsetCoords, 0).x;
            if (NewDepth < MinDepth.z) MinDepth = vec3(OffsetCoords, NewDepth);
        }
    }
    MinDepth.xy /= resolution;
    return vec3(MinDepth);
}

vec3 TAA(vec3 Color, ivec2 FragCoord, vec2 Texcoord) {
    bool IsDH;
    vec3 ClosestSample = get_closest_depth(FragCoord, Texcoord, IsDH);
    vec2 PrevCoord = Texcoord + toPrevScreenPos(ClosestSample.xy, ClosestSample.z, IsDH, false).xy - ClosestSample.xy;

    if (clamp(PrevCoord + resolutionInv, 0, 1) != PrevCoord + resolutionInv)
        return Color;

    vec3 PrevColor = texture_catmullrom_fast(colortex4, PrevCoord).rgb;
    if (PrevColor == vec3(0) || any(isnan(PrevColor))) return Color;

    vec4 ClippingMaxColor;
    vec3 ClampedColor = neighbourhoodClipping(colortex0, vec4(Color, 1), vec4(PrevColor, 1), ClippingMaxColor, FragCoord).rgb;

    #if AA_MODE != 2
    float blendFactor = 0.7 + 0.1 * exp(-length((PrevCoord - Texcoord) * resolution));
    #else
    float blendFactor = 0.9;
    #endif

    // Jessie's offcenter rejection (reduce ghosting)
    vec2 pixelOffset = 1.0 - abs(2.0 * fract(PrevCoord * resolution) - 1.0);
    float OffcenterRejection = sqrt(pixelOffset.x * pixelOffset.y) * 0.15 + 0.85;
    blendFactor *= OffcenterRejection;

    #if AA_MODE == 2
    // Flicker reduction
    blendFactor = clamp(blendFactor + pow2(get_luminance((PrevColor - Color) / ClippingMaxColor.rgb)) * 0.15, 0, 1);
    #endif

    Color = mix(Color, ClampedColor, blendFactor);
    return Color;
}

// Temporal component for SMAA T2x
vec3 T2x(vec3 Color, ivec2 FragCoord, vec2 Texcoord) {
    bool IsDH;
    float Depth = get_depth_solid(Texcoord, IsDH);
    // if(Depth < 0.56) return Color;
    vec2 PrevCoord = toPrevScreenPos(Texcoord, Depth, IsDH, false).xy;

    if (clamp(PrevCoord, 0, 1) != PrevCoord)
        return Color;

    vec3 PrevColor = textureNicest(colortex9, PrevCoord).rgb;
    if (PrevColor == vec3(0)) return Color;

    float DepthPrev = texture(colortex8, PrevCoord).r;

    vec2 velocity = (Texcoord - PrevCoord.xy) * resolution;
    float blendFactor = 0.5 * max(0, 1 - abs(l_depth(DepthPrev, IsDH) - l_depth(quantize_16bit(Depth)))) * exp(-len2(velocity));

    Color = mix(Color, PrevColor, blendFactor);
    return Color;
}

vec4 temporal_upscale_clouds(vec3 ScreenPos, bool IsDH, ivec2 FragCoord, vec3 PlayerPos, vec3 PlayerPosN, sampler2D Sampler, out float DistToCloudCurrent) {
    const int VOLUMETRICS_RES_INV = int(1 / VOLUMETRICS_RES);
    DistToCloudCurrent = texelFetch(image1Sampler, ivec2(FragCoord * VOLUMETRICS_RES), 0).r * farLod * 4;
    float DepthToCloud = view_screen(player_view(PlayerPosN * DistToCloudCurrent, IsDH), IsDH, false).z;
    DepthToCloud = min(1, DepthToCloud); // It can sometimes go over 1 with DH (maybe float imprecision?)

    // Prevent clouds from clipping in front of objects
    if(DepthToCloud > ScreenPos.z && ScreenPos.z < 1) return vec4(0, 0, 0, 1);

    vec2 PrevCoord = toPrevScreenPos(ScreenPos.xy, DepthToCloud, IsDH, false).xy;
    ivec2 LastUpdatePos = FragCoord - FragCoord % VOLUMETRICS_RES_INV + ivec2(frameCounter * VOLUMETRICS_RES, frameCounter) % VOLUMETRICS_RES_INV;

    // Sample last updated pos when there's no other data available 
    bool WasOffScreen = clamp(PrevCoord, 0, 1) != PrevCoord;
    float DepthPrev = min_depth_4x4(PrevCoord, colortex8);
    bool WasOccluded = DepthPrev < DepthToCloud;
    if (WasOffScreen || WasOccluded || (ScreenPos.z < 0.56)) {
        vec4 Color = texture(image0Sampler, ScreenPos.xy * VOLUMETRICS_RES);
        Color.a = 1 - Color.a;
        Color = max(Color, 0);
        return Color;
    }
    
    // Only update when there's new samples
    bool IsSampleNotCurrent = any(notEqual(FragCoord, LastUpdatePos));

    vec4 PrevColor = texture_bicubic(Sampler, PrevCoord);
    vec4 Color = texelFetch(image0Sampler, ivec2(gl_FragCoord.xy * VOLUMETRICS_RES), 0);
    // Transmittance should default to 1
    Color.a = 1 - Color.a;
    Color = max(Color, 0);

    float blendFactor = float(IsSampleNotCurrent);

    vec2 pixelOffset = 1.0 - abs(2.0 * fract(PrevCoord * resolution) - 1.0);
    float OffcenterRejection = sqrt(pixelOffset.x * pixelOffset.y) * 0.2 + 0.8;
    blendFactor *= OffcenterRejection;

    return mix(Color, PrevColor, blendFactor);
}

vec4 temporal_upscale_vl(vec3 ScreenPos, bool IsDH, ivec2 FragCoord, vec3 PlayerPos) {
    const int VOLUMETRICS_RES_INV = int(1 / VOLUMETRICS_RES);

    vec2 PrevCoord = toPrevScreenPos(ScreenPos.xy, ScreenPos.z, IsDH, true).xy;

    // Sample last updated pos when there's no other data available 
    bool WasOffScreen = clamp(PrevCoord, 0, 1) != PrevCoord;

    if(WasOffScreen || (ScreenPos.z < 0.56)) {
        vec4 Color = texture(image2Sampler, ScreenPos.xy * VOLUMETRICS_RES);
        Color.a = 1 - Color.a;
        Color = max(Color, 0);
        return Color;
    }

    vec2 FragCoordInPrevPass = FragCoord - FragCoord % VOLUMETRICS_RES_INV + 0.5 * VOLUMETRICS_RES_INV;
    float DepthL = l_depth(ScreenPos.z, IsDH);
    float TotalFactor = 0; vec4 Color = vec4(0);
    for(int i = -1; i <= 1; i++) {
        for(int j = -1; j <= 1; j++) {
            bool IsDHInPrevPass;
            vec2 OffsetFragPos = FragCoordInPrevPass + vec2(i, j) * VOLUMETRICS_RES_INV;
            float DepthUsedInPrevPass = get_depth(OffsetFragPos * resolutionInv, IsDHInPrevPass);
            DepthUsedInPrevPass = l_depth(DepthUsedInPrevPass, IsDHInPrevPass);
            // Reduces pixelation
            float DistFromCenter = 1 - distance(FragCoordInPrevPass + (fract(ScreenPos.xy * resolution * VOLUMETRICS_RES) - 0.5) * VOLUMETRICS_RES_INV, OffsetFragPos) * VOLUMETRICS_RES / sqrt(2) * 0.66;
            float DepthDiff = abs(DepthL - DepthUsedInPrevPass) * 0.33;
            DepthDiff *= IsDHInPrevPass ? 10 : 1; // I should use dhNearPlane to linearize depth, but it seems to be broken
            float Factor = max(1e-6, DistFromCenter - min(1, DepthDiff));
            Color += texelFetch(image2Sampler, ivec2(OffsetFragPos * VOLUMETRICS_RES), 0) * Factor;
            TotalFactor += Factor;
        }
    }
    Color /= TotalFactor;
    Color.a = 1 - Color.a;
    Color = max(Color, 0);

    vec4 PrevColor = texture(colortex7, PrevCoord);
    float PrevDepth = texture(colortex8, PrevCoord).r;

    float DepthQuantized = l_depth(quantize_16bit(ScreenPos.z), IsDH);
    float blendFactor = 0.92 * exp(-abs(l_depth(PrevDepth, IsDH) - DepthQuantized) * 0.5);

    vec2 pixelOffset = 1.0 - abs(2.0 * fract(PrevCoord * resolution) - 1.0);
    float OffcenterRejection = sqrt(pixelOffset.x * pixelOffset.y) * 0.1 + 0.9;
    blendFactor *= OffcenterRejection;

    
    return mix(Color, PrevColor, blendFactor);
}

// https://blog.demofox.org/2016/02/19/normalized-vector-interpolation-tldr/
vec3 slerp(vec3 start, vec3 end, float percent) {
     // Dot product - the cosine of the angle between 2 vectors.
     float dot = dot(start, end);     
     // Clamp it to be in the range of Acos()
     // This may be unnecessary, but floating point
     // precision can be a fickle mistress.
     dot = clamp(dot, -1.0, 1.0);
     // Acos(dot) returns the angle between start and end,
     // And multiplying that by percent returns the angle between
     // start and the final result.
     float theta = acos(dot)*percent;
     vec3 RelativeVec = normalize(end - start*dot); // Orthonormal basis
     // The final result.
     return ((start*cos(theta)) + (RelativeVec*sin(theta)));
}

vec4 temporal_denoise_gi(vec4 Color, vec3 ScreenPos, vec2 FragCoord, bool IsDH, vec2 BentNormalCurrent, out vec4 GIUpscaleData) {
    vec2 PrevCoord = toPrevScreenPos(ScreenPos.xy, ScreenPos.z, IsDH, true).xy;

    float PrevDepth = texture(colortex8, PrevCoord).r;
    float DepthQuantized = l_depth(quantize_16bit(ScreenPos.z), IsDH);
    if(clamp(PrevCoord, 0, 1) != PrevCoord) {
        GIUpscaleData.y = 1;
        return Color;
    }

    vec4 PrevColor = texture(colortex13, PrevCoord * INDIRECT_RES_SCALE);

    vec4 ClippingMaxColor;
    vec4 ClampedColor = neighbourhoodClipping(colortex3, Color, PrevColor, ClippingMaxColor, ivec2(FragCoord));

    vec4 GIData = texture(colortex14, PrevCoord * INDIRECT_RES_SCALE);
    vec2 PrevBentNormal = GIData.zw;

    float PixelAge = min(64, float(floatBitsToUint(GIData.y)));

    PixelAge *= max(0, 1 - abs(l_depth(PrevDepth, IsDH) - DepthQuantized));

    vec2 pixelOffset = 1.0 - abs(2.0 * fract(PrevCoord * resolution) - 1.0);
    float OffcenterRejection = sqrt(pixelOffset.x * pixelOffset.y) * 0.15 + 0.85;
    PixelAge *= OffcenterRejection;
    
    PixelAge += 1;
    GIData.y = uintBitsToFloat(uint(PixelAge));

    float blendFactor = 1 - 1.0 / PixelAge;

    vec3 BNC = decodeUnitVector(BentNormalCurrent * 2 - 1);
    vec3 BNP = decodeUnitVector(PrevBentNormal * 2 - 1);

    vec3 BNF = slerp(BNC, BNP, 0.9);
    GIUpscaleData.zw = encodeUnitVector(BNF) * 0.5 + 0.5;

    return mix(Color, ClampedColor, blendFactor);
}