#include "/lib/all_the_libs.glsl"

flat out vec3 LightColorDirect;
noperspective out vec2 texcoord;
void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    LightColorDirect = get_shadowlight_color();
}
