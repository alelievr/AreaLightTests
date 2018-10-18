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
            
            struct RaymarchData
            {
                float radius;
                float3 p0;
                float3 p1;
            };

            struct LightRaymarchResult
            {
                float forwardDistance;
                float backDistance;
                float3 center;
                float delta;
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

            // Punctual attenuation functions from HDRP

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
            
            float sdLight(float3 p, RaymarchData data);
            float EvalutePunctualLightAttenuation(float3 positionWS, RaymarchData data)
            {
                float  dist   =  sdLight(positionWS, data);
                float  distSq    = dist * dist;
                float  distRcp = rcp(dist);

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
            
            float star(float3 v)
            {
                float r = 1.5 + 0.5 * cos(atan2(v.y, v.x) * 5.0 + PI / 2.0);

                r *= length(v);
                return r;
            }

            // SDF from: http://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm
            float dot2( in float3 v ) { return dot(v,v); }
            float sdQuad( float3 p, float3 a, float3 b, float3 c, float3 d )
            {
                float3 ba = b - a; float3 pa = p - a;
                float3 cb = c - b; float3 pb = p - b;
                float3 dc = d - c; float3 pc = p - c;
                float3 ad = a - d; float3 pd = p - d;
                float3 nor = cross( ba, ad );

                return sqrt(
                (sign(dot(cross(ba,nor),pa)) +
                sign(dot(cross(cb,nor),pb)) +
                sign(dot(cross(dc,nor),pc)) +
                sign(dot(cross(ad,nor),pd))<3.0)
                ?
                min( min( min(
                dot2(ba*clamp(dot(ba,pa)/dot2(ba),0.0,1.0)-pa),
                dot2(cb*clamp(dot(cb,pb)/dot2(cb),0.0,1.0)-pb) ),
                dot2(dc*clamp(dot(dc,pc)/dot2(dc),0.0,1.0)-pc) ),
                dot2(ad*clamp(dot(ad,pd)/dot2(ad),0.0,1.0)-pd) )
                :
                dot(nor,pa)*dot(nor,pa)/dot2(nor) );
            }

            float sdTorus(float3 p, RaymarchData data)
            {
                p -= _LightPosition;
                float2 q = float2(length(p.xz) - _Range, p.y);
                return length(q);
            }

            float sdLine(float3 p, RaymarchData data)
            {
                float3 pa = p - data.p0, ba = data.p1 - data.p0;
                float h = saturate(dot(pa,ba)/dot(ba,ba));
                float3 t = (pa - ba * h);
                return length(pa - ba * h);
            }

            float sdCross(float3 p, float t)
            {
                p -= _LightPosition;
                return abs(p.x) + abs(p.y) + abs(p.z) - t;
            }

            #define CROSS       0
            #define TORUS       1
            #define QUAD        2
            #define DEFAULT     -1
            
            #define SDF DEFAULT

            float sdLight(float3 p, RaymarchData data)
            {
                switch (SDF)
                {
                    case TORUS:
                        return sdTorus(p, data);
                    case CROSS:
                        return sdCross(p, 0.2);
                    case QUAD:
                        float3 a = data.p0;
                        float3 b = data.p1;
                        float3 c = b + _LightForward * _Range;
                        float3 d = a + _LightForward * _Range;
                        return sdQuad(p, a, b, c, d);
                    default:
                        return sdLine(p, data);
                }
            }

            LightRaymarchResult RaymarchToLight(float3 p, float3 direction, RaymarchData data)
            {
                LightRaymarchResult results;
                float   t = 0.001;
                float3  startPoint = p;
                float   distance = 0;
                float3  oldPosition;
                float   oldDistance;

                for (uint i = 0; i < 6; i++)
                {
                    oldPosition = p;
                    oldDistance = distance;

                    p = startPoint + direction * t;
                    distance = sdLight(p, data);
                    if (oldDistance <= distance)
                        break ;
                    t += distance;
                }

                results.forwardDistance = distance;
                results.backDistance = oldDistance;
                results.center = oldPosition + (p - oldPosition) * 0.5;
                return results;
            }

            float3 ConstructLightPosition(v2f i, RaymarchData data)
            {
                LightRaymarchResult results = RaymarchToLight(i.positionWS, i.normalWS, data);
                float2 delta = float2(0.01, 0);

                float3 lightDirection = normalize(float3(
                    sdLight(results.center + delta.xyy, data) - sdLight(results.center - delta.xyy, data),
                    sdLight(results.center + delta.yxy, data) - sdLight(results.center - delta.yxy, data),
                    sdLight(results.center + delta.yyx, data) - sdLight(results.center - delta.yyx, data)
                ));

                return results.center - lightDirection * sdLight(results.center, data);
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

                RaymarchData data;

                data.radius = 0.5;
                data.p0 = p0;
                data.p1 = p1;

                float3 lightPosition = ConstructLightPosition(i, data);
                // float3 lightPosition = GetNearestPointSegment(p0, p1, i.positionWS);
                // return float4(lightPosition * 0.5 + 0.5, 1);
                float3 lightToSample = i.positionWS - lightPosition;
                // return normalize(lightPosition).xyzx * 0.5 + 0.5;
                // return normalize(lightToSample).xyzx * 0.5 + 0.5;
                // return saturate(dot(i.normalWS, normalize(lightToSample)));

                float diffuseBSDF, specularBSDF;
                BSDF(diffuseBSDF, specularBSDF);

                // return float4(i.normalWS * 0.5 + 0.5, 1);
                // return float4(normalize(-lightToSample) * 0.5 + 0.5, 1);
                // return length(lightToSample).xxxx / 10;

                float intensity = saturate(dot(i.normalWS, normalize(-lightToSample)));
                intensity *= EvalutePunctualLightAttenuation(i.positionWS, data);

                diffuse *= diffuseBSDF * intensity;
                diffuse *= _Luminance;

                //TODO: specular

                return float4(diffuse, 1);
            }
            ENDCG
        }
    }
}
