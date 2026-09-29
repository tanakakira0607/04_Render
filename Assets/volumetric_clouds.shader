Shader "Unlit/RenderShader2_2_Volumetric"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}

        _CloudBottom ("Cloud Layer Bottom (World Y)", Float) = 5.0
        _CloudTop ("Cloud Layer Top (World Y)", Float) = 15.0

        _CloudScale ("Cloud Noise Scale", Float) = 0.08
        _WindSpeed ("Wind Speed", Float) = 0.5
        _DensityThreshold ("Density Threshold", Range(0,1)) = 0.55
        _DensityMultiplier ("Density Multiplier", Float) = 3.0

        _StepCount ("Raymarch Steps", Int) = 48
        _LightStepCount ("Light Raymarch Steps", Int) = 6

        _SunDir ("Sun Direction", Vector) = (0.4, 0.6, 0.3, 0)
        _CloudColor ("Cloud Color", Color) = (1,1,1,1)
        _SkyColorTop ("Sky Color (Top)", Color) = (0.15,0.45,0.95,1)
        _SkyColorBottom ("Sky Color (Bottom)", Color) = (0.95,0.95,1.0,1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100
        Cull Off

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
                float3 worldPos : TEXCOORD1;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float _CloudBottom;
            float _CloudTop;
            float _CloudScale;
            float _WindSpeed;
            float _DensityThreshold;
            float _DensityMultiplier;
            int _StepCount;
            int _LightStepCount;
            float4 _SunDir;
            float4 _CloudColor;
            float4 _SkyColorTop;
            float4 _SkyColorBottom;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            // ---------- 3Dハッシュ & バリューノイズ ----------
            float hash3(float3 p)
            {
                p = frac(p * 0.3183099 + float3(0.1,0.1,0.1));
                p *= 17.0;
                return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
            }

            float noise3D(float3 x)
            {
                float3 i = floor(x);
                float3 f = frac(x);
                f = f * f * (3.0 - 2.0 * f);

                float n000 = hash3(i + float3(0,0,0));
                float n100 = hash3(i + float3(1,0,0));
                float n010 = hash3(i + float3(0,1,0));
                float n110 = hash3(i + float3(1,1,0));
                float n001 = hash3(i + float3(0,0,1));
                float n101 = hash3(i + float3(1,0,1));
                float n011 = hash3(i + float3(0,1,1));
                float n111 = hash3(i + float3(1,1,1));

                float nx00 = lerp(n000, n100, f.x);
                float nx10 = lerp(n010, n110, f.x);
                float nx01 = lerp(n001, n101, f.x);
                float nx11 = lerp(n011, n111, f.x);

                float nxy0 = lerp(nx00, nx10, f.y);
                float nxy1 = lerp(nx01, nx11, f.y);

                return lerp(nxy0, nxy1, f.z);
            }

            float fbm3D(float3 p)
            {
                float sum = 0.0;
                float amp = 0.5;
                float freq = 1.0;
                [unroll]
                for (int i = 0; i < 5; i++)
                {
                    sum += noise3D(p * freq) * amp;
                    freq *= 2.02;
                    amp *= 0.5;
                }
                return sum;
            }

            // ---------- 雲の密度(3Dワールド座標が入力) ----------
            float CloudDensity(float3 worldPos)
            {
                // 雲層の高さ方向の正規化(0=底, 1=頂上)
                float h = saturate((worldPos.y - _CloudBottom) / max(_CloudTop - _CloudBottom, 0.001));

                // 上下端をふわっとフェードさせ、綿雲っぽい塊感を出す
                float edgeFade = smoothstep(0.0, 0.15, h) * smoothstep(1.0, 0.75, h);
                if (edgeFade <= 0.001) return 0.0;

                // 風で流れる座標(XZ方向)
                float3 p = worldPos * _CloudScale;
                p.xz += _Time.y * _WindSpeed * float2(1.0, 0.3);

                float n = fbm3D(p);

                float density = saturate((n - _DensityThreshold) * _DensityMultiplier);
                return density * edgeFade;
            }

            // ---------- 太陽方向への簡易ライトマーチ(自己遮蔽) ----------
            float LightMarch(float3 pos, float3 lightDir)
            {
                float stepSize = (_CloudTop - _CloudBottom) / _LightStepCount;
                float densitySum = 0.0;

                for (int i = 0; i < 6; i++)
                {
                    if (i >= _LightStepCount) break;
                    pos += lightDir * stepSize;
                    densitySum += CloudDensity(pos) * stepSize;
                }

                return exp(-densitySum * 1.5);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float3 rayOrigin = _WorldSpaceCameraPos;
                float3 rayDir = normalize(i.worldPos - rayOrigin);
                float3 sunDir = normalize(_SunDir.xyz);

                // 空の背景色(視線の上下角度で決まる。UVではなくレイの向きなので、
                // カメラの向きを変えると正しく空が動く)
                float skyT = saturate(rayDir.y * 0.5 + 0.5);
                float4 sky = lerp(_SkyColorBottom, _SkyColorTop, pow(skyT, 0.6));

                // レイと雲層(2枚のY平面に挟まれたスラブ)の交差区間を計算
                float tBottom = (_CloudBottom - rayOrigin.y) / rayDir.y;
                float tTop    = (_CloudTop    - rayOrigin.y) / rayDir.y;

                float tNear = min(tBottom, tTop);
                float tFar  = max(tBottom, tTop);

                tNear = max(tNear, 0.0);

                // 水平に近いレイ(rayDir.y がほぼ0)は交差計算が不安定なので除外
                if (abs(rayDir.y) < 0.001 || tFar <= tNear)
                {
                    return sky;
                }

                // あまり遠くまでは飛ばさない(パフォーマンスのため距離を制限)
                tFar = min(tFar, tNear + 200.0);

                int steps = max(_StepCount, 1);
                float stepSize = (tFar - tNear) / steps;

                float transmittance = 1.0;
                float3 accumColor = 0;

                for (int s = 0; s < 128; s++)
                {
                    if (s >= steps) break;

                    float t = tNear + stepSize * (s + 0.5);
                    float3 pos = rayOrigin + rayDir * t;

                    float density = CloudDensity(pos);

                    if (density > 0.01)
                    {
                        float lightT = LightMarch(pos, sunDir);

                        // アンビエント(周囲光)+ 直接光。完全な影にならないよう最低照度を確保
                        float3 lighting = _CloudColor.rgb * (lightT * 0.85 + 0.35);

                        float absorption = density * stepSize * 1.2;
                        accumColor += transmittance * absorption * lighting;
                        transmittance *= exp(-absorption);

                        if (transmittance < 0.01) break;
                    }
                }

                float3 finalColor = sky.rgb * transmittance + accumColor;
                return fixed4(finalColor, 1.0);
            }
            ENDCG
        }
    }
}
