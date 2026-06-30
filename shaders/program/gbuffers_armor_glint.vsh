#include "/lib/all_the_libs.glsl"

out vec2 texcoord;
void main() {
	gl_Position = ftransform();
	gl_Position.xy += taaJitter * gl_Position.w;
  	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
