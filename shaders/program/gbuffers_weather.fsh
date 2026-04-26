#include "/lib/all_the_libs.glsl"

in Data {
    vec2 lmcoord;
    vec2 texcoord;
    vec4 glcolor;
    flat float Id;
    flat mat3 TBN;
    vec3 ViewPos;
} DataIn;

#include "/generic/water.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/lighting/lighting.fsh"

/* RENDERTARGETS:5 */
layout(location = 0) out vec4 Albedo;

void main() {
    vec4 Color = DataIn.glcolor * texture(gtexture, DataIn.texcoord);
    if(Color.a < 0.1) discard;
    float L = get_luminance(Color.rgb);
    Albedo = vec4(0, L, 0, 0);
}
