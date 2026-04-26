#include "/generic/gtao.glsl"

vec3 filter_floodfill(sampler3D Sampler, vec3 PlayerPos, vec3 FragPos, vec3 Normal) {
    vec3 Pos = FragPos / voxelDistance / vec3(2, 1, 2); 
    vec3 C = texture(Sampler, Pos).rgb; // Center

    return C;
}

vec3 calc_lighting(Positions Pos, MaterialProperties Mat, bool IsDH, vec2 texcoord, bool IsHand, out vec4 ShadowBuf) {

    if (Mat.Id >= MATERIAL_TALL_PLANT_LOWER && Mat.Id <= MATERIAL_SHORT_PLANT) {
        Mat.Normal = gbufferModelView[1].xyz; // upDirection
    }
    float NdotL = dot(sLightPosN, Mat.Normal);

    Mat.Lightmap = pow4(Mat.Lightmap);
    Mat.Lightmap.x += Mat.Emissiveness * float(Mat.Emissiveness < 1);
    vec3 LMColor = TorchlightColor;
    #if (defined COLORED_LIGHTS) && (!defined DH_TERRAIN) && (!defined VOXY_TERRAIN)
        vec3 PlayerPosAbs = get_voxel_pos(Pos.Player) + view_player(Mat.Normal, false) * 0.065;

        if(is_in_voxel_range(PlayerPosAbs)) {
            vec3 VoxelData;
            if(frameCounter % 2 == 1) {
                VoxelData = filter_floodfill(voxelImgSampler_a, Pos.Player, PlayerPosAbs, Mat.Normal);
            } else {
                VoxelData = filter_floodfill(voxelImgSampler_b, Pos.Player, PlayerPosAbs, Mat.Normal);
            }
            VoxelData *= 12;

            float Fade = shadow_fade(Pos.Player, voxelDistance);
            LMColor = mix(VoxelData.rgb, LMColor, Fade);
        }
    #endif


    #ifndef GBUFFERS_TERRAIN
        // Prevents a strange rare lightleak
        NdotL *= Mat.Lightmap.y;
    #endif

    #ifdef DIMENSION_OVERWORLD
        #ifdef DEFERRED
            #ifdef SPATIAL_DENOISING
                vec4 GIDenoise;
                if(IsHand) {
                    GIDenoise = vec4(0, 0, 0, 0);
                } else {
                    GIDenoise = gi_denoise(colortex3, texcoord, vec2(0, 1), Pos.Screen.z, IsDH);
                }
            #endif
        #endif

        // Ambient lighting
        vec3 BentNormal = 
        #if AO_MODE == 2
            !IsHand ? Mat.BentNormal : 
        #endif
            Mat.Normal;
        float NangUp = dot(gbufferModelView[1].xyz, BentNormal) * 0.5 + 0.5;
        float NangL = -view_player(BentNormal, true).x * 0.5 + 0.5;
        vec3 SunA = texture(image0Sampler, (vec2(NangL, NangUp) * 15 * resolutionInv)).rgb; 

        // Ao
        #if AO_MODE == 2 && (defined DEFERRED)
            SunA *= 1 - GIDenoise.a;
        #elif AO_MODE == 1
            SunA *= 1 - ssao(Mat.Normal, Pos.View, IsDH);
        #endif

        if(lightningBoltPosition.w > 0) {
            float VdotLi = 1 - min(1, distance(lightningBoltPosition.xz, Pos.Player.xz) * 0.0025);
            vec3 LiBPN = normalize((player_view(lightningBoltPosition.xyz, false) - Pos.View));
            float NdotLi = max(0, dot(Mat.Normal, LiBPN)) * 0.8 + 0.2;
            SunA += vec3(1) * NdotLi * pow4(VdotLi);
        }
        
        SunA = mix(MinLight, SunA, Mat.Lightmap.y);
    #elif defined DIMENSION_NETHER
    // Fake lighting, to make things look less flat
        float NdotU = dot(Mat.Normal, gbufferModelView[1].xyz);
        vec3 FakeLavaLight = TorchlightColor * 0.05 * (-NdotU * 0.5 + 0.5);
        vec3 FakeAmbientLight = fogColor.rgb * 0.2 * (NdotU * 0.5 + 0.5);
        vec3 SunA = MinLight * 2 + FakeAmbientLight + FakeLavaLight;
    #else
        vec3 SunA = srgb_linear(vec3(0.2, 0.1, 0.15));
    #endif

    vec3 OutColor = Mat.Albedo * (SunA + LMColor * Mat.Lightmap.x);

    #if (defined RSM) && (defined DIMENSION_OVERWORLD) && (defined DEFERRED)
        OutColor.rgb += GIDenoise.rgb * Mat.Albedo;
    #endif

    float SSSS = Mat.SSS;
    if (Mat.SSS < 64.0 / 255.0 && Mat.Lightmap.y > 0.1) {
        if (Mat.Id == MATERIAL_SSS_WEAK) SSSS = SSS_STRENGTH_WEAK;
        else if (Mat.Id >= MATERIAL_SSS_STRONG && Mat.Id <= MATERIAL_LEAVES) SSSS = SSS_STRENGTH_STRONG;
        else SSSS = 0;
    }
    bool DoSSS = SSSS > 0;

    vec3 SunDirect = vec3(0);
    bool IsMetal, IsHardcodedMetal;
    vec3 Shadow = vec3(0);
    if (NdotL > 0 || DoSSS) {
        Shadow = get_shadow(Pos.Player, Pos.View, IsDH, Mat.FlatNormal, Mat.Lightmap.y, DoSSS, ivec2(gl_FragCoord.xy));

        if (Shadow != vec3(0)) {
            vec3 LightColor;
            if (sunAngle < 0.5)
                LightColor = dataBuf.SunColor;
            else
                LightColor = dataBuf.MoonColor;

            float LHeight = sin(sunAngle * TAU); // to_player_pos(sunPosN).y;
            LightColor *= smoothstep(0.0, 0.05, abs(LHeight));

            SunDirect = Mat.Albedo / PI * max(0.1, float(!IsMetal));
            SunDirect *= LightColor * max(NdotL, 0);

            if (DoSSS) {
                SSSS = (1 - SSSS) * 5;

                float SSS = exp(-SSSS * abs(NdotL));
                float Phase = max(ISOTROPIC_PHASE, cs_phase(dot(Pos.ViewN, sLightPosN), 0.6));
                SunDirect += Mat.Albedo.rgb * LightColor * SSS * Phase;
            }
        }
    }
    OutColor += SunDirect * Shadow;

    ShadowBuf.r = get_luminance(Shadow);
    ShadowBuf.gba = vec3(0);

    return OutColor * max(0., float(!IsMetal));
}
