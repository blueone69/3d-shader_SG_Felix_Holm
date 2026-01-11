Shader "Stylized/CelOutlineAnimated"
{
    Properties
    {
        // Base color for cel shading
        _BaseColor("Base Color", Color) = (1,1,1,1)

        // Shadow color for darker cel bands
        _ShadowColor("Shadow Color", Color) = (0.1,0.1,0.1,1)

        // Number of cel shading steps
        _Steps("Cel Steps", Range(1,8)) = 3

        // Light intensity multiplier
        _LightIntensity("Light Intensity", Range(0.1,4)) = 1.0

        // Outline color
        _OutlineColor("Outline Color", Color) = (0,0,0,1)

        // Outline thickness
        _OutlineThickness("Outline Thickness", Range(0.0,0.05)) = 0.02

        // Outline animation speed
        _OutlineAnimSpeed("Outline Anim Speed", Range(0.0,10.0)) = 2.0

        // Outline animation amplitude
        _OutlineAnimAmplitude("Outline Anim Amplitude", Range(0.0,0.02)) = 0.005

        // Cel shading animation speed (e.g. shimmer)
        _CelAnimSpeed("Cel Anim Speed", Range(0.0,10.0)) = 1.5

        // Cel shading animation amplitude
        _CelAnimAmplitude("Cel Anim Amplitude", Range(0.0,1.0)) = 0.2

        // Optional normal map
        _NormalMap("Normal Map", 2D) = "bump" {}

        // Normal map strength
        _NormalStrength("Normal Strength", Range(0.0,2.0)) = 1.0
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline"="UniversalPipeline"
        }

        // ---------- PASS 1: OUTLINE (INVERSE HULL) ----------
        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }

            Cull Front        // Render backfaces to create outline shell
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _OutlineColor;
                float  _OutlineThickness;
                float  _OutlineAnimSpeed;
                float  _OutlineAnimAmplitude;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // Outline animation
                float t = _Time.y * _OutlineAnimSpeed;
                float animOffset = sin(t) * _OutlineAnimAmplitude;

                float outlineAmount = _OutlineThickness + animOffset;

                float3 normalOS = normalize(IN.normalOS);
                float3 offsetPosOS = IN.positionOS.xyz + normalOS * outlineAmount;

                float3 positionWS = TransformObjectToWorld(float4(offsetPosOS, 1.0));
                OUT.positionHCS = TransformWorldToHClip(positionWS);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                return _OutlineColor;
            }

            ENDHLSL
        }

        // ---------- PASS 2: CEL SHADING ----------
        Pass
        {
            Name "CelShading"
            Tags { "LightMode"="UniversalForward" }

            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float4 tangentOS  : TANGENT;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float4 positionWS  : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float2 uv          : TEXCOORD2;
                float3 tangentWS   : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _ShadowColor;
                float  _Steps;
                float  _LightIntensity;
                float  _CelAnimSpeed;
                float  _CelAnimAmplitude;
                float  _NormalStrength;
            CBUFFER_END

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                float3 posWS = TransformObjectToWorld(IN.positionOS);
                OUT.positionWS = float4(posWS, 1.0);
                OUT.positionHCS = TransformWorldToHClip(posWS);

                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);
                float3 tangentWS = TransformObjectToWorldDir(IN.tangentOS.xyz);
                float3 bitangentWS = cross(normalWS, tangentWS) * IN.tangentOS.w;

                OUT.normalWS = normalWS;
                OUT.tangentWS = tangentWS;
                OUT.bitangentWS = bitangentWS;
                OUT.uv = IN.uv;

                return OUT;
            }

            float3 ApplyNormalMap(float3 normalWS, float3 tangentWS, float3 bitangentWS, float2 uv)
            {
                float4 normalTex = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv);
                float3 normalTS = UnpackNormal(normalTex);
                normalTS.xy *= _NormalStrength;
                normalTS = normalize(normalTS);

                float3x3 TBN = float3x3(tangentWS, bitangentWS, normalWS);
                float3 finalNormalWS = normalize(mul(TBN, normalTS));
                return finalNormalWS;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float3 normalWS = normalize(IN.normalWS);

                // Apply normal map if present
                normalWS = ApplyNormalMap(normalWS, normalize(IN.tangentWS), normalize(IN.bitangentWS), IN.uv);

                // Get main directional light
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS.xyz));

                float3 lightDir = normalize(mainLight.direction);
                float NdotL = saturate(dot(normalWS, lightDir));

                // Cel shading animation (shimmer)
                float t = _Time.y * _CelAnimSpeed;
                float anim = sin(t + IN.positionWS.x + IN.positionWS.z) * _CelAnimAmplitude;

                float lit = saturate(NdotL * _LightIntensity + anim);

                // Quantize into cel steps
                float steps = max(_Steps, 1.0);
                float stepped = floor(lit * steps) / (steps - 0.0001);

                // Blend between shadow and base color
                float3 color = lerp(_ShadowColor.rgb, _BaseColor.rgb, stepped);

                // Multiply by light color
                color *= mainLight.color;

                return float4(color, _BaseColor.a);
            }

            ENDHLSL
        }
    }

    FallBack Off
}
