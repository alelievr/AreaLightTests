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
            #include "UnityStandardBRDF.cginc"

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
                float3 center;
                float distance;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float4 _Color;
            float _Smoothness;

            float3 _LightPosition;
            // float4x4 _LightModelMatrix;
            float3 _LightRight;
            float3 _LightUp;
            float3 _LightForward;
            float _Range;
            float _Luminance;
            float _Length;
            float _Width;
            int _LightMode;
            int _AffectDiffuse;
            int _AffectSpecular;

            #define PI 3.14159265

            v2f vert (appdata v)
            {
                v2f o;
                o.positionNDC = UnityObjectToClipPos(v.vertex);
                o.positionWS = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.normalWS = UnityObjectToWorldNormal(v.normal);
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

            float AngleAttenuation(float cosFwd, float lightAngleScale, float lightAngleOffset)
            {
                return saturate(cosFwd * lightAngleScale + lightAngleOffset);
            }

            // Combines SmoothWindowedDistanceAttenuation() and SmoothAngleAttenuation() in an efficient manner.
            // distances = {d, d^2, 1/d, 0}
            float PunctualLightAttenuation(float4 distances, float rangeAttenuationScale, float rangeAttenuationBias, float lightAngleScale, float lightAngleOffset)
            {
                float distSq   = distances.y;
                float distRcp  = distances.z;
                // float cosFwd   = distances.w * distRcp;

                float attenuation = min(distRcp, 1.0 / PUNCTUAL_LIGHT_THRESHOLD);
                attenuation *= DistanceWindowing(distSq, rangeAttenuationScale, rangeAttenuationBias);
                // For point light model, we don't need angle attenuation
                // attenuation *= AngleAttenuation(cosFwd, lightAngleScale, lightAngleOffset);

                // Effectively results in SmoothWindowedDistanceAttenuation(...) * SmoothAngleAttenuation(...).
                return Sq(attenuation);
            }
            
            float EvalutePunctualLightAttenuation(float3 lightToSample, float3 positionWS, float lightDistance)
            {
                float  dist   =  lightDistance;
                float  distSq    = dist * dist;
                float  distRcp = rcp(dist);

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

                return PunctualLightAttenuation(distances, scale, bias, angleScale, angleOffset);
            }

            float FastACosPos(float inX)
            {
                float x = abs(inX);
                float res = (0.0468878 * x + -0.203471) * x + 1.570796; // p(x)
                res *= sqrt(1.0 - x);

                return res;
            }

            // Ref: https://seblagarde.wordpress.com/2014/12/01/inverse-trigonometric-functions-gpu-optimization-for-amd-gcn-architecture/
            // Input [-1, 1] and output [0, PI]
            // 12 VALU
            float FastACos(float inX)
            {
                float res = FastACosPos(inX);

                return (inX >= 0) ? res : PI - res; // Undo range reduction
            }

            // Reference: An Area - Preserving Parametrization for Spherical Rectangles  (section 4.2)
            float RectangleSolidAngle(float3 worldPos, float3  p0, float3 p1, float3 p2, float3 p3)
            {
                float3 v0 = p0 - worldPos;
                float3 v1 = p1 - worldPos;
                float3 v2 = p2 - worldPos;
                float3 v3 = p3 - worldPos;

                float3 n0 = normalize(cross(v0, v1));
                float3 n1 = normalize(cross(v1, v2));
                float3 n2 = normalize(cross(v2, v3));
                float3 n3 = normalize(cross(v3, v0));

                float g0 = FastACos(dot(-n0, n1));
                float g1 = FastACos(dot(-n1, n2));
                float g2 = FastACos(dot(-n2, n3));
                float g3 = FastACos(dot(-n3, n0));

                return g0 + g1 + g2 + g3 - 2.0f * PI;
            }

            float ComputeWrapLighting(float3 N, float3 L, float w)
            {
                // Energy conserving wrapped diffuse: http://blog.stevemcauley.com/2011/12/03/energy-conserving-wrapped-diffuse/
                return saturate((dot(N, L) + w) / ((1 + w) * (1 + w)));
            }

            float star(float3 v)
            {
                float r = 1.5 + 0.5 * cos(atan2(v.y, v.x) * 5.0 + PI / 2.0);

                r *= length(v);
                return r;
            }

            float dot2( in float3 v )
            {
                return dot(v,v);
            }

            float dot2( in float2 v )
            {
                return dot(v,v);
            }
            
            // SDF from: http://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm
            float sdBoxSq(float3 p, float3 b)
            {
                return dot2(max(abs(p)-b,0.0));
            }

            float sdTorusSq(float3 p, RaymarchData data)
            {
                float2 q = float2(length(p.xz) - _Range, p.y);
                return dot(q, q);
            }

            float sdAALineSq(float3 p, RaymarchData data)
            {
                return dot2(max(abs(p) - float3(_Length / 2.0, 0, 0), 0.0));
            }

            float sdCrossSq(float3 p, float t)
            {
                float d = abs(p.x) + abs(p.y) + abs(p.z) - t;
                return d * d;
            }

            float sdRectSq(float3 p, float3 size)
            {
                float3 f = max(0, abs(p) - size);
                return dot(f, f);
            }

            #define CROSS       0
            #define TORUS       1
            #define QUAD        2
            #define DEFAULT     -1

            float sdLightSq(float3 p, RaymarchData data)
            {
                switch (_LightMode)
                {
                    case TORUS:
                        return sdTorusSq(p, data);
                    case CROSS:
                        return sdCrossSq(p, 0.2);
                    case QUAD:
                        return sdRectSq(p, float3(_Length / 2, _Width / 2, 0));
                    default:
                        return sdAALineSq(p, data);
                }
            }

            float3 ConstructLightPosition(float3 positionLS, float3 normalLS, RaymarchData data, out float lightDistance)
            {
                lightDistance = sqrt(sdLightSq(positionLS, data));
                
                float3 p = positionLS + normalLS * lightDistance;
                float distSq = sdLightSq(p, data);
                float2 delta = float2(0.01, 0);

                // light direction from sdf normal approximation
                float3 lightDirection = normalize(float3(
                    distSq - sdLightSq(p - delta.xyy, data),
                    distSq - sdLightSq(p - delta.yxy, data),
                    distSq - sdLightSq(p - delta.yyx, data)
                ));

                return p - lightDirection * sqrt(distSq);
            }

            void BSDF(v2f i, float3 lightDirection, out float diffuseBSDF, out float specularBSDF)
            {
                diffuseBSDF = 1.0 / PI;

                float LdotH = 0;

                float3 viewDir = normalize(_WorldSpaceCameraPos - i.positionWS);
                float3 halfVector = normalize(-lightDirection + viewDir);

                specularBSDF = pow(DotClamped(halfVector, i.normalWS), _Smoothness * 100);

                if (!_AffectDiffuse)
                    diffuseBSDF = 0;
                if (!_AffectSpecular)
                    specularBSDF = 0;
            }


float SmoothDistanceWindowing(float distSquare, float rangeAttenuationScale, float rangeAttenuationBias)
{
    float factor = DistanceWindowing(distSquare, rangeAttenuationScale, rangeAttenuationBias);
    return Sq(factor);
}

float EllipsoidalDistanceAttenuation(float3 unL, float3 axis, float invAspectRatio,
                                    float rangeAttenuationScale, float rangeAttenuationBias)
{
    // Project the unnormalized light vector onto the axis.
    float projL = dot(unL, axis);

    // Transform the light vector so that we can work with
    // with the ellipsoid as if it was a sphere with the radius of light's range.
    float diff = projL - projL * invAspectRatio;
    unL -= diff * axis;

    float sqDist = dot(unL, unL);
    return SmoothDistanceWindowing(sqDist, rangeAttenuationScale, rangeAttenuationBias);
}


            fixed4 frag (v2f i) : SV_Target
            {
                i.normalWS = normalize(i.normalWS);
                fixed3 diffuse = tex2D(_MainTex, i.uv) * _Color;
                float3 specular = float3(1, 1, 1); // white specular color
                RaymarchData data;

                float halfLength = _Length * 0.5;
                data.p0 = float3(-halfLength, 0, 0);
                data.p1 = float3(halfLength, 0, 0);
                data.radius = 0.5;

                float3x3 lightMatrix = float3x3(_LightRight, _LightUp, _LightForward);

                float3 positionLS = mul(lightMatrix, i.positionWS - _LightPosition);
                float3 normalLS = mul(lightMatrix, i.normalWS);

                float lightDistance;
                float3 lightPosition = ConstructLightPosition(positionLS, normalLS, data, lightDistance);
                float3 lightToSample = positionLS - lightPosition;

                float3 viewDir = normalize(_WorldSpaceCameraPos - i.positionWS);
                float3 specularDirection = reflect(viewDir, i.normalWS);

                // float3 specularDirectionLS = mul(_LightModelMatrix, specularDirection);

                // float3 specularLightPosition = ConstructLightPosition(positionLS, specularDirectionLS, data, lightDistance);
                // float3 specularLightDirection = normalize(positionLS - specularLightPosition);
            
                // float invAspectRatio = saturate(_Range / (_Range + (0.5 * _Length)));
                // float eintensity = EllipsoidalDistanceAttenuation(_LightPosition - i.positionWS, _LightRight, invAspectRatio,
                //                                      1.0f / (_Range * _Range),
                //                                     1.0);
                float eintensity = EvalutePunctualLightAttenuation(lightToSample, positionLS, lightDistance);

                float3 specularLightDirection = float3(0, 0, 0);

                float diffuseBSDF, specularBSDF;
                BSDF(i, specularLightDirection, diffuseBSDF, specularBSDF);

                // float NdotL = ComputeWrapLighting(normalLS, normalize(-lightToSample), 0.0);
                float NdotL = saturate(dot(normalLS, normalize(-lightToSample)));

                if (_LightMode == QUAD)
                {
                    float f = saturate(-positionLS.z);
                    diffuseBSDF *= f;
                }

                float intensity = NdotL * eintensity;//EvalutePunctualLightAttenuation(lightToSample, positionLS, lightDistance);

                diffuse *= diffuseBSDF * intensity;
                diffuse *= _Luminance;

                specular *= specularBSDF;

                return float4(diffuse + specular, 1);
            }
            ENDCG
        }
    }
}