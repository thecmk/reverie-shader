float cloud_shadows(vec3 WorldPos) {
    #ifndef DIMENSION_OVERWORLD
        return 1;
    #endif
    
    vec3 CloudSamplePos = WorldPos;
    if (CloudSamplePos.y < CLOUD_LOWER_PLANE) {
        CloudSamplePos = intersectRayWithPlane(CloudSamplePos, view_player(sLightPosN, false), CLOUD_UPPER_PLANE);
        if(CloudSamplePos == vec3(0))
            return 0;
        CloudSamplePos += WorldPos;
    } 
    else if(CloudSamplePos.y > CLOUD_UPPER_PLANE) {
        return 1;
    }

    float CloudCoverage = noise_clouds_base_simple(CloudSamplePos);
    CloudCoverage = max(0, CloudCoverage - 0.06); // Account for the noise being carved out

    CloudCoverage = mix(exp2(-cloudCoverageVl), CloudCoverage, linstep(0.2, 0.25, sin(sunAngle * TAU))); // No shadows in the morning because it looks weird

    return 1 - CloudCoverage;
}

vec3 get_shadow_transparent(vec3 SampleCoords, vec3 ShadowPosUndistorted, out float IsWater) {
    float Depth1 = texture(shadowtex1HW, SampleCoords).x;
    IsWater = 0;
    if (Depth1 < 0.001) {
        return vec3(Depth1);
    }
    float Depth = texture(shadowtex0HW, SampleCoords).x;
    if (Depth < 1) {
        vec4 ShadowCol = texture(shadowcolor0, SampleCoords.xy);

        ShadowCol.rgb = mix(vec3(1), ShadowCol.rgb, ShadowCol.a * (1 - Depth));
        IsWater = texture(shadowcolor2, SampleCoords.xy).r * step(Depth, 0.0001);
        return ShadowCol.rgb * Depth1;
    }
    return vec3(Depth1);
}

vec3 pcf(float PenumbraSize, mat2 RotationOffset, vec3 ShadowPosUndistorted, out float IsWater) {
    const int SAMPLE_COUNT = 12;

    PenumbraSize *= shadowTexSize;

    vec3 ShadowColorFinal = vec3(0);
    IsWater = 0;
    for (int i = 0; i < SAMPLE_COUNT; i++) {
        vec2 OffsetP = (RotationOffset * vogel_sample(i, SAMPLE_COUNT)) * PenumbraSize;
        vec3 ShadowPosD = ShadowPosUndistorted + vec3(OffsetP, 0);
        ShadowPosD = distort(ShadowPosD);

        ShadowPosD = ShadowPosD * 0.5 + 0.5; //convert from shadow ndc space to shadow screen space.
        float _IsWaterLocal;
        ShadowColorFinal += get_shadow_transparent(ShadowPosD, ShadowPosUndistorted, _IsWaterLocal);
        IsWater += _IsWaterLocal;
    }
    IsWater /= SAMPLE_COUNT;
    return ShadowColorFinal / SAMPLE_COUNT;
}

float pcss(vec3 ShadowPosUndistorted, mat2 RotationOffset, bool DoSSS, out float BlockerDSSS) {
    float ReceiverD = ShadowPosUndistorted.z * 0.2 * 0.5 + 0.5;
    float BlockerD = 0, Hits = 0;

    float MaxRadius = 5 * SHADOW_FILTER_SIZE;
    MaxRadius *= DoSSS ? 7 : 1;

    for (int i = 0; i < 8; i++) {
        vec2 OffsetP = (RotationOffset * vogel_sample(i, 8)) * MaxRadius * shadowTexSize;
        vec2 ShadowPosD = ShadowPosUndistorted.xy + OffsetP;
        ShadowPosD = distort(vec3(ShadowPosD, 0)).xy;
        ShadowPosD = ShadowPosD * 0.5 + 0.5;

        float Sample = texture(shadowtex0, ShadowPosD).x;
        if (Sample < ReceiverD) {
            BlockerD += ReceiverD - Sample;
            Hits++;
        }
    }
    BlockerDSSS = BlockerD * far;
    if (Hits == 0) {
        return MaxRadius; // Prevent funny business
    }
    BlockerD /= Hits;
    return min(BlockerD * far + 0.5, MaxRadius);
}

// Used in vl
float get_shadow_unfiltered(vec3 PlayerPos, vec3 ShadowPos) {
    #ifdef DIMENSION_NETHER
    return 0.0;
    #endif

    float Fade = shadow_fade(PlayerPos, shadowDistanceDH);
    if(Fade > 0.99) return eyeBrightnessSmooth.y / 240.0;

    float ShadowFinal = step(1e-4, texture(shadowtex1, ShadowPos.xy).x - ShadowPos.z);
    ShadowFinal = mix(ShadowFinal, eyeBrightnessSmooth.y / 240.0, Fade);
    return ShadowFinal;
}

