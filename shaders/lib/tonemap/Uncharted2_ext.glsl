const float HABLE_A = 0.15f;
const float HABLE_B = 0.50f;
const float HABLE_C = 0.10f;
const float HABLE_D = 0.20f;
const float HABLE_E = 0.02f;
const float HABLE_F = 0.30f;
const float HABLE_W = 11.0f;


vec3 Reinhard(vec3 x, float peak) {
  return x / (x / peak + 1.);
}
vec3 ReinhardExtended(vec3 x, float white_max, float peak) {
  return Reinhard(x, peak) * (1. + (peak * x) / (white_max * white_max));
}
float ComputeReinhardExtendableScale(float w, float p, float m, float x, float y) {
  return p * (w * w * y - (p * x * x)) / (w * w * x * (p - y));
}
vec3 ReinhardPiecewiseExtended(vec3 x, float white_max, float x_max, float shoulder)
{
   const float x_min = 0.f; //(perhaps HdrGameMinimumBrightness can go here, but whatever...)
   float exposure = ComputeReinhardExtendableScale(white_max, x_max, x_min, shoulder, shoulder);
   vec3 extended = ReinhardExtended(x * exposure, white_max * exposure, x_max);
   extended = min(extended, x_max);
   return mix(x, extended, step(shoulder, x));
}

// https://github.com/XgarhontX/photon-hdr/blob/main/shaders/renodx.glsl
float SignSqrt(float x) {
  return sign(x) * sqrt(abs(x));
}

float Hable_ApplyCurve(float x, float a, float b, float c, float d, float e, float f) {
  float numerator = x * (a * x + c * b) + d * e;  // x * (a * x + c * b) + d * e
  float denominator = x * (a * x + b) + d * f;    // x * (a * x + b) + d * f
  return (numerator / denominator) - (e / f);
}

vec3 Hable_ApplyCurve(vec3 x, float a, float b, float c, float d, float e, float f) {
  vec3 numerator = x * (a * x + c * b) + d * e;  // x * (a * x + c * b) + d * e
  vec3 denominator = x * (a * x + b) + d * f;    // x * (a * x + b) + d * f
  return (numerator / denominator) - (e / f);
}

float Hable_ApplyCurve(float x) {
  return Hable_ApplyCurve(x, HABLE_A, HABLE_B, HABLE_C, HABLE_D, HABLE_E, HABLE_F);
}

vec3 Hable_ApplyCurve(vec3 x) {
  return Hable_ApplyCurve(x, HABLE_A, HABLE_B, HABLE_C, HABLE_D, HABLE_E, HABLE_F);
}

float Hable_Derivative(
    float x,
    float a, float b, float c,
    float d, float e, float f) {
  float num = -a * b * (c - 1.0) * x * x
              + 2.0 * a * d * (f - e) * x
              + b * d * (c * f - e);

  float den = x * (a * x + b) + d * f;
  den = den * den;

  return num / den;
}

float Hable_Derivative(float x) {
  return Hable_Derivative(x, HABLE_A, HABLE_B, HABLE_C, HABLE_D, HABLE_E, HABLE_F);
}

// Root of f'(x) = 0 for the raw ApplyCurve, using quadratic formula.
// With a,b,c,d,e,f > 0 and 0 < c < 1, this is well-defined.
float Hable_FindDerivativeRoot(
    float a, float b, float c,
    float d, float e, float f) {
  // Quadratic coefficients for numerator of f'(x)
  // -a*b*(c - 1) * x^2 + 2*a*d*(f - e)*x + b*d*(c*f - e) = 0
  float Aq = a * b * (1.f - c);  // -a*b*(c-1)
  float Bq = 2.f * a * d * (f - e);
  float Cq = b * d * (c * f - e);

  // Discriminant
  float disc = Bq * Bq - 4.f * Aq * Cq;
  disc = max(disc, 0.f);  // just in case of tiny negatives

  float sqrtDisc = sqrt(disc);

  float r1 = (-Bq + sqrtDisc) / (2.f * Aq);
  float r2 = (-Bq - sqrtDisc) / (2.f * Aq);

  // Larger root of the quadratic
  float root = max(r1, r2);

  // Only care about non-negative x in our domain
  return max(root, 0.f);
}

