Shader "Unlit/blackhole"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _EventHorizonRadius ("Event Horizon Radius", Float) = 1.0
        _DiskInner ("Disk Inner Radius", Float) = 1.2
        _DiskOuter ("Disk Outer Radius", Float) = 2.5
        _GravityStrength ("Gravity Strength", Float) = 0.3
        _SwirlSpeed ("Swirl Speed", Float) = 3.0
        _InfallSpeed ("Infall Stream Speed", Float) = 1.5
        _StreakCount ("Streak Count", Float) = 10.0
    }
    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Cull Off
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
                float3 worldPos : TEXCOORD1;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float _EventHorizonRadius;
            float _DiskInner;
            float _DiskOuter;
            float _GravityStrength;
            float _SwirlSpeed;
            float _InfallSpeed;
            float _StreakCount;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            float StarField(float3 dir)
            {
                return step(0.997,
                    frac(sin(dot(dir.xy, float2(12.9898,78.233))) * 43758.5453));
            }

            fixed4 frag(v2f i) : SV_Target
            {
                // ワールド空間の中心(オブジェクトの位置)
                float3 center = mul(unity_ObjectToWorld, float4(0,0,0,1)).xyz;

                float3 p = _WorldSpaceCameraPos;
                float3 rayDir = normalize(i.worldPos - p);

                bool hitDisk = false;
                float3 diskColor = 0;
                float glow = 0;

                for (int n = 0; n < 150; n++)
                {
                    float distCenter = length(center - p);

                    // イベントホライズン → 完全に黒(不透明)
                    if (distCenter < _EventHorizonRadius)
                    {
                        return fixed4(0, 0, 0, 1);
                    }

                    // 光子リング風グロー(ホライズンのすぐ外側だけに限定)
                    float ringDist = distCenter - _EventHorizonRadius;
                    if (ringDist < 0.3)
                    {
                        // わずかな脈動で「エネルギーが吸い込まれ続けている」感を出す
                        float pulse = 0.9 + 0.1 * sin(_Time.y * 4.0);
                        glow += (0.02 / (ringDist * ringDist + 0.015)) * pulse;
                    }

                    // 降着円盤
                    float3 local = p - center;
                    float rr = length(local.xz);
                    if (abs(local.y) < 0.04 && rr > _DiskInner && rr < _DiskOuter)
                    {
                        float heat = saturate(1.0 - abs(rr - (_DiskInner + _DiskOuter) * 0.5) / ((_DiskOuter - _DiskInner) * 0.5));

                        float angle = atan2(local.z, local.x);

                        // ケプラー回転:内側ほど速く回る(現実の降着円盤の挙動に近い)
                        // これだけでも「渦を巻いて落ちていく」感がはっきり出る
                        float angularSpeed = _SwirlSpeed / sqrt(max(rr, 0.1));
                        float swirl = sin(angle * 6.0 - _Time.y * angularSpeed + rr * 4.0) * 0.15 + 0.85;

                        // 外側→内側へ流れる帯(インフォール・ストリーク)
                        // rrが小さくなるにつれ位相が進む=帯が中心へ吸い込まれていくように見える
                        float diskSpan = _DiskOuter - _DiskInner;
                        float normR = (rr - _DiskInner) / max(diskSpan, 0.0001); // 0(内側)〜1(外側)
                        float streakPhase = normR * _StreakCount - _Time.y * _InfallSpeed * 3.0 - angle * 1.5;
                        float streak = pow(saturate(sin(streakPhase * 3.14159) * 0.5 + 0.5), 3.0);

                        float3 hot  = float3(1.0, 1.0, 0.85);
                        float3 cool = float3(1.0, 0.25, 0.02);
                        diskColor = lerp(cool, hot, heat) * swirl;

                        // 内側に近づくほど帯を明るく強調 → 「吸い込まれて加速し輝きが増す」演出
                        float innerBoost = 1.0 + saturate(1.0 - normR) * 1.5;
                        diskColor += streak * innerBoost * float3(1.0, 0.9, 0.6) * 1.5;

                        // ドップラー風:片側だけ明るく(簡易近似)
                        float doppler = lerp(0.6, 1.6, saturate(local.x / _DiskOuter * 0.5 + 0.5));
                        diskColor *= doppler;

                        hitDisk = true;
                        break;
                    }

                    float d = distCenter - _EventHorizonRadius;
                    p += rayDir * max(d * 0.5, 0.015);

                    // 重力レンズ
                    float3 gravityDir = normalize(center - p);
                    rayDir += gravityDir * (_GravityStrength / max(distCenter * distCenter, 0.3));
                    rayDir = normalize(rayDir);

                    if (distCenter > 40.0) break;
                }

                if (hitDisk)
                {
                    return fixed4(diskColor * 5.0 + glow * float3(1,0.5,0.2) * 0.3, 1);
                }

                float star = StarField(rayDir);
                float3 col = star.xxx + glow * float3(1,0.5,0.2) * 0.5;
                return fixed4(col, saturate(star + glow * 0.5));
            }
            ENDCG
        }
    }
}
