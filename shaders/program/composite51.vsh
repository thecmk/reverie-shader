#include "/lib/all_the_libs.glsl"

noperspective out vec2 texcoord;
flat out float DepthCenterL;
flat out float DepthCenter;

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	#ifdef DOF_MANUAL_FOCUS
        DepthCenterL = DOF_FOCUS_DISTANCE;
    #else
        DepthCenter = texture(depthtex1, vec2(0.5)).r;

        float OldDepth = dataBuf.DofFocus;
        float BlendFactor = frameTime / (1 + frameTime) * DOF_FOCUS_ADJUSTMENT_SPEED;
        DepthCenter = mix(OldDepth, DepthCenter, BlendFactor);

        DepthCenterL = l_depth(DepthCenter);
    #endif
}
