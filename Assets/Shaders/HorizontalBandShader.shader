Shader "Custom/HorizontalBandShader"
{
    // Horizontal band shader with optional audio-reactive modulation.
    // If you use an AudioAnalyzer that sets the global float '_AudioLevel',
    // bands will react to the audio (speed and color intensity).
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _BandColor1 ("Band Color 1", Color) = (1,0,0,1)
        _BandColor2 ("Band Color 2", Color) = (0,0,1,1)
        _BandsThickness ("Bands Thickness", Range(0,0.5)) = 0.05
        _BandsSpeed ("Bands Speed", Range(-10,10)) = 1
        _BandCurvature ("Band Curvature", Range(0,0.5)) = 0.05
        _CurvatureFreq ("Curvature Frequency", Range(0.1,20)) = 6.0
        _CurvatureSpeed ("Curvature Speed", Range(-10,10)) = 1.0
        _AudioCurvBoost ("Audio Curvature Boost", Range(0,10)) = 2.0
        _AudioColorBoost ("Audio Color Boost", Range(0,2)) = 0.2
        _ArcMode ("Arc Mode (0=Semicircle,1=Cosine,2=Sine)", Range(0,2)) = 1
        _ColorOscAmp ("Color Oscillation Amplitude", Range(0,1)) = 0
        _ColorOscFreq ("Color Oscillation Frequency", Range(0,20)) = 10
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _BandColor1;
            float4 _BandColor2;
            float _BandsThickness;
            float _BandsSpeed;
            // Curvature controls: amplitude, frequency, animation speed and audio boost
            float _BandCurvature;    // how tall the arc is
            float _CurvatureFreq;    // how many arcs across the X axis
            float _CurvatureSpeed;   // animation speed of the arcs (phase)
            float _AudioCurvBoost;   // multiplier to boost curvature when audio is present
            float _AudioColorBoost;  // amount to boost base color by audio (multiplier, preserves hue)
            float _ArcMode; // 0=Semicircle, 1=Cosine bell, 2=Sine bell
            // Color oscillation controls (default 0 = disabled)
            float _ColorOscAmp;    // amplitude of per-channel oscillation (0..1)
            float _ColorOscFreq;   // frequency of per-channel oscillation
            // Global audio level (0..1) written by scripts via Shader.SetGlobalFloat("_AudioLevel", value)
            float _AudioLevel; // optional — use to modulate speed/color if present

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float2 uv = i.uv;
                // Read global audio level (0..1). If not set, _AudioLevel will typically be 0.
                float audio = saturate(_AudioLevel);
                // Base vertical band motion (speed reduced by 10x)
                float baseY = uv.y + (_BandsSpeed * 0.1) * _Time.y;
                float baseBandPos = frac(baseY / _BandsThickness);
                // Compute repeated semi-circular arcs across X by using frac() + a semicircle function (arc animation speed reduced by 10x)
                float phase = (_CurvatureSpeed * 0.1) * _Time.y;
                float xf = frac(uv.x * _CurvatureFreq + phase);
                float x = (xf - 0.5) * 2.0; // -1..1 across each repeated cell

                // Select arc shape:
                //  - 0: parabola (1 - x^2)
                //  - 1: cosine bell (0.5*(1+cos(pi*x)))
                //  - 2: sine bell (sin((1-abs(x))*pi/2))
                float arc;
                if (_ArcMode < 0.5)
                {
                    // Parabola: sharper central peak, quicker falloff than semicircle
                    arc = saturate(1.0 - x * x); // parabola
                }
                else if (_ArcMode < 1.5)
                {
                    arc = 0.5 * (1.0 + cos(x * UNITY_PI)); // cosine bell, 0 at |x|=1, 1 at x=0
                }
                else
                {
                    arc = sin((1.0 - abs(x)) * (UNITY_PI * 0.5)); // sine-based bell
                }
                // Arc offset scaled by curvature amount and optionally boosted by audio
                float arcOffset = arc * _BandCurvature * (1.0 + audio * _AudioCurvBoost);
                // Optionally modulate arc per-band so the arc effect varies across bands
                arcOffset *= (1.0 - baseBandPos);
                // Final band offset includes curvature
                float bandOffset = baseY + arcOffset;
                float bandPos = frac(bandOffset / _BandsThickness);
                fixed4 color = lerp(_BandColor1, _BandColor2, bandPos);

                // Keep color lively and audio-reactive
                // Use multiplicative boost to preserve hue; safer than adding a constant to each channel
                color.rgb *= (1.0 + audio * _AudioColorBoost);
                // Soft clamp: reduce slightly if the max channel would exceed 0.99 to avoid pure white
                float maxC = max(max(color.r, color.g), color.b);
                if (maxC > 0.99)
                    color.rgb *= (0.99 / maxC);

                // Optional per-channel oscillation (set _ColorOscAmp = 0 to disable stripes)
                float oscAmp = _ColorOscAmp * (0.1 + audio * 0.2);
                float oscFreq = _ColorOscFreq;
                if (oscAmp > 0.0)
                {
                    color.r += sin(uv.x * oscFreq + _Time.y * (5 + audio * 10)) * oscAmp;
                    color.g += cos(uv.x * oscFreq + _Time.y * (5 + audio * 10)) * oscAmp;
                    color.b += sin(uv.x * oscFreq + _Time.y * (5 + audio * 10)) * oscAmp;
                }

                // Clamp final color to avoid bright pink/yellow overflow artifacts
                color = saturate(color);

                return tex2D(_MainTex, uv) * color;
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
}