#include "/lib/all_the_libs.glsl"
#include "/generic/water.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/lighting/lighting.fsh"

#if (defined SEPARATE_ENTITY_DRAWS) && MC_VERSION < 12105 
#include "/generic/lighting/gbuffers_translucent.fsh"
void main() {
    init_frag_translucent();
}
#else
#include "/generic/lighting/gbuffers.fsh"
void main() {
    init_frag();
}
#endif