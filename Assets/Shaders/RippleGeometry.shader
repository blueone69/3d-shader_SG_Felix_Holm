Shader "Custom/RippleGeometryTextured"
{
    Properties
    {
        _BaseMap ("Base Texture", 2D) = "white" {}
        _BaseColor ("Base Color Tint", Color) = (1,1,1,1)

        _Origin ("Origin (Object Space)", Vector) = (0,0,0,0)
        _Radius ("Radius", Float) = 1
        _Amplitude ("Amplitude", Float) = 0.1
        _Speed ("Speed", Float) = 1
        _Frequency ("Frequency", Float) = 10
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 200

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 normalWS    : NORMAL;
                float2 uv          : TEXCOORD0;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            float4 _BaseColor;

            float3 _Origin;
            float _Radius;
            float _Amplitude;
            float _Speed;
            float _Frequency;

            // Unity auto‑generates this for textures:
            float4 _BaseMap_ST;   // xy = tiling, zw = offset

            Varyings vert (Attributes IN)
            {
                Varyings OUT;

                float3 pos = IN.positionOS.xyz;

                // Distance from origin (object space)
                float dist = distance(pos, _Origin);

                // Fade out displacement near radius
                float ringMask = saturate(1 - dist / _Radius);

                // Time-based ripple wave
                float wave = sin(dist * _Frequency - _Time.y * _Speed);

                // Final displacement
                float displacement = wave * _Amplitude * ringMask;

                // Move vertex along its normal
                pos += IN.normalOS * displacement;

                OUT.positionHCS = TransformObjectToHClip(pos);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);

                // Apply tiling + offset
                OUT.uv = IN.uv * _BaseMap_ST.xy + _BaseMap_ST.zw;

                return OUT;
            }

            float4 frag (Varyings IN) : SV_Target
            {
                float4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                return tex * _BaseColor;
            }

            ENDHLSL
        }
    }
}