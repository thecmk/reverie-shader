float shadowMapBias = 1.0 - 25.6 / shadowDistanceDH;

// float get_distort_factor(vec2 pos) {
//     return length(pos.xy) * shadowMapBias + (1 - shadowMapBias);
// }

// Squircle distortion - covers the shadowmap better
// https://gist.github.com/Luracasmus/7ef1602bc9bdc14c95e3e1f98c9c4dd0
float get_distort_factor(vec2 pos) {
    vec2 Pos2 = pow2(pos);
    vec2 Pow4 = pow2(Pos2);
    float s = 1 - 2.0 / shadowDistanceDH;
    float FgSqR = sqrt(Pos2.x + Pos2.y + sqrt(Pow4.x + (2.0 - 4.0 * pow2(s)) * Pos2.x * Pos2.y + Pow4.y)) * inversesqrt(2.0);
    return FgSqR * shadowMapBias + (1 - shadowMapBias);
}

vec3 distort(vec3 pos) {
    float factor = get_distort_factor(pos.xy);
    return vec3(pos.xy / factor, pos.z * 0.2);
}

vec3 distort(vec3 pos, float factorInv) {
    return vec3(pos.xy * factorInv, pos.z * 0.2);
}

vec3 undistort(vec3 pos) {
    float factor = get_distort_factor(pos.xy);
    return vec3(pos.xy * factor, pos.z / 0.2);
}

// Adapted from Complementary Shaders
// with Emin's explicit permission
vec3 compute_bias(vec3 PlayerPos, vec3 WorldNormal, float NdotL, float Skylight) {
    float DistanceBias = pow(dot(PlayerPos, PlayerPos), 0.75);
    DistanceBias = 0.12 + 0.0008 * DistanceBias;
    vec3 Bias = WorldNormal * DistanceBias * (2 - 0.95 * max(NdotL, 0));

    #ifdef DIMENSION_OVERWORLD
        if (Skylight < 0.5 && isEyeInWater != 1) {
            vec3 EdgeFactor = 0.2 * (0.5 - fract(PlayerPos + cameraPosition + WorldNormal * 0.01));
            Bias += max(0.5 - Skylight, 0) * EdgeFactor;
        }
    #endif
    
    return Bias;
}
