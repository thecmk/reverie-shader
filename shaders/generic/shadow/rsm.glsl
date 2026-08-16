vec3 rsm(vec3 PlayerPos, vec3 Normal, vec3 LightColor) {
    if (isOutdoorsSmooth < 0.001) return vec3(0);
    if (isEyeInWater == 1) return vec3(0);

    float Fade = shadow_fade(PlayerPos, shadowDistanceDH);
    if(Fade > 0.99) return vec3(0);

    float CloudCoverage = cloud_shadows(PlayerPos + cameraPosition);
    if(CloudCoverage < 0.01) return vec3(0);

    vec3 ShadowPos = player_shadow(PlayerPos);

    vec3 ShadowNormal = mat3(shadowModelView) * (mat3(gbufferModelViewInverse) * Normal);
    vec3 Sum = vec3(0);

    vec2 Pos = gl_FragCoord.xy;
    float Dither = blue_noise(Pos, true).r * TAU;
    mat2 RotationMat = rotation_mat(Dither);
    
    for (int i = 1; i <= RSM_SAMPLE_COUNT; i++) {
        vec2 Offset = (RotationMat * vogel_sample(i, RSM_SAMPLE_COUNT));
        Offset = Offset * shadowTexSize * 64;
        
        Offset *= sign(dot(Offset, ShadowNormal.xy));

        vec3 OffsetPos = ShadowPos + vec3(Offset, 0);
        vec3 SamplePos = distort(OffsetPos) * 0.5 + 0.5;
        float RealDepth = texture(shadowtex1, SamplePos.xy).x;
        RealDepth = (RealDepth * 2 - 1) / 0.2;
        if (RealDepth < ShadowPos.z) continue;

        OffsetPos.z = RealDepth;

        float Dist = distance(OffsetPos, ShadowPos);
        float Flux = pow1_33_f(max(1 - Dist / (shadowTexSize * 64), 0));

        if (Flux < 0.0001) continue;

        vec3 SampleNormal = decodeUnitVector(texture(shadowcolor1, SamplePos.xy).rg * 2 - 1);

        vec3 RayDir = normalize(OffsetPos - ShadowPos);
        RayDir.z *= -1;
        Flux *= max(0, dot(RayDir, ShadowNormal.xyz));
        RayDir *= -1;
        Flux *= max(0, dot(RayDir, SampleNormal));

        if (Flux < 0.0001) continue;

        vec3 ShadowColor = texture(shadowcolor0, SamplePos.xy).rgb;
        
        Sum += ShadowColor * Flux;
    }
    vec3 Rsm = Sum * LightColor / RSM_SAMPLE_COUNT * isOutdoorsSmooth * CloudCoverage * (1 - Fade);
    
    return Rsm;
}

float[5] weights = float[5](0.13298, 0.12579, 0.0866, 0.05455, 0.03316);
vec4 gi_denoise(sampler2D Sampler, vec2 Texcoord, vec2 direction, float CurrentDepth, bool IsDH) {
    vec4 color = vec4(0);
    float TotalWeight = 0;
    float CurrentData = texture(colortex1, Texcoord, 0).w;
    CurrentDepth = l_depth(CurrentDepth, IsDH);
    vec3 CurrentNormal = decodeUnitVector(unpackUnorm2x8(CurrentData) * 2 - 1);

    const int BLUR_SIZE = 3;
    const float MAGIC_NUMBER = 2;

    for (int i = -BLUR_SIZE; i <= BLUR_SIZE; i++) {
        vec2 OffsetUV = Texcoord + i * direction * MAGIC_NUMBER * resolutionInv;
        vec4 OffsetColor = texture(Sampler, OffsetUV * INDIRECT_RES_SCALE, 0);

        float OffsetWeight = 1; //weights[abs(i)];
        
        bool IsOffsetDH;
        float OffsetDepth = get_depth(OffsetUV, IsOffsetDH);
        OffsetDepth = l_depth(OffsetDepth, IsOffsetDH);
        OffsetWeight *= pow4(clamp(1 - abs(CurrentDepth - OffsetDepth), 0, 1));

        float OffsetData = texture(colortex1, OffsetUV, 0).w;
        vec3 OffsetNormal = decodeUnitVector(unpackUnorm2x8(OffsetData) * 2 - 1);
        OffsetWeight *= pow4(max(dot(CurrentNormal, OffsetNormal), 0));

        color += OffsetColor * OffsetWeight;
        TotalWeight += OffsetWeight;
    }
    return color / TotalWeight;
}

vec3 sample_normal(vec2 FragCoord) {
    return decodeUnitVector(unpackUnorm2x8(texelFetch(colortex1, ivec2(FragCoord), 0).w) * 2 - 1);
}

vec4 gi_bilateral_upscale(vec2 FragCoord, vec3 CurrentNormal, float CurrentDepth, out vec2 BentNormal, bool IsDH) {
    FragCoord = floor(FragCoord);
    // return texelFetch(colortex13, ivec2(FragCoord * INDIRECT_RES_SCALE), 0);
    vec2 PrevCoord = ((floor(FragCoord * INDIRECT_RES_SCALE) + 0.25) / INDIRECT_RES_SCALE);
    CurrentNormal = view_player(CurrentNormal, IsDH);
    CurrentDepth = l_depth(CurrentDepth, IsDH);

    float TotalWeight = 0;
    vec4 GI = vec4(0); BentNormal = vec2(0);
    for(int i = -1; i <= 1; i++) {
        for(int j = -1; j <= 1; j++) {
            vec2 PrevCoordOffset = PrevCoord + vec2(i, j) / INDIRECT_RES_SCALE;

            float PrevDepth = texelFetch(depthtex0, ivec2(PrevCoordOffset), 0).r;
            PrevDepth = l_depth(PrevDepth, IsDH);
            float Weight = pow4(clamp(2 - abs(CurrentDepth - PrevDepth), 0, 1));
            
            vec3 PrevNormal = sample_normal(PrevCoordOffset);
            Weight *= pow4(max(0,dot(PrevNormal, CurrentNormal)));

            Weight *= max(0, 1 - distance(PrevCoordOffset, FragCoord) * INDIRECT_RES_SCALE * 0.66); // Reduce pixelation

            GI += texelFetch(colortex13, ivec2(FragCoord * INDIRECT_RES_SCALE + vec2(i, j)), 0) * Weight;
            BentNormal += texelFetch(colortex5, ivec2(FragCoord * INDIRECT_RES_SCALE), 0).zw * Weight;
            TotalWeight += Weight;
        }
    }
    BentNormal = texelFetch(colortex5, ivec2(FragCoord * INDIRECT_RES_SCALE), 0).zw;
    if(TotalWeight < 0.001) return vec4(0,0,0,0);
    return GI / TotalWeight;
}