Shader "Custom/URP_RingsInWater_PBR"
{
    Properties
    {
        _BaseColor          ("Water Color", Color) = (1,1,1,1)
        _Origin             ("Origin (World Space)", Vector) = (0,0,0,0)
        _Amplitude          ("Amplitude", Float) = 0.1
        _Speed              ("Speed", Float) = 1.0
        _Frequency          ("Frequency", Float) = 10.0
        _DisplacementMode   ("Displacement Mode", Range(0,3)) = 1
        _VerticalAmount     ("Vertical Amplitude", Range(0,1)) = 0.1
        _WaveNormalStrength ("Wave Normal Strength", Range(0,1)) = 1.0
        _Metallic           ("Metallic", Range(0,1)) = 0.0
        _Smoothness         ("Smoothness", Range(0,1)) = 0.9
        _FresnelStrength    ("Fresnel Strength", Range(0,5)) = 2.0

        _DepthFadeDistance  ("Depth Fade Distance", Float) = 1.5
        _ShallowBoost       ("Shallow Brightness Boost", Float) = 1.5
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalRenderPipeline"
            "RenderType"     = "Transparent"
            "Queue"          = "Transparent"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM

            #pragma vertex   vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 viewDirWS   : TEXCOORD2;
                float4 screenPos   : TEXCOORD3;
            };

            float4 _BaseColor;
            float4 _Origin;
            float  _Amplitude;
            float  _Speed;
            float  _Frequency;
            float  _DisplacementMode;
            float  _VerticalAmount;
            float  _WaveNormalStrength;
            float  _Metallic;
            float  _Smoothness;
            float  _FresnelStrength;

            float  _DepthFadeDistance;
            float  _ShallowBoost;

            // -----------------------------
            // VERTEX
            // -----------------------------
            Varyings vert(Attributes v)
            {
                Varyings o;

                float3 posOS = v.positionOS.xyz;

                float3 worldPosBefore = TransformObjectToWorld(posOS);
                float3 distanceWS     = worldPosBefore - _Origin.xyz;
                float  dist           = length(distanceWS);

                float effect = _Amplitude * sin(dist * _Frequency - _Speed * _Time.y);

                float3 dispOS = 0;

                if (_DisplacementMode < 0.5)
                {
                    if (dist > 1e-6)
                    {
                        float3 radialWS = normalize(distanceWS) * effect;
                        float3x3 w2o = (float3x3)GetWorldToObjectMatrix();
                        dispOS = mul(w2o, radialWS);
                    }
                }
                else if (_DisplacementMode < 1.5)
                {
                    dispOS = float3(0, effect * _VerticalAmount, 0);
                }
                else if (_DisplacementMode < 2.5)
                {
                    dispOS = normalize(v.normalOS) * effect;
                }
                else
                {
                    float3 radialOS = 0;
                    if (dist > 1e-6)
                    {
                        float3 radialWS = normalize(distanceWS) * effect * (1.0 - _VerticalAmount);
                        float3x3 w2o = (float3x3)GetWorldToObjectMatrix();
                        radialOS = mul(w2o, radialWS);
                    }
                    float3 verticalOS = float3(0, effect * _VerticalAmount, 0);
                    dispOS = radialOS + verticalOS;
                }

                posOS += dispOS;

                float3 positionWS = TransformObjectToWorld(posOS);
                float3 normalWS   = TransformObjectToWorldNormal(v.normalOS);

                o.positionWS  = positionWS;
                o.normalWS    = normalize(normalWS);
                o.viewDirWS   = GetWorldSpaceViewDir(positionWS);
                o.positionHCS = TransformWorldToHClip(positionWS);

                o.screenPos = ComputeScreenPos(o.positionHCS);

                return o;
            }

            // -----------------------------
            // SURFACE DATA
            // -----------------------------
            void InitializeSurfaceData(out SurfaceData s)
            {
                s = (SurfaceData)0;

                s.albedo     = _BaseColor.rgb;
                s.metallic   = _Metallic;
                s.smoothness = _Smoothness;
                s.occlusion  = 1.0;

                s.emission   = _BaseColor.rgb * 0.05;

                s.alpha      = _BaseColor.a;
            }

            // -----------------------------
            // INPUT DATA
            // -----------------------------
            void InitializeInputData(Varyings IN, out InputData i)
            {
                i = (InputData)0;

                float3 normalWS = normalize(IN.normalWS);

                if (_WaveNormalStrength > 0.001)
                {
                    float t = _Time.y * _Speed;
                    float n = sin(IN.positionWS.x * _Frequency * 0.2 + t) *
                              cos(IN.positionWS.z * _Frequency * 0.2 - t);

                    float3 bend = normalize(float3(0, 1, n));
                    normalWS = normalize(lerp(normalWS, bend, _WaveNormalStrength));
                }

                // Flip normal toward sun
                Light mainLight = GetMainLight();
                float3 L = -mainLight.direction;

                if (dot(normalWS, L) < 0)
                    normalWS = -normalWS;

                i.positionWS      = IN.positionWS;
                i.normalWS        = normalWS;
                i.viewDirectionWS = normalize(IN.viewDirWS);

                i.shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                i.fogCoord    = ComputeFogFactor(IN.positionHCS.z);

                i.vertexLighting  = 0;
                i.bakedGI         = 0;
                i.shadowMask      = 0;
                i.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionHCS);
            }

            // -----------------------------
            // FRAGMENT
            // -----------------------------
            half4 frag(Varyings IN) : SV_Target
            {
                SurfaceData s;
                InitializeSurfaceData(s);

                InputData i;
                InitializeInputData(IN, i);

                half4 col = UniversalFragmentPBR(i, s);

                // -------------------------
                // ⭐ DEPTH FADE (URP 6.x FIX)
                // -------------------------
                float2 uv = IN.screenPos.xy / IN.screenPos.w;

                float rawDepth = SampleSceneDepth(uv);

                float sceneDepth = LinearEyeDepth(rawDepth, _ZBufferParams);
                float fragDepth  = LinearEyeDepth(IN.positionHCS.z / IN.positionHCS.w, _ZBufferParams);

                float depthDiff = sceneDepth - fragDepth;

                float intersectionFade = saturate(depthDiff / _DepthFadeDistance);

                float shallowBoost = saturate(1.0 - depthDiff / _DepthFadeDistance);
                shallowBoost *= _ShallowBoost;

                col.rgb *= intersectionFade;
                col.rgb += shallowBoost * _BaseColor.rgb * 0.5;

                // -------------------------
                // ⭐ FRESNEL BOOST
                // -------------------------
                float3 N = i.normalWS;
                float3 V = normalize(i.viewDirectionWS);

                float fresnel = pow(1.0 - saturate(dot(N, V)), 3.0);
                fresnel *= _FresnelStrength;

                Light mainLight = GetMainLight();
                float3 L = -mainLight.direction;

                float sun = saturate(dot(N, L));

                col.rgb += fresnel * sun * _BaseColor.rgb * 2.0;

                col.rgb = max(col.rgb, _BaseColor.rgb * 0.2);

                return col;
            }

            ENDHLSL
        }
    }

    FallBack Off
}