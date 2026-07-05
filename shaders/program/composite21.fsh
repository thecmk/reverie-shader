#include "/lib/all_the_libs.glsl"

in vec2 texcoord;

/* RENDERTARGETS:0 */
layout(location = 0) out vec4 Color;

void main() {
    Color = texture(colortex0, texcoord);

    Color.rgb *= 1 / (dataBuf.AvgLum * 9.6) * EXPOSURE_MULT;
    
    Color.rgb = apply_tonemap(Color.rgb);
}
