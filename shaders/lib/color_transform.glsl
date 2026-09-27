const mat3 REC709_TO_XYZ = mat3(
    0.4124564, 0.3575761, 0.1804375,
    0.2126729, 0.7151522, 0.0721750,
    0.0193339, 0.1191920, 0.9503041
);

const mat3 XYZ_TO_REC709 = mat3(
     3.2409699419,-1.5373831776,-0.4986107603,
    -0.9692436363, 1.8759675015, 0.0415550574,
     0.0556300797,-0.2039769589, 1.0569715142
);

const mat3 XYZ_TO_REC2020 = mat3(
    1.7166084, -0.3556621, -0.2533601, 
    -0.6666829, 1.6164776, 0.0157685, 
    0.0176422, -0.0427763, 0.94222867
);
const mat3 REC2020_TO_XYZ = mat3(
    0.6369736, 0.1446172, 0.1688585, 
    0.2627066, 0.6779996, 0.0592938, 
    0.0000000, 0.0280728, 1.0608437
);


const mat3 REC709_REC2020 = REC709_TO_XYZ * XYZ_TO_REC2020;
const mat3 REC2020_REC709 = REC2020_TO_XYZ * XYZ_TO_REC709;

#define linear_srgb(linear) ( mix(12.92 * linear, 1.055 * pow(linear, vec3(1/2.4)) - 0.055, step(0.0031308, linear)) )
#define srgb_linear(srgb) ( mix(srgb / 12.92, pow(((srgb + 0.055)/(1.055)), vec3(2.4)), step(0.04045, srgb)))

#define srgb_rec2020(srgb) ( srgb_linear(srgb) * REC709_REC2020 )

vec3 rgb_to_hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz),
                 vec4(c.gb, K.xy),
                 step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r),
                 vec4(c.r, p.yzx),
                 step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(
        abs(q.z + (q.w - q.y) / (6.0 * d + e)), // Hue
        d / (q.x + e),                          // Saturation
        q.x                                     // Value
    );
}

vec3 hsv_to_rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 rgb_to_xyz(vec3 rgb) {
    const mat3 XYZ_MATRIX = mat3(
            0.5149, 0.3654, 0.0248,
            0.3244, 0.6704, 0.1248,
            0.1607, 0.0642, 0.8504
        );
    return XYZ_MATRIX * rgb;
}


// https://graphicrants.blogspot.com/2009/04/rgbm-color-encoding.html
vec4 RGBMEncode( vec3 color ) {
    vec4 rgbm;
    color = color;
    color = sqrt(color);
    color *= 1.0 / 6.0;
    rgbm.a = clamp( max( max( color.r, color.g ), max( color.b, 1e-6 ) ), 0, 1 );
    rgbm.a = ceil( rgbm.a * 255.0 ) / 255.0;
    rgbm.rgb = color / rgbm.a;
    return rgbm;
}

vec3 RGBMDecode( vec4 rgbm ) {
    return pow2(6.0 * rgbm.rgb * rgbm.a);
}

vec3 texture_rgbm(sampler2D sampler, vec2 texcoord) {
    return RGBMDecode(texture(sampler, texcoord));
}
