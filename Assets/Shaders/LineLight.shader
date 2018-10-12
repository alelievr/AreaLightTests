// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

Shader "Custom/LineLight"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1, 1, 1, 1)
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
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 positionNDC : SV_POSITION;
                float3 normal : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float4 _Color;
            float3 _LightPosition;
            float3 _LightRight;
            float3 _LightUp;
            float4 _LightForward;
            float _Range;
            float _Luminance;
            float _Length;

            v2f vert (appdata v)
            {
                v2f o;
                o.positionNDC = UnityObjectToClipPos(v.vertex);
                o.positionWS = mul (unity_ObjectToWorld, v.vertex).xyz;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.normal = mul(unity_ObjectToWorld, float4(v.normal, 0));
                return o;
            }

            float Sq(float f)
            {
                return f * f;
            }

            // Punctual attenuation from HDRP
            float DistanceWindowing(float distSquare, float rangeAttenuationScale, float rangeAttenuationBias)
            {
                // If (range attenuation is enabled)
                //   rangeAttenuationScale = 1 / r^2
                //   rangeAttenuationBias  = 1
                // Else
                //   rangeAttenuationScale = 2^12 / r^2
                //   rangeAttenuationBias  = 2^24
                return saturate(rangeAttenuationBias - Sq(distSquare * rangeAttenuationScale));
            }

            // Square the result to smoothen the function.
            float AngleAttenuation(float cosFwd, float lightAngleScale, float lightAngleOffset)
            {
                return saturate(cosFwd * lightAngleScale + lightAngleOffset);
            }

            #define PUNCTUAL_LIGHT_THRESHOLD 0.01 // 1cm (in Unity 1 is 1m)


            // Combines SmoothWindowedDistanceAttenuation() and SmoothAngleAttenuation() in an efficient manner.
            // distances = {d, d^2, 1/d, d_proj}, where d_proj = dot(lightToSample, lightData.forward).
            float PunctualLightAttenuation(float4 distances, float rangeAttenuationScale, float rangeAttenuationBias,
                                        float lightAngleScale, float lightAngleOffset)
            {
                float distSq   = distances.y;
                float distRcp  = distances.z;
                float distProj = distances.w;
                float cosFwd   = distProj * distRcp;

                float attenuation = min(distRcp, 1.0 / PUNCTUAL_LIGHT_THRESHOLD);
                attenuation *= DistanceWindowing(distSq, rangeAttenuationScale, rangeAttenuationBias);
                attenuation *= AngleAttenuation(cosFwd, lightAngleScale, lightAngleOffset);

                // Effectively results in SmoothWindowedDistanceAttenuation(...) * SmoothAngleAttenuation(...).
                return Sq(attenuation);
            }

            // Distance of point from line:
            float3 GetNearestPointLine(float3 a, float3 b, float3 p)
            {
                float3 n = b - a;
                float3 pa = a - p;
                float n2 = dot(n, n);
                float abd = dot(pa, n);
                float t = abd / n2;

                return a - n * t;
            }

            // Distance of point from segment:
            float3 GetNearestPointSegment(float3 a, float3 b, float3 p)
            {
                if (dot((a - b), (a - p)) < 0)
                    return a;
                else if (dot((b - a), (b - p)) < 0)
                    return b;
                else
                    return GetNearestPointLine(a, b, p);
            }

            float sdCapsule( float3 p, float3 a, float3 b, float r )
            {
                float3 pa = p - a, ba = b - a;
                float h = saturate(dot(pa,ba)/dot(ba,ba));
                return length(pa - ba * h) - r;
            }

            float sdTorus( float3 p, float2 t )
            {
                float2 q = float2(length(p.xz)-t.x,p.y);
                return length(q)-t.y;
            }

            float sdCross(float3 p, float t)
            {
                return abs(p.x) + abs(p.y) + abs(p.z) - t;
            }

            // 1D spherical line integration: http://advances.realtimerendering.com/s2016/s2016_ltc_rnd.pdf
            float SphericalLine(float3 p0, float3 p1)
            {
                float p0p1 = p0 * p1;

                return acos(dot(p0, p1));
            }

            fixed4 frag (v2f i) : SV_Target
            {
                i.normal = normalize(i.normal);
                fixed4 col = tex2D(_MainTex, i.uv) * _Color;

                float3 p0 = _LightPosition - _LightRight / 2 * _Length;
                float3 p1 = _LightPosition + _LightRight / 2 * _Length;
                
                float3 p2 = _LightPosition - _LightForward / 2 * _Length;
                float3 p3 = _LightPosition + _LightForward / 2 * _Length;

#if 1
                float3 lightPosition = GetNearestPointSegment(p0, p1, i.positionWS);
#else
                float3 near = min(GetNearestPointSegment(p0, p1, i.positionWS), );
                float3 lightToSample = i.positionWS - near;
#endif
            
                float3 lightToSample = i.positionWS - lightPosition;

                // Energy conserving wrapped diffuse: http://blog.stevemcauley.com/2011/12/03/energy-conserving-wrapped-diffuse/
                float w = 0;//SphericalLine(p0, p1);
                float3 L = normalize(lightPosition - i.positionWS);
                float wrapedNdotL = (dot(i.normal, L) + w) / ((1 + w) * (1 + w));

                col *= saturate(wrapedNdotL);

                float3 unL     = -lightToSample;
                float  distSq  = dot(unL, unL);
                // float distSq   =  Sq(sdCapsule(i.positionWS, p0, p1, 0));
                // float distSq   =  Sq(sdTorus(i.positionWS - _LightPosition, 2));
                // float distSq   =  Sq(sdCross(i.positionWS - _LightPosition, 0));
                float  distRcp = rsqrt(distSq);
                float  dist    = distSq * distRcp;

                float4 distances = float4(
                    dist,
                    distSq,
                    distRcp,
                    dot(lightToSample, _LightForward)
                );

                float scale = 1.0f / (_Range * _Range);
                float bias  = 1.0f;
                float angleScale = 0.0f;
                float angleOffset = 1.0f;

                col *= PunctualLightAttenuation(distances, scale, bias, angleScale, angleOffset);
                col *= _Luminance;

                return float4(col.xyz, 1);
            }
            ENDCG
        }
    }
}
