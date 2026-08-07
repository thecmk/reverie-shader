#include "/lib/all_the_libs.glsl"

#include "/generic/water.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/shadow/rsm.glsl"
#include "/generic/post/taa.glsl"

// Denoise pass for GI

in vec2 texcoord;

/* RENDERTARGETS:13,14 */
layout(location = 0) out vec4 GIDenoise;
layout(location = 1) out vec4 GIAux;

void main() {
	bool IsDH;
	float Depth = get_depth(texcoord, IsDH);
	if(Depth < 1 && Depth > 0.56) {
		Positions Pos = get_positions(texcoord, Depth, IsDH, true);
		vec4 GI = texture(colortex3, texcoord * INDIRECT_RES_SCALE);
		vec2 BentNormalEncoded = texture(colortex5, texcoord * INDIRECT_RES_SCALE).zw;
		GIDenoise = temporal_denoise_gi(GI, Pos.Screen, gl_FragCoord.xy, IsDH, BentNormalEncoded, GIAux);
	} else {
		GIDenoise = vec4(0,0,0,0);
		GIAux = vec4(0);
	}
}
