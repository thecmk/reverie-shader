#include "/lib/all_the_libs.glsl"

noperspective in vec2 texcoord;

/* RENDERTARGETS:0 */
layout(location = 0) out vec4 Color;

void main() {
    Color = texture(colortex0, texcoord);

    Color.rgb *= 1 / (dataBuf.AvgLum * 9.6) * EXPOSURE_MULT;
    
    Color.rgb = apply_tonemap(Color.rgb);

    #if TONEMAP_OPERATOR != 1 && TONEMAP_OPERATOR != 3
        Color.rgb = Color.rgb * REC2020_REC709;
    #endif


    #ifdef LUT
        Color.rgb = decode_lut(Color.rgb, gl_FragCoord.xy);
    #endif
}
