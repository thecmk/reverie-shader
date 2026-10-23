#include "/lib/all_the_libs.glsl"

vec2 clrwl_distortShadowClipXY(vec2 vertexClipXY) {
    return distort(vec3(vertexClipXY, 0.0)).xy;
}

float clrwl_distortShadowClipZ(float vertexClipZ) {
    return distort(vec3(0.0, 0.0, vertexClipZ)).z;
}