// Analytic knee root of f'''(x) = 0 for Uncharted2/Hable ApplyCurve
// a,b,c,d,e,f > 0, typically 0 < c < 1.
// Returns the smallest positive real root ("first knee") in x > 0.
float Hable_FindThirdDerivativeRoot(float a, float b, float c, float d, float e, float f) {
  // sqrt(a b^2 c^2 - 2 a b^2 c + a b^2)
  float sqrt_ab = sqrt(
      a * b * b * c * c
      - 2.f * a * b * b * c
      + a * b * b);

  // sqrt(a d^2 e^2 - 2 a d^2 e f + a d^2 f^2
  //    + b^2 c^2 d f + b^2 (-c) d e - b^2 c d f + b^2 d e)
  float sqrt_df = sqrt(
      a * d * d * e * e
      - 2.f * a * d * d * e * f
      + a * d * d * f * f
      + b * b * c * c * d * f
      + b * b * (-c) * d * e
      - b * b * c * d * f
      + b * b * d * e);

  // Precompute (d e - d f)
  float de_df = d * e - d * f;

  // Inner big piece: sqrt_ab * (...) / (8 * sqrt_df)
  float term_top =
      32.f * (a * d * d * e * f - a * d * d * f * f + b * b * c * d * f - b * b * d * e)
      / (a * a * b * (c - 1.f));

  float term_mid =
      96.f * de_df * (c * d * f - d * e)
      / (a * b * (c - 1.f) * (c - 1.f));

  float de_df2 = de_df * de_df;
  float de_df3 = de_df2 * de_df;

  float term_tail =
      64.f * de_df3
      / (b * b * b * (c - 1.f) * (c - 1.f) * (c - 1.f));

  float Tfrac = sqrt_ab * (term_top - term_mid - term_tail)
                / (8.f * sqrt_df);

  // (12 a^2 b c d f - 12 a^2 b d e) / (6 (a^3 b c - a^3 b))
  float Tmid2_num = 12.f * a * a * b * c * d * f
                    - 12.f * a * a * b * d * e;
  float Tmid2_den = 6.f * (a * a * a * b * c - a * a * a * b);
  float Tmid2 = Tmid2_num / Tmid2_den;

  // (6 (c d f - d e))/(a (c - 1))
  float T3 = 6.f * (c * d * f - d * e)
             / (a * (c - 1.f));

  // (8 (d e - d f)^2)/(b^2 (c - 1)^2)
  float T4 = 8.f * de_df2
             / (b * b * (c - 1.f) * (c - 1.f));

  // Centers for the ± branches
  float centerNeg = -Tfrac + Tmid2 + T3 + T4;  // used with sqrt(-centerNeg)
  float centerPos = Tfrac + Tmid2 + T3 + T4;   // used with sqrt( centerPos)

  // Branch square roots: use SignSqrt for robustness and correct branch behaviour
  float sNeg = SignSqrt(-centerNeg);
  float sPos = SignSqrt(centerPos);

  // Shifts:
  //  - first two roots use:  - sqrt_df/sqrt_ab - (d e - d f)/(b (c - 1))
  //  - last two use:          sqrt_df/sqrt_ab - (d e - d f)/(b (c - 1))
  float shift1 = sqrt_df / sqrt_ab + de_df / (b * (c - 1.f));  // we subtract this
  float shift2 = sqrt_df / sqrt_ab - de_df / (b * (c - 1.f));  // we add this

  // The four analytic roots from WA, mapped to floats:
  float r1 = -0.5f * sNeg - shift1;  // -1/2 * sqrt(-centerNeg) - shift1
  float r2 = 0.5f * sNeg - shift1;   //  1/2 * sqrt(-centerNeg) - shift1
  float r3 = -0.5f * sPos + shift2;  // -1/2 * sqrt( centerPos) + shift2
  float r4 = 0.5f * sPos + shift2;   //  1/2 * sqrt( centerPos) + shift2

  // Max root seems to be always be the right one
  float root = clamp(max(r1, max(r2, max(r3, r4))), 0, 1);

  return root;
}

float Hable_FindThirdDerivativeRoot() {
  return Hable_FindThirdDerivativeRoot(HABLE_A, HABLE_B, HABLE_C, HABLE_D, HABLE_E, HABLE_F);
}

vec3 Hable_ApplyExtended(vec3 x, float white_precompute) {    
  vec3 base = Hable_ApplyCurve(x) * white_precompute;

  float pivot_x = Hable_FindThirdDerivativeRoot();
  float pivot_y = Hable_ApplyCurve(pivot_x) * white_precompute;
  float slope = Hable_Derivative(pivot_x) * white_precompute;
  vec3 offset = vec3(pivot_y - slope * pivot_x);

  vec3 extended = vec3(slope) * x + offset;

  return mix(base, extended, step(vec3(pivot_x), x));
}

vec3 Uncharted2_ext(vec3 color) {
  #ifdef HDR_ENABLED
    //boost
    color *= 2.0;

    //setup
    float white_precompute = 1.f / Hable_ApplyCurve(HABLE_W);

    float peak = (HdrGamePeakBrightness / HdrGamePaperWhiteBrightness);
    float shoulder = (36.0 / HdrGamePaperWhiteBrightness);

    //do
    vec3 s = sign(color);
    color = abs(color);
    color = Hable_ApplyExtended(color, white_precompute);
    color = ReinhardPiecewiseExtended(color, 100, peak, shoulder); //good enough for blowout
    color *= s;
  #endif

  return color;
}