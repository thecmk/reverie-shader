#define GBUFFERS_SPIDEREYES

#include "/lib/all_the_libs.glsl"
#include "/generic/water.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/lighting/lighting.fsh"

#ifdef SEPARATE_ENTITY_DRAWS 
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