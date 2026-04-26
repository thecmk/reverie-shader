#include "/lib/all_the_libs.glsl"
#include "/generic/water.glsl"
attribute vec2 mc_Entity;
attribute vec2 mc_midTexCoord;

out vec2 texcoord;
out vec4 glcolor;

flat out vec3 Normal;
flat out float Material;

out vec3 PlayerPos;

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	glcolor = gl_Color;

	Normal = normalize(gl_NormalMatrix * gl_Normal);
	Material = (mc_Entity.x - 10000.0);

	PlayerPos = (shadowModelViewInverse * vec4((gl_ModelViewMatrix * gl_Vertex).xyz, 1)).xyz;
	vec3 WorldPos = PlayerPos + cameraPosition;

	#ifdef WAVY_PLANTS
    vec3 WavePos = WorldPos / WAVE_SIZE + frameTimeCounter * WAVE_SPEED;
    WavePos = sin(WavePos);
    float Noise = WavePos.x * WavePos.y * WavePos.z;
    Noise *= WAVE_AMPLITUDE + rainStrength * 0.1;
    #ifdef WAVE_LEAVES
    if (Material == MATERIAL_LEAVES) {
        WorldPos.x += Noise / 2;
        WorldPos.zy -= Noise / 2;
    }
    else
    #endif
    if (Material == MATERIAL_SHORT_PLANT) {
        if (gl_MultiTexCoord0.t < mc_midTexCoord.t)
            WorldPos += Noise;
    }
    else if (Material == MATERIAL_TALL_PLANT_LOWER) {
        if (gl_MultiTexCoord0.t < mc_midTexCoord.t)
            WorldPos += Noise / 2;
    }
    else if (Material == MATERIAL_TALL_PLANT_UPPER) {
        if (gl_MultiTexCoord0.t > mc_midTexCoord.t)
            WorldPos += Noise / 2;
        else
            WorldPos += Noise;
    }
    #endif

	gl_Position = shadowProjection * vec4((shadowModelView * vec4((WorldPos - cameraPosition), 1)).xyz, 1);
	
	gl_Position.xyz = distort(gl_Position.xyz);
}
