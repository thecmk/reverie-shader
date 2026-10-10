#define WATER_NOISE_BUFFER waterNoise

float sine(vec2 Coords, float Amp, float Speed, vec2 FlowDir) {
    float x = dot(Coords, FlowDir) + (frameTimeCounter * Speed);
    return Amp * sin(x);
}

vec2 sine_d(vec2 Coords, float Amp, float Speed, vec2 FlowDir) {
    float x = dot(Coords, FlowDir) + (frameTimeCounter * Speed);
    return Amp * FlowDir * cos(x);
}

float get_water_height(vec3 WorldPos) {
    vec2 Coords = WorldPos.xz * 2;
    const float WAVE_ITER = 32;
    vec2 FlowDir = windDirection;
    float Amp = 1, Speed = 1., Sum = 0, AmpSum = 0;
    for (int i = 1; i <= WAVE_ITER; i++) {
        vec2 PrevWave = sine_d(Coords, Amp, Speed, FlowDir);

        Coords *= 1 + 2.5 / WAVE_ITER;
        FlowDir = rotate(FlowDir, 2.2242);
        Amp *= 1 - 0.2 / WAVE_ITER;
        Speed *= 1 + 2.25 / WAVE_ITER;

        float Wave = sine(Coords + PrevWave, Amp, Speed, FlowDir);

        Sum += Wave;
        AmpSum += Amp;
    }  
    return (Sum / AmpSum) * 0.2;
}

vec2 get_water_height_d(vec3 WorldPos) {
    vec2 Coords = WorldPos.xz * 2; 
    const float WAVE_ITER = 32;
    vec2 Sum = vec2(0), FlowDir = windDirection;
    float Amp = 1, Speed = 1., AmpSum = 0;
    vec2 PrevWave = vec2(0); // Used for domain warping
    for (int i = 1; i <= WAVE_ITER; i++) {
        Coords *= 1 + 2.5 / WAVE_ITER;
        FlowDir = rotate(FlowDir, 2.2242);
        Amp *= 1 - 0.2 / WAVE_ITER;
        Speed *= 1 + 2.25 / WAVE_ITER;

        vec2 Wave = sine_d(Coords + PrevWave, Amp, Speed, FlowDir);

        Sum += Wave;
        PrevWave = Wave;
        AmpSum += Amp;
    }
    return Sum / AmpSum * 0.1;
}

vec3 change_flow_dir(vec3 Coords, vec3 WorldNormal) {
    // Fix normals for water falling vertically
    if(abs(WorldNormal.y) < 0.01) {
        if(abs(WorldNormal.x) < 0.5) {
            Coords.xz = Coords.xy * sign(-WorldNormal.z);
        } else {
            Coords.xz = Coords.yz * sign(-WorldNormal.x);
        }
    }
    // Increase flow speed in the direction the water flows
    Coords.xz -= frameTimeCounter * normalize(WorldNormal.xz) * 8 * (1 - pow4(WorldNormal.y));
    return Coords;
}

vec3 get_water_normal(vec3 Coords, vec3 WorldNormal) {
    Coords = change_flow_dir(Coords, WorldNormal);
    vec2 H = get_water_height_d(Coords); // * pow(max(1+Dist/128, 0), 4);

    return vec3(H.x, H.y, sqrt(1 - (H.x * H.x + H.y * H.y)));
}

float get_water_height_noise(vec3 WorldPos) {
    vec2 Coords = WorldPos.zx;
    float color = texture(WATER_NOISE_BUFFER, (Coords - frameTimeCounter * 0.7) / 8).x * 0.4;
    Coords.y += sin(Coords.x / 12) * 2;
    color += texture(WATER_NOISE_BUFFER, (Coords + frameTimeCounter * 1.2) / 24).x * 0.6;
    return (color - 0.5) * 3;
}

float get_water_caustics(vec3 PlayerPos) {
    vec3 WorldPos = PlayerPos + cameraPosition;
    vec3 PlayerPosS = WorldPos - PLAYER_LIGHT_VEC / max(0.25, PLAYER_LIGHT_VEC.y) * WorldPos.y;
    float WaterHeight = get_water_height_noise(PlayerPosS);
    float CausticsColor = exp(-abs(WaterHeight) * 3) * 1.5 + 0.25;
    return CausticsColor;
}

vec3 get_water_parallax(vec3 WorldPos, vec3 PlayerPosN) {
    const int StepCount = 4;

    vec3 Offset = PlayerPosN / abs(PlayerPosN.y);
    vec3 CurrentPos = WorldPos;
    float InitialHeight = fract(WorldPos.y);
    float CurrentHeight = InitialHeight;
    
    for(int i = 0; i < StepCount; i++) {      
        float NewHeight = get_water_height(CurrentPos) + InitialHeight;
        CurrentPos += Offset * (CurrentHeight - NewHeight);
        CurrentHeight = NewHeight;
    }
    return CurrentPos;
}

MaterialProperties get_puddles(Positions Pos, MaterialProperties Mat, inout vec3 Color, inout float PuddleStrength) {
    PuddleStrength = wetness; // Only after it's raining
    if(PuddleStrength < 0.01) return Mat;

    vec3 WorldPos = Pos.Player + cameraPosition;
    PuddleStrength *= linstep(0.9, 0.95, Mat.Lightmap.y); // Not in the shade
    PuddleStrength *= float(Mat.Id < MATERIAL_WATER); // Not on foliage or other mats
    PuddleStrength *= step(0.99, dot(gbufferModelView[1].xyz, Mat.FlatNormal)); // Only when facing up

    if(PuddleStrength < 0.01) return Mat;
    PuddleStrength *= texture(noisetex, WorldPos.xz / 1000).r;

    float Darkening = pow2(PuddleStrength);
    PuddleStrength = smoothstep(1 - PUDDLE_COVERAGE - 0.05, 1 - PUDDLE_COVERAGE + 0.05, PuddleStrength);
    if(PuddleStrength < 0.01) return Mat; 

    Mat.Smoothness = hardcoded_smoothness(MATERIAL_WATER);
    Mat.F0 = hardcoded_f0(MATERIAL_WATER);

    Mat.Normal = view_player(Mat.FlatNormal, false);
    Mat.Normal = tbn_normal(Mat.Normal) * get_water_normal(WorldPos * 3, Mat.Normal);
    Mat.Normal = player_view(Mat.Normal, false);

    Color.rgb *= 1 - Darkening * 0.33;

    return Mat;
}