#include "/lib/all_the_libs.glsl"
#include "/generic/post/cas.fsh"
in vec2 texcoord;

#include "/generic/post/taa.glsl"
#include "/lib/tonemap/Uncharted2_ext.glsl"

vec3 sample_normal(vec2 FragCoord) {
    return decodeUnitVector(texture(colortex14, FragCoord, 0).zw * 2 - 1) * 0.5 + 0.5;
}

vec3 apply_vignette(vec3 Color, vec2 Pos) {
    Pos = Pos - 0.5;
    float Strength = len2(Pos);
    Strength = pow(Strength, 2 - VIGNETTE_FALLOFF);
    Color *= 1 - min(Strength, 1);
    return Color;
}

vec3 channel_mixer(vec3 Color) {
    vec3 NewColor = vec3(0);
    NewColor += Color.r * vec3(CM_R_IN_R, CM_G_IN_R, CM_B_IN_R);
    NewColor += Color.g * vec3(CM_R_IN_G, CM_G_IN_G, CM_B_IN_G);
    NewColor += Color.b * vec3(CM_R_IN_B, CM_G_IN_B, CM_B_IN_B);
    return clamp(NewColor, 0, 1);
}

vec3 color_balance(vec3 Color) {
    vec3 Shadows = clamp(Color + vec3(SHADOWS_CYAN_TO_RED, SHADOWS_MAGENTA_TO_GREEN, SHADOWS_YELLOW_TO_BLUE), 0, 1);
    vec3 Mids = clamp(Color + vec3(MIDS_CYAN_TO_RED, MIDS_MAGENTA_TO_GREEN, MIDS_YELLOW_TO_BLUE), 0, 1);
    vec3 Highs = clamp(Color + vec3(HIGHS_CYAN_TO_RED, HIGHS_MAGENTA_TO_GREEN, HIGHS_YELLOW_TO_BLUE), 0, 1);

    float OldL = get_luminance(Color);
    vec3 NewColor = OldL < 0.5 ? mix(Shadows, Mids, OldL * 2) : mix(Mids, Highs, OldL * 2 - 1);
    float NewL = get_luminance(NewColor);

    NewColor *= OldL / NewL;
    return NewColor;
}

/* RENDERTARGETS:0 */
layout(location = 0) out vec4 Color;

vec3 sRGB_EncodeSafe(vec3 c) {
   //Save sign for Wide Color Gamut
   vec3 s = sign(c);
   c = abs(c);
    
   //sRGB
   bvec3 cutoff = lessThan(c, vec3(0.0031308));
   vec3 higher = vec3(1.055) * pow(c, vec3(1.0 / 2.4)) - vec3(0.055);
   vec3 lower = c * vec3(12.92);
   c = mix(higher, lower, cutoff);

   //Restore Sign
   return c * s;
}

void main() {
    #if AA_MODE != 0 && !(defined PIXELATION)
	    Color.rgb = CAS(colortex0, texcoord, SHARPENING_AMOUNT);
    #else
        Color.rgb = textureLod(colortex0, texcoord, 0).rgb;
    #endif

    #ifdef COLOR_BALANCING
        Color.rgb = color_balance(Color.rgb);
    #endif

    #ifdef CHANNEL_MIXER
        Color.rgb = channel_mixer(Color.rgb);
    #endif

    #ifdef HDR_ENABLED
        Color.rgb = reinhard_odd_inv(Color.rgb);
        Color.rgb = Uncharted2_ext(Color.rgb);
        Color.rgb *= HdrGamePaperWhiteBrightness / HdrUIBrightness;
        Color.rgb = sRGB_EncodeSafe(Color.rgb);
    #else
        // These tonemaps already have the conversion built in
        #if TONEMAP_OPERATOR != 1 && TONEMAP_OPERATOR != 3
            Color.rgb = linear_srgb(Color.rgb);
        #endif
    #endif

    #ifdef FILM_GRAIN
     Color.rgb = film_grain(Color.rgb, gl_FragCoord.xy);
    #endif

    Color.rgb = apply_vibrance(Color.rgb, VIBRANCE);
    Color.rgb = apply_saturation(Color.rgb, SATURATION);
    Color.rgb = apply_contrast(Color.rgb, CONTRAST);

    #ifdef VIGNETTE
        Color.rgb = apply_vignette(Color.rgb, texcoord);
    #endif

    #ifndef HDR_ENABLED
        Color.rgb += (dither(gl_FragCoord.xy, false) - 0.5) / 255;
    #endif

    imageStore(water_depth_min, ivec2(gl_FragCoord.xy), uvec4(floatBitsToUint(1e6)));
}
