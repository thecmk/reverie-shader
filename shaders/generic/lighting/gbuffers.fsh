#include "/generic/weather.glsl"

#ifndef VOXY_TERRAIN
in Data {
    vec2 lmcoord;
    vec2 texcoord;
    vec4 glcolor;
    flat float Id;
    flat mat3 TBN;
    vec3 ViewPos;
    float chunkFade;
    #if (defined PBR_POM) && (defined GBUFFERS_TERRAIN)
        flat vec2 AtlasScale;
        flat vec2 AtlasOffset;
    #endif
} DataIn;
#else
    struct Data {
        vec2 lmcoord;
        vec2 texcoord;
        vec4 glcolor;
        float Id;
        mat3 TBN;
        vec3 ViewPos;
        #if (defined PBR_POM) && (defined GBUFFERS_TERRAIN)
            vec2 AtlasScale;
            vec2 AtlasOffset;
        #endif
        float chunkFade;
    } DataIn;
    void map_voxy_param_to_varying(VoxyFragmentParameters param) {
        DataIn.texcoord = param.uv;
        DataIn.lmcoord = param.lightMap;
        DataIn.lmcoord = max(DataIn.lmcoord * 1.06667 - 0.0648, 0);
        DataIn.Id = (param.customId - 10000.0);
        DataIn.glcolor = param.tinting;
        DataIn.ViewPos = screen_view(vec3(DataIn.texcoord, gl_FragCoord.z), true, false);
        // from Cortex
        vec3 normal = vec3(
                        uint((param.face >> 1) == 2),
                        uint((param.face >> 1) == 0),
                        uint((param.face >> 1) == 1)
                    ) *
            (float(int(param.face) & 1) * 2.0 - 1.0);
        DataIn.TBN = tbn_normal(player_view(normal, true));
        DataIn.chunkFade = 1;
    }
#endif
vec2 dCoordx = dFdx(DataIn.texcoord), dCoordy = dFdy(DataIn.texcoord);

/* RENDERTARGETS:1,2 */
layout(location = 0) out vec4 buf1;
layout(location = 1) out vec4 buf2;

#if (defined PBR_POM) && (defined GBUFFERS_TERRAIN)
    vec2 to_local_pos(vec2 texcoord) {
        return (texcoord - DataIn.AtlasOffset) / DataIn.AtlasScale; 
    }

    vec2 from_local_pos(vec2 LocalPos) {
        return fract(LocalPos) * DataIn.AtlasScale + DataIn.AtlasOffset;
    }

    // Code by @geforcelegend in #snippets
    mat3 get_tbn(out vec2 TexScale) {
        vec2 dCoordDX = dCoordx;
        vec2 dCoordDY = dCoordy;

        vec3 dPosDX = dFdx(DataIn.ViewPos);
        vec3 dPosDY = dFdy(DataIn.ViewPos);

        vec3 normal = cross(dPosDX, dPosDY);

        vec3 tangentHelper = dPosDY * dCoordDX.x - dPosDX * dCoordDY.x;
        vec3 tangent = cross(tangentHelper, normal) / dot(tangentHelper, tangentHelper);

        vec3 bitangentHelper = dPosDY * dCoordDX.y - dPosDX * dCoordDY.y;
        vec3 bitangent = cross(bitangentHelper, normal) / dot(bitangentHelper, bitangentHelper);

        float tangentLen = inversesqrt(dot(tangent, tangent));
        float bitangentLen = inversesqrt(dot(bitangent, bitangent));

        mat3 tbnMatrix = mat3(tangent * tangentLen, bitangent * bitangentLen, normalize(normal));
        TexScale = vec2(tangentLen, bitangentLen);
        return tbnMatrix;
    }

    vec2 pom() {
        vec2 _TexScale;
        mat3 TBN = get_tbn(_TexScale);
        
        // Distance fade
        float Dist = len2(DataIn.ViewPos);
        if(Dist > pow2(12)) return DataIn.texcoord;

        float Height = 1-textureGrad(normals, DataIn.texcoord, dCoordx, dCoordy).a;
        if(Height < 1/255.0) {
            return DataIn.texcoord;
        }

        int StepCount = POM_STEP_COUNT;


        vec3 TangentPos = normalize(DataIn.ViewPos * TBN);
        vec3 Offset = vec3(TangentPos.xy / -TangentPos.z * POM_MAX_DEPTH, 1) / StepCount;
        Offset.xy *= _TexScale / DataIn.AtlasScale;
        float Dither = dither(gl_FragCoord.xy, true);
        vec3 CurrentPos = vec3(to_local_pos(DataIn.texcoord) + Offset.xy * Dither, 0); 
        
        for(int i = 0; i < StepCount && Height - CurrentPos.z > 1./255.0; i++) {
            vec2 NewPos = from_local_pos(CurrentPos.xy);            
            Height = 1 - textureGrad(normals, NewPos, dCoordx, dCoordy).a;
            CurrentPos += Offset;
        }
        
        // Need to move back one here
        CurrentPos -= Offset;
        return from_local_pos(CurrentPos.xy);
    }
