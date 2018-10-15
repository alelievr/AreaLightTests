// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

Shader "Custom/LineLight"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1, 1, 1, 1)
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
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
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 positionNDC : SV_POSITION;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float4 tangentWS : TANGENT;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float4 _Color;
            float _Smoothness;

            float3 _LightPosition;
            float3 _LightRight;
            float3 _LightUp;
            float4 _LightForward;
            float _Range;
            float _Luminance;
            float _Length;

            #define PI 3.14159265

            v2f vert (appdata v)
            {
                v2f o;
                o.positionNDC = UnityObjectToClipPos(v.vertex);
                o.positionWS = mul (unity_ObjectToWorld, v.vertex).xyz;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.normalWS = mul(unity_ObjectToWorld, float4(v.normal, 0));
                o.tangentWS = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
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

            #define PUNCTUAL_LIGHT_THRESHOLD 0.01 // 1cm (in Unity 1 is 1m)


            // Combines SmoothWindowedDistanceAttenuation() and SmoothAngleAttenuation() in an efficient manner.
            // distances = {d, d^2, 1/d, 0}
            float PunctualLightAttenuation(float4 distances, float rangeAttenuationScale, float rangeAttenuationBias)
            {
                float distSq   = distances.y;
                float distRcp  = distances.z;

                float attenuation = min(distRcp, 1.0 / PUNCTUAL_LIGHT_THRESHOLD);
                attenuation *= DistanceWindowing(distSq, rangeAttenuationScale, rangeAttenuationBias);
                // For point light model, we don't need angle attenuation
                // attenuation *= AngleAttenuation(cosFwd, lightAngleScale, lightAngleOffset);

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

            float sdLine(float3 p, float3 a, float3 b)
            {
                float3 pa = p - a, ba = b - a;
                float h = saturate(dot(pa,ba)/dot(ba,ba));
                float3 t = (pa - ba * h);
                return sqrt(dot(t, t));
            }

            float sdLineSq(float3 p, float3 a, float3 b)
            {
                return pow(sdLine(p, a, b), 2);
            }

            float sdTorus(float3 p, float2 t)
            {
                float2 q = float2(length(p.xz)-t.x,p.y);
                return length(q)-t.y;
            }

            float sdCross(float3 p, float t)
            {
                return abs(p.x) + abs(p.y) + abs(p.z) - t;
            }

            float star(float2 v)
            {
                float r = 1.5 + 0.5 * cos(atan2(v.y, v.x) * 5.0 + PI / 2.0);

                r *= length(v);
                return r;
            }

            // 1D spherical line integration: http://advances.realtimerendering.com/s2016/s2016_ltc_rnd.pdf
            float SphericalLine(float3 p0, float3 p1)
            {
                float p0p1 = p0 * p1;

                return acos(dot(p0, p1));
            }

            float EvalutePunctualLightAttenuation(float3 positionWS, float3 p0, float3 p1)
            {
                float distSq   =  sdLineSq(positionWS, p0, p1);
                // float distSq   =  Sq(sdTorus(positionWS - _LightPosition, 2));
                // float distSq   =  Sq(sdCross(positionWS - _LightPosition, 0));
                float  distRcp = rsqrt(distSq);
                float  dist    = distSq * distRcp;

                float4 distances = float4(
                    dist,
                    distSq,
                    distRcp,
                    0
                );

                float scale = 1.0f / (_Range * _Range);
                float bias  = 1.0f;

                return PunctualLightAttenuation(distances, scale, bias);
            }

            float ComputeWrapLighting(float3 N, float3 lightToSample)
            {
                // Energy conserving wrapped diffuse: http://blog.stevemcauley.com/2011/12/03/energy-conserving-wrapped-diffuse/
                float w = 0;//SphericalLine(p0, p1);
                float3 L = normalize(-lightToSample);
                float wrappedNdotL = (dot(N, L) + w) / ((1 + w) * (1 + w));

                return saturate(wrappedNdotL);
            }

            struct LightRaymarchResult
            {
                float forwardDistance;
                float backDistance;
                float3 center;
                float delta;
            };

            LightRaymarchResult RaymarchToLight(float3 p, float3 direction, float3 p0, float3 p1)
            {
                LightRaymarchResult results;
                float   t = 0.001;
                float3  startPoint = p;
                float   distance = 0;
                float3  oldPosition;
                float   oldDistance;

                for (uint i = 0; i < 2; i++)
                {
                    oldPosition = p;
                    oldDistance = distance;

                    p = startPoint + direction * t;
                    distance = sdLine(p, p0, p1);
                    t += distance;
                }

                results.forwardDistance = distance;
                results.backDistance = oldDistance;
                results.delta = length(p - oldPosition) / 2.0;
                results.center = oldPosition + (p - oldPosition) * 0.5;
                return results;
            }

            float3 ConstructLightPosition(v2f i, float3 p0, float3 p1)
            {
                LightRaymarchResult results = RaymarchToLight(i.positionWS, i.normalWS, p0, p1);

                float3 reconstructedUp = cross(i.normalWS, i.tangentWS.xyz);

                // No need to recompute them, it's already done during the raymarching
                // float3 m0 = results.center + results.delta * i.normal;
                // float3 m1 = results.center - results.delta * i.normal;
                float3 m2 = results.center + results.delta * i.tangentWS;
                float3 m3 = results.center - results.delta * i.tangentWS;
                float3 m4 = results.center + results.delta * reconstructedUp;
                float3 m5 = results.center - results.delta * reconstructedUp;

                float3 lightDirection = normalize(
                    i.normalWS * (results.forwardDistance - results.backDistance) +
                    i.tangentWS * (sdLine(m2, p0, p1) - sdLine(m3, p0, p1)) +
                    reconstructedUp * (sdLine(m4, p0, p1) - sdLine(m5, p0, p1))
                );

                return results.center + lightDirection * sdLine(results.center, p0, p1);
            }

            float F_Schlick(float f0, float u)
            {
                float x = 1.0 - u;
                float x2 = x * x;
                float x5 = x * x2 * x2;
                return (1 - f0) * x5 + f0;
            }

            void BSDF(out float diffuseBSDF, out float specularBSDF)
            {
                diffuseBSDF = 1.0 / PI;

                float LdotH = 0;

                specularBSDF = F_Schlick(_Smoothness, LdotH);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                i.normalWS = normalize(i.normalWS);
                fixed3 diffuse = tex2D(_MainTex, i.uv) * _Color;

                float halfLength = _Length * 0.5;
                float3 p0 = _LightPosition - _LightRight * halfLength;
                float3 p1 = _LightPosition + _LightRight * halfLength;

                float3 lightPosition = ConstructLightPosition(i, p0, p1);
                // float3 lightPosition = GetNearestPointSegment(p0, p1, i.positionWS);
                float3 lightToSample = i.positionWS - lightPosition;
                return normalize(lightPosition).xyzx * 0.5 + 0.5;
                // return normalize(lightToSample).xyzx * 0.5 + 0.5;
                // return saturate(dot(i.normalWS, normalize(lightToSample)));

                float diffuseBSDF, specularBSDF;
                BSDF(diffuseBSDF, specularBSDF);

                // return float4(i.normalWS * 0.5 + 0.5, 1);
                return float4(normalize(-lightToSample) * 0.5 + 0.5, 1);
                // return length(lightToSample).xxxx / 10;

                float intensity = saturate(dot(i.normalWS, normalize(-lightToSample)));
                intensity *= EvalutePunctualLightAttenuation(i.positionWS, p0, p1);

                diffuse *= diffuseBSDF * intensity;
                diffuse *= _Luminance;

                //TODO: specular

                return float4(diffuse, 1);
            }
            ENDCG
        }
    }
}
