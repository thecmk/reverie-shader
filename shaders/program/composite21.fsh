#include "/lib/all_the_libs.glsl"

noperspective in vec2 texcoord;

/* RENDERTARGETS:0 */
layout(location = 0) out vec4 Color;

void main() {
    Color = texture(colortex0, texcoord);

    Color.rgb *= 1 / (dataBuf.AvgLum * 9.6) * EXPOSURE_MULT;
    
    #ifndef HDR_ENABLED
        Color.rgb = apply_tonemap(Color.rgb);
    #endif

    #if (TONEMAP_OPERATOR != 1 && TONEMAP_OPERATOR != 3) || (defined HDR_ENABLED)
        Color.rgb = Color.rgb * REC2020_REC709;
    #endif

    #ifdef HDR_ENABLED
        Color.rgb = reinhard_odd(Color.rgb);
    #endif

    #ifdef LUT
        Color.rgb = decode_lut(Color.rgb, gl_FragCoord.xy);
    #endif
}
