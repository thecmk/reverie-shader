#include "/lib/all_the_libs.glsl"
#include "/generic/water.glsl"

#include "/generic/weather.glsl"

attribute vec2 mc_Entity;
attribute vec2 mc_midTexCoord;
attribute vec4 at_midBlock;

out vec2 texcoord;


void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    gl_Position = ftransform();
    gl_Position.xyz = distort(gl_Position.xyz);
}
