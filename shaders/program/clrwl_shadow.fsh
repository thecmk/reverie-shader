#include "/lib/all_the_libs.glsl"
#include "/generic/water.glsl"
in vec2 texcoord;


#ifdef RSM
    /* RENDERTARGETS:0,1 */
#else
    /* RENDERTARGETS:0 */
#endif
layout(location = 0) out vec4 Color;
#ifdef RSM
    layout(location = 1) out vec4 ShadowNormal;
#endif

void main() {
    Color = texture(gtexture, texcoord);
    vec2 lmcoord;
    float ao;
    vec4 overlayColor;

    clrwl_computeFragment(Color, Color, lmcoord, ao, overlayColor);
    Color.a = 1;

    Color.rgb = srgb_rec2020(Color.rgb);

    #ifdef RSM
        ShadowNormal.rg = encodeUnitVector(clrwl_vertexNormal) * 0.5 + 0.5;
    #endif
}