float get_shadow_unfiltered(vec3 PlayerPos, vec3 FlatNormal, float Skylight) {
    #ifdef DIMENSION_NETHER
    return 0.0;
    #endif

    vec3 bias = compute_bias(PlayerPos + gbufferModelViewInverse[3].xyz, view_player(FlatNormal, false), dot(FlatNormal, sLightPosN), Skylight);
    vec3 ShadowPosUndistorted = player_shadow(PlayerPos + bias);
    vec3 ShadowPos = distort(ShadowPosUndistorted);
    ShadowPos = ShadowPos * 0.5 + 0.5;

    return get_shadow_unfiltered(PlayerPos, ShadowPos) * cloud_shadows(PlayerPos + cameraPosition);
}

float get_shadow_screenspace(vec3 ViewPos, bool IsDH, vec3 FlatNormal, float Dither) {
    const int STEP_COUNT = 12;

    vec3 ScreenPos = view_screen(ViewPos, IsDH, true);
    vec3 Step = (view_screen(ViewPos + sLightPosN * 24, IsDH, true) - ScreenPos) / exp2(STEP_COUNT * 0.66 - 2);

    float Shadow = 1;
    for(float i = Dither; i < STEP_COUNT+1; i++) {
        vec3 ScreenPosC = ScreenPos + Step * exp2(i * 0.66 - 2);
        if(clamp(ScreenPosC, 0, 1) != ScreenPosC) break;
        bool IsDHReal;
        float RealDepth = get_depth(ScreenPosC.xy, IsDHReal);
        if(RealDepth < 0.56) break;
        float Diff = l_depth(ScreenPosC.z, IsDH) - l_depth(RealDepth, IsDHReal);
        
        Shadow *= 1 - step(0, Diff) * (1 - linstep(10, 15, abs(Diff)));
    }
    return Shadow;
}

vec3 get_shadow(vec3 PlayerPos, vec3 ViewPos, bool IsDH, vec3 FlatNormal, float Skylight, bool DoSSS, out float BlockerDist, out float Fade, out float CloudShadow, vec2 FragCoord) {
    BlockerDist = 0;
    #ifdef DIMENSION_NETHER
    return vec3(0);
    #endif

    if (dot(sLightPosN, FlatNormal) <= 0 && !DoSSS) return vec3(0);

    vec3 ShadowFinal = vec3(1);
    #ifdef CLOUDS
        CloudShadow = pow4(cloud_shadows(PlayerPos + cameraPosition));
        ShadowFinal *= CloudShadow;
    #else
        CloudShadow = 1;
    #endif

    float Dither = dither(FragCoord, true) * TAU;

    vec3 bias = compute_bias(PlayerPos + gbufferModelViewInverse[3].xyz, view_player(FlatNormal, false), dot(FlatNormal, sLightPosN), Skylight);
    vec3 SSSbias = DoSSS ? bias * 0.05 : bias;

    #ifdef SCREENSPACE_SHADOWS_FALLBACK
    float FadeSS = shadow_fade(PlayerPos, shadowDistanceDH - 16);
        if(FadeSS > 1e-6) {
            float ShadowScreen = get_shadow_screenspace(player_view(PlayerPos + SSSbias, IsDH), IsDH, FlatNormal, Dither);
            #ifdef DIMENSION_OVERWORLD
                ShadowScreen *= Skylight; // Fix light leaks outside the shadow map
            #endif
            ShadowFinal *= mix(1, ShadowScreen, FadeSS);
        }
    #endif

    Fade = shadow_fade(PlayerPos, shadowDistanceDH);
    if(Fade > 1 - 1e-6) {
        return ShadowFinal;
    }

    
    mat2 RotationOffset = rotation_mat(Dither);

    float PenumbraSize;
    #if SHADOW_FILTER == 2
        PenumbraSize = pcss(player_shadow(PlayerPos), RotationOffset, DoSSS, BlockerDist);
    #else
        PenumbraSize = SHADOW_FILTER_SIZE;
    #endif

    #if SHADOW_FILTER != 2
        PenumbraSize *= DoSSS ? 10 : 1;
        bias = SSSbias;
    #endif
    vec3 ShadowPosUndistorted = player_shadow(PlayerPos + bias);

    vec3 ShadowTransparent; float _IsWater;
    #if SHADOW_FILTER != 0
        ShadowTransparent = pcf(PenumbraSize, RotationOffset, ShadowPosUndistorted, _IsWater);
    #else
        vec3 ShadowPos = distort(ShadowPosUndistorted);
        ShadowPos = ShadowPos * 0.5 + 0.5;
        ShadowTransparent = get_shadow_transparent(ShadowPos, ShadowPosUndistorted, _IsWater);
    #endif

    if(_IsWater > 0.001) {
        float Caustics = get_water_caustics(PlayerPos);
        ShadowTransparent *= mix(1, Caustics, _IsWater);
    }

    ShadowFinal *= mix(ShadowTransparent, vec3(1), Fade);

    return ShadowFinal;
}
