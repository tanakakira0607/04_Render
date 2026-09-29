Shader "Unlit/RenderShader2_2" //shader名の宣言
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {} //マテリアルインスペクタに表示されるパラメータを定義
	}
	SubShader
	{
		Tags { "Queue"="Transparent" "RenderType"="Transparent" }

Blend SrcAlpha OneMinusSrcAlpha
Cull Off
ZWrite Off //タグの定義
		LOD 100 //shaderの複数さを定義

		Pass //1回の描画
		{
			CGPROGRAM  //gpuの処理↓
			#pragma vertex vert
			#pragma fragment frag
			// make fog work
			#pragma multi_compile_fog
			
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				UNITY_FOG_COORDS(1)
				float4 vertex : SV_POSITION;
			};

			sampler2D _MainTex;
			float4 _MainTex_ST;
			
			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				UNITY_TRANSFER_FOG(o,o.vertex);
				return o;
			}

			fixed4 frag(v2f i) : SV_Target
{
    float2 uv = i.uv;

    // ビームの中心ライン
    float beam = 1.0 - abs(uv.y - 0.5) * 2.0;

    beam = pow(saturate(beam), 4);

    float3 color =
        float3(1,1,1) * beam +
        float3(0.2,0.7,1.0) * beam;

    return float4(color, beam);
}
			ENDCG
		}
	}
}
