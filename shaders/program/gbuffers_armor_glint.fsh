#include "/lib/all_the_libs.glsl"

in Data {
    vec2 lmcoord;
    vec2 texcoord;
    vec4 glcolor;
    flat float Id;
    flat mat3 TBN;
    vec3 ViewPos;
} DataIn;

/* RENDERTARGETS:10 */
layout(location = 0) out vec4 Color;

void main() {
	Color = texture(gtexture, DataIn.texcoord);

    if (Color.a < 0.1) {
        discard;
        return;
    }

    Color.rgb = srgb_linear(Color.rgb);
}

