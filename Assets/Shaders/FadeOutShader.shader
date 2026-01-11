Shader "Custom/FadeOutShader"
{
    // Simple shader that fades meshes out based on their world-space Y position.
    // _CutoffHeight: world Y where fading starts.
    // _FadeRange: vertical distance over which the fade goes from 1 -> 0.
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _CutoffHeight ("Cutoff Height", Range(-1, 1)) = 0
        _FadeRange ("Fade Range", Range(-1, 1)) = 0.5
    }
    SubShader
    {
        // Make this shader render with alpha blending and no depth writes so transparency sorts correctly
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        LOD 100
        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            // Vertex input: position and UV
            struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; };
            // Interpolators passed to fragment shader
            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float worldY : TEXCOORD1; // world-space Y position
            };

            sampler2D _MainTex; // main texture
            float _CutoffHeight; // world Y where fading begins
            float _FadeRange; // vertical distance over which fade completes

            // Vertex shader: compute world-space Y and clip-space position
            v2f vert (appdata v)
            {
                v2f o;
                float4 worldPos = mul(unity_ObjectToWorld, v.vertex); // object -> world
                o.vertex = UnityObjectToClipPos(v.vertex); // object -> clip
                o.uv = v.uv;
                o.worldY = worldPos.y;
                return o;
            }

            // Fragment shader: sample texture and apply alpha fade based on world Y
            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 col = tex2D(_MainTex, i.uv);
                // Fade: 1.0 at or below _CutoffHeight, 0.0 at _CutoffHeight + _FadeRange
                float fade = 1.0 - smoothstep(_CutoffHeight, _CutoffHeight + _FadeRange, i.worldY);
                col.a *= fade;
                return col;
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
}