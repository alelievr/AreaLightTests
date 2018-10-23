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
            float4x4 _LightModelMatrix;
            float3 _LightRight;
            float3 _LightUp;
            float4 _LightForward;
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
            
            float EvalutePunctualLightAttenuation(float3 positionWS, float lightDistance)
            {
                float  dist   =  lightDistance;
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

            float star(float3 v)
            {
                float r = 1.5 + 0.5 * cos(atan2(v.y, v.x) * 5.0 + PI / 2.0);

                r *= length(v);
                return r;
            }


            // SDF from: http://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm
            float dot2( in float3 v ) { return dot(v,v); }
            float sdQuadSq( float3 p, float3 a, float3 b, float3 c, float3 d )
            {
                float3 ba = b - a; float3 pa = p - a;
                float3 cb = c - b; float3 pb = p - b;
                float3 dc = d - c; float3 pc = p - c;
                float3 ad = a - d; float3 pd = p - d;
                float3 nor = cross( ba, ad );

                return (
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

            float sdRectSq(float3 p, float2 size)
            {
                float3 f = abs(p) - float3(size.x, 0, size.y);
                float d_box = dot2(max(f, 0.0));

                return d_box;

                float a = abs(1.0 / size.x);
                a = a*a*a*a*a*a*a*a*a;

                return d_box + (a / max(1.0, p.y));
                
                d_box += a / p.y;
                
                return d_box;
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
                        // TODO: replace by a sdbox
                        float3 a = data.p0;
                        float3 b = data.p1;
                        float3 c = b + _LightForward * _Range;
                        float3 d = a + _LightForward * _Range;
                        // return sdBoxSq(p, float3(_Length / 2, 0, _Width / 2));
                        return sdRectSq(p, float2(_Length / 2, _Width / 2));
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

            float F_Schlick(float f0, float u)
            {
                float x = 1.0 - u;
                float x2 = x * x;
                float x5 = x * x2 * x2;
                return (1 - f0) * x5 + f0;
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

            fixed4 frag (v2f i) : SV_Target
            {
                i.normalWS = normalize(i.normalWS);
                fixed3 diffuse = tex2D(_MainTex, i.uv) * _Color;
                float3 specular = float3(1, 1, 1); // white specular color

                float halfLength = _Length * 0.5;
                float3 p0 = float3(-halfLength, 0, 0);
                float3 p1 = float3(halfLength, 0, 0);

                RaymarchData data;

                data.radius = 0.5;
                data.p0 = p0;
                data.p1 = p1;

                float3 positionLS = mul(_LightModelMatrix, i.positionWS - _LightPosition);
                float3 normalLS = mul(_LightModelMatrix, i.normalWS);

                float lightDistance;
                float3 lightPosition = ConstructLightPosition(positionLS, normalLS, data, lightDistance);
                float3 lightToSample = positionLS - lightPosition;

                float3 viewDir = normalize(_WorldSpaceCameraPos - i.positionWS);
                float3 specularDirection = reflect(viewDir, i.normalWS);

                float3 specularDirectionLS = mul(_LightModelMatrix, specularDirection);

                float3 specularLightPosition = ConstructLightPosition(positionLS, specularDirectionLS, data, lightDistance);
                float3 specularLightDirection = normalize(positionLS - specularLightPosition);

                float diffuseBSDF, specularBSDF;
                BSDF(i, specularLightDirection, diffuseBSDF, specularBSDF);

                if (_LightMode == QUAD)
                {
                    diffuseBSDF *= step(positionLS.y, 0);
                }

                float intensity = saturate(dot(normalLS, normalize(-lightToSample)));
                intensity *= EvalutePunctualLightAttenuation(positionLS, lightDistance);

                diffuse *= diffuseBSDF * intensity;
                diffuse *= _Luminance;

                specular *= specularBSDF;

                return float4(diffuse + specular, 1);
            }
            ENDCG
        }
    }
}