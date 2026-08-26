#define DEFERRED

#include "/lib/all_the_libs.glsl"

in vec2 texcoord;
flat in vec3 LightColorDirect; // This needs to be initialized in the vertex stage of the pass

#include "/generic/gtao.glsl"
#include "/generic/water.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/shadow/rsm.glsl"
#include "/generic/post/taa.glsl"


/* RENDERTARGETS:3,5 */
layout(location = 0) out vec4 GIDenoise;
layout(location = 1) out vec4 BentNormalOut;


void main() {
    bool IsDH;
    vec2 Texcoord = ((floor(gl_FragCoord.xy) + 0.5) / INDIRECT_RES_SCALE - 0.5) * resolutionInv; // Lower left texel
    float Depth = get_depth(Texcoord, IsDH);
    
    BentNormalOut = texture(colortex5, Texcoord);
    if ((Depth > 0.56) && Depth < 1) {
        Positions Pos = get_positions(Texcoord, Depth, IsDH, true);
        mat2x4 GbufferData = mat2x4(texture(colortex1, Texcoord), texture(colortex2, Texcoord));
        MaterialProperties Mat = unpack_material(GbufferData, IsDH);

        float Gtao = 1;
        vec3 BentNormal;
        #if AO_MODE == 2
            Gtao = gtao(Pos, IsDH, Mat.Normal, BentNormal);
            BentNormalOut.zw = encodeUnitVector(view_player(BentNormal, IsDH)) * 0.5 + 0.5;
        #endif

        vec3 Rsm = vec3(0);
        #ifdef RSM
            #ifndef DIMENSION_NETHER
                Rsm = rsm(Pos.Player, Mat.Normal, LightColorDirect);
            #endif
        #endif
        
        GIDenoise = vec4(Rsm.rgb, 1 - Gtao);
    }
    else {
        GIDenoise = vec4(0, 0, 0, 0);
    }
}