#endif

#ifdef VOXY_TERRAIN
    void init_frag(VoxyFragmentParameters param) {
#else
    void init_frag() {
#endif
    #if (defined PBR_POM) && (defined GBUFFERS_TERRAIN)
        vec2 texcoord = pom();
    #else
        vec2 texcoord = DataIn.texcoord;
    #endif
    vec4 glcolor = get_seasons_color(DataIn.glcolor);
    #ifdef VOXY_TERRAIN
        vec4 Albedo = glcolor * param.sampledColour;
    #else
        #ifdef PBR_POM
        vec4 Albedo = vec4(glcolor.rgb, 1) * textureGrad(gtexture, texcoord, dCoordx, dCoordy);
        #else
        vec4 Albedo = vec4(glcolor.rgb, 1) * texture(gtexture, texcoord);
        #endif
    #endif
    if (Albedo.a < 0.1) {
        discard;
    }

    vec3 ScreenPos = gl_FragCoord.xyz * vec3(resolutionInv, 1);
    #if (defined DH_TERRAIN) || (defined VOXY_TERRAIN)
        bool IsDH = true;
    #else
        bool IsDH = false;
    #endif
    Positions Pos = get_positions(ScreenPos.xy, ScreenPos.z, IsDH, false);
    #if (defined DISTANT_HORIZONS) && (!defined VOXY)
        float Dither = bayer8(gl_FragCoord.xy);
        if (transition_to_dh(Pos.Player, Dither)) {
            discard;
        }
        #if (defined DH_NOISE) && (defined DH_TERRAIN)
            Albedo.rgb = dh_noise(Pos.Player, Albedo.rgb);
        #endif
    #endif

    Albedo.rgb *= pow(glcolor.a, 1 / 2.2);

    #ifdef GBUFFERS_ENTITIES
    Albedo.rgb = mix(Albedo.rgb, entityColor.rgb, entityColor.a);
    #endif

    MaterialProperties Mat;
    Mat.Albedo = Albedo.rgb;

    vec3 PackNormal = get_normal(texcoord, dCoordx, dCoordy);
    Mat.Normal = DataIn.TBN * PackNormal;

    Mat.FlatNormal = DataIn.TBN[2];
    
    #if (defined IRIS_FEATURE_FADE_VARIABLE) && !(defined DH_TERRAIN)
        Mat.chunkFade = DataIn.chunkFade;
    #else
        Mat.chunkFade = 1;
    #endif

    Mat.Lightmap = DataIn.lmcoord;
    if(Mat.Lightmap.y > 1 / 255.0)
        Mat.Lightmap.y += bayer8(gl_FragCoord.xy) / 255.0;

    #ifdef GBUFFERS_SPIDEREYES
        Mat.Lightmap.y = 0; // Make spider eyes not affected by skylight
    #endif

    Mat.SSS = get_sss(texcoord);
    Mat.Emissiveness = get_emissiveness(texcoord);

    Mat.Smoothness = texture(specular, texcoord).r;
    Mat.F0 = texture(specular, texcoord).g;
    Mat.Id = DataIn.Id;

    buf1 = pack_material_buf1(Mat, false);
    buf2 = pack_material_buf2(Mat, false);
}
