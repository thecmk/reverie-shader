#include "/lib/all_the_libs.glsl"
// Clouds

#include "/generic/water.glsl"
#include "/generic/sky.glsl"
#include "/generic/clouds.glsl"


#if (defined DIMENSION_OVERWORLD) && (defined CLOUDS)
const vec2 workGroupsRender = vec2(VOLUMETRICS_RES, VOLUMETRICS_RES);
#else
const vec2 workGroupsRender = vec2(0, 0);
#endif

layout(local_size_x = 16, local_size_y = 16) in;
void main() {
    const int VOLUMETRICS_RES_INV = int(1 / VOLUMETRICS_RES);

    vec2 FragPos = gl_GlobalInvocationID.xy * VOLUMETRICS_RES_INV + ivec2(frameCounter * VOLUMETRICS_RES, frameCounter) % VOLUMETRICS_RES_INV;
    vec2 texcoord = (FragPos + 0.5) * resolutionInv;
    bool IsDH;
    float Depth = max_depth_4x4(texcoord, IsDH);
    if(Depth > 0.56) {
        Positions Pos = get_positions(texcoord, Depth, IsDH, true);

        float _DepthCloud = 1e8;
        vec4 CloudData = get_clouds(Pos.Player, Pos.PlayerN, 32, cameraPosition, true, FragPos, Depth, _DepthCloud);

        if(_DepthCloud < 1e8) {
            _DepthCloud = _DepthCloud / farLod / 4;
        }

        // Transmittance should default to 1
        CloudData.a = 1 - CloudData.a;
        imageStore(image0, ivec2(gl_GlobalInvocationID.xy), CloudData);
        imageStore(image1, ivec2(gl_GlobalInvocationID.xy), vec4(_DepthCloud, 0, 0, 0));
    } else {
        imageStore(image0, ivec2(gl_GlobalInvocationID.xy), vec4(0,0,0,0));
        imageStore(image1, ivec2(gl_GlobalInvocationID.xy), vec4(1e8, 0,0,0));
    }
}
