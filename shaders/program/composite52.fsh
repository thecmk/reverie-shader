#include "/lib/all_the_libs.glsl"

#include "/generic/post/cas.fsh"
/* RENDERTARGETS:0 */
layout(location = 0) out vec4 Color;

noperspective in vec2 texcoord;

const bool colortex0MipmapEnabled = true;


void main() {

    vec3 Col = texture(colortex0, texcoord, PIXELATION_AMOUNT).rgb;

    #ifdef PIXELATION_SHARPENING
        vec2 d = 0.66 * resolutionInv * exp2(PIXELATION_AMOUNT);
        vec3 Blurred  = texture(colortex0, texcoord + vec2(-1, -1) * d, PIXELATION_AMOUNT).rgb;
            Blurred += texture(colortex0, texcoord + vec2( 1,  1) * d, PIXELATION_AMOUNT).rgb;
            Blurred += texture(colortex0, texcoord + vec2(-1,  1) * d, PIXELATION_AMOUNT).rgb;
            Blurred += texture(colortex0, texcoord + vec2( 1, -1) * d, PIXELATION_AMOUNT).rgb;
        Blurred *= 0.25;

        float Weight = abs(get_luminance(Col) - get_luminance(Blurred));
        Col = Col + Col * (Col - Blurred) * PIXELATION_SHARPENING_AMOUNT;
    #endif

    Color = vec4(Col, 1);
}
