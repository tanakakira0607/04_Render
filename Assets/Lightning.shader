Shader "Custom/URP/Lightning"
{
    Properties
    {
        [HDR] _GlowColor ("Glow Color", Color) = (0.3, 0.5, 1.0, 1)
        [HDR] _CoreColor ("Core Color", Color) = (1.0, 1.0, 1.0, 1)
        _Intensity      ("Intensity", Float) = 3
        _CoreWidth      ("Core Width", Range(0.001, 0.05)) = 0.008
        _GlowWidth      ("Glow Width", Range(0.01, 0.4)) = 0.08
        _Amplitude      ("Zigzag Amplitude", Range(0, 0.4)) = 0.18
        _Frequency      ("Zigzag Frequency", Range(1, 30)) = 7
        _FlickerRate    ("Flicker Rate (per sec)", Float) = 10
        _Seed           ("Seed", Float) = 0
        _BranchStrength ("Branch Strength", Range(0, 1)) = 0.6
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "Lightning"
            Blend One One          // 加算合成
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _GlowColor;
                half4 _CoreColor;
                float _Intensity, _CoreWidth, _GlowWidth;
                float _Amplitude, _Frequency, _FlickerRate, _Seed, _BranchStrength;
            CBUFFER_END

            struct Attributes { float4 posOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings   { float4 posCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.posCS = TransformObjectToHClip(IN.posOS.xyz);
                OUT.uv = IN.uv;
                return OUT;
            }

            float hash11(float n) { return frac(sin(n * 127.1) * 43758.5453); }

            float noise1(float x)
            {
                float i = floor(x);
                float f = frac(x);
                f = f * f * (3.0 - 2.0 * f);
                return lerp(hash11(i), hash11(i + 1.0), f) * 2.0 - 1.0;
            }

            // 3オクターブのfBm（ギザギザ感を出す）
            float fbm(float x)
            {
                return noise1(x) * 0.55 + noise1(x * 2.3) * 0.3 + noise1(x * 5.1) * 0.15;
            }

            // メイン稲妻の横方向オフセット（両端は固定）
            float boltOffset(float y, float t)
            {
                float env = pow(saturate(sin(y * PI)), 0.6);
                return fbm(y * _Frequency + t * 17.3 + _Seed * 31.7) * _Amplitude * env;
            }

            // 1本の線としての明るさ（コア + グロー）
            float2 line_(float d)
            {
                float core = smoothstep(_CoreWidth, 0.0, d);
                float glow = exp(-(d * d) / (_GlowWidth * _GlowWidth));
                return float2(core, glow);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 uv = IN.uv;
                float x = uv.x - 0.5;
                float y = uv.y;

                // フリッカー：一定間隔でパターンが切り替わり、各ステップ内で減衰
                float ft   = _Time.y * _FlickerRate;
                float step_ = floor(ft);
                float t    = step_;
                float life = 1.0 - frac(ft);
                float on   = step(0.25, hash11(step_ + _Seed * 7.0));
                float flick = on * (0.4 + 0.6 * life * life);

                // メインの稲妻
                float mainOff = boltOffset(y, t);
                float2 m = line_(abs(x - mainOff));
                float core = m.x;
                float glow = m.y;

                // 枝分かれ（3本）
                for (int i = 0; i < 3; i++)
                {
                    float fi = (float)i;
                    float by  = 0.2 + hash11(t * 1.7 + fi * 3.1 + _Seed) * 0.55;
                    float dir = hash11(t * 2.3 + fi * 5.7 + _Seed) > 0.5 ? 1.0 : -1.0;
                    float len = 0.25;
                    float dy  = y - by;
                    float mask = step(0.0, dy) * saturate(1.0 - dy / len);

                    float bx = boltOffset(by, t) + dir * dy * 0.7
                             + fbm(dy * _Frequency * 2.0 + fi * 10.0 + t * 9.1) * _Amplitude * 0.35;
                    float2 b = line_(abs(x - bx) * 1.6);
                    core += b.x * mask * _BranchStrength * 0.7;
                    glow += b.y * mask * _BranchStrength * 0.5;
                }

                // 上下端をフェード
                float endFade = smoothstep(0.0, 0.04, y) * smoothstep(1.0, 0.96, y);

                half3 col = _GlowColor.rgb * glow + _CoreColor.rgb * core;
                col *= _Intensity * flick * endFade;

                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}
