
#define Deferred=true;

SamplerState linearSampler : Immutable
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

struct VS_IN
{
	float4 PosO : POSITION;
	float4 TexCd : TEXCOORD0;

};

struct psInput
{
	float4 p : SV_Position;
	float2 uv : TEXCOORD0;
};


static const float MAX_REFLECTION_LOD = 9.0;

float2 R : Targetsize;

struct LightStruct
{
	float4   Color;
    float4   lPos;
	
    float    lightRange;
    float    lAtt0;
    float    lAtt1;
    float    lightType;
	
    float 	 useShadow;
	float 	 shadowType;
	float 	 lightBleedingLimit;
	float 	 lightSize;
	
	float 	 penumbraScale;
	float 	 numShadowSamples;
	float 	 pad0;
	float 	 pad1;
};

struct LightMatricesStruct
{
	row_major 	float4x4 VP;
	row_major	float4x4 V;
	row_major	float4x4 P;
};

struct MaterialStruct
{
	float metallic;
	float roughness;
	
	float 	pad0;
	float 	pad1;
	float4  Color;
	float4  Emissive;
	
	row_major float4x4	tTex;
	row_major float4x4	tTexInv;
	
	float 	sssAmount;
	float 	sssFalloff;
	float 	sss;
	float 	pad2;
	
	float 	fHeightMapScale;
	float 	POMnumSamples;
	float 	POM;
	float 	pad3;
	
	float4	Refraction;
	
	float	bumpy;
	float	noTile;
	float	useTex;
	float	Iridescence;
	
	#ifdef doControlTextures
	
	float	sampleAlbedo;
	float	sampleEmissive;
	float	sampleNormal;
	float	sampleHeight;
	
	float	sampleRoughness;
	float	sampleMetallic;
	float	sampleAO;
	float	pad4;
	
	#endif
};

static const float3 F = float3(0.04,0.04,0.04);	



Texture2DArray texture2d <string uiname="Texture"; >;
Texture2DArray EmissiveTex <string uiname="Emissive"; >;
//Texture2DArray normalTex <string uiname="NormalMap"; >;
//Texture2DArray heightMap <string uiname="HeightMap"; >;
Texture2DArray roughTex <string uiname="RoughnessMap"; >;
Texture2DArray metallTex <string uiname="MetallicMap"; >;
Texture2DArray aoTex <string uiname="AOMap"; >;
Texture2DArray iridescence <string uiname="Iridescence"; >;

StructuredBuffer <bool> useTex;

Texture2D GBufferPos <string uiname="GBufferPos"; >;
Texture2D GBufferNorm <string uiname="GBufferNorm"; >;
Texture2D GBufferTexCd <string uiname="GBufferTexCd"; >;

TextureCube cubeTexRefl <string uiname="CubeMap Refl"; >;
TextureCube cubeTexIrradiance <string uiname="CubeMap Irradiance"; >;
Texture2D brdfLUT <string uiname="brdfLUT"; >;

Texture2DArray lightMap <string uiname="SpotTex"; >;
Texture2DArray shadowMap <string uiname="ShadowMaps"; >;

StructuredBuffer <LightMatricesStruct> LightMatrices  <string uiname="Light Matrices Buffer";>;
StructuredBuffer <LightStruct> Light  <string uiname="Light Parameter Buffer";>;
StructuredBuffer <MaterialStruct> Material  <string uiname="Material";>;


cbuffer cbPerObject : register (b0)
{	
	float4 GlobalReflectionColor <bool color = true; string uiname="Global Reflection Color";>  = { 0.0f,0.0f,0.0f,0.0f };
	float4 GlobalDiffuseColor <bool color = true; string uiname="Global Diffuse Color";>  = { 0.0f,0.0f,0.0f,0.0f };
	float4 Background <bool color = true; string uiname="Background Color";>  = { 0.0f,0.0f,0.0f,0.0f };

	float4x4 tVI;
	
	float lPower <String uiname="Power"; float uimin=0.0;> = 1;     //shininess of specular highlight

	float2 iblIntensity <String uiname="IBL Intensity";>;	

	uint num;
};


SamplerState g_samLinear
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

#include "..\dx11\ShadowMapping.fxh"
#include "..\dx11\NoTile.fxh"
//#include "..\dx11\ParallaxOcclusionMapping.fxh"
#include "..\dx11\CookTorrance.fxh"
#ifdef doIBL
#include "..\dx11\IBL.fxh"
#elif doIridescence	
#include "..\dx11\IRIDESCENCE.fxh"
#elif doGlobalLight
#include "..\dx11\GLOBALLIGHT.fxh"
#endif

#ifdef doToneMap
#include "ToneMapping.fxh"
#endif

psInput VS(VS_IN input)
{
    psInput output;
    output.p  = input.PosO;
    output.uv = input.TexCd;
    return output;
}




float4 doLighting(psInput input) : SV_Target
{
	
	///////////////////////////////////////////////////////////////////////////
	// INITIALIZE GLOBAL VARIABLES
	///////////////////////////////////////////////////////////////////////////
	
	
	float3 N = GBufferNorm.Sample(linearSampler,input.uv).rgb;
	if(length(N) == 0) return Background * 2;
	
	uint texID = GBufferNorm.Sample(linearSampler, input.uv).a * 1000;
	float4 PosW = GBufferPos.Sample(linearSampler, input.uv);
	
	float4 TexCd = GBufferTexCd.Sample(linearSampler, input.uv);
	
	TexCd = mul(TexCd, Material[texID].tTex);
	
	float3 V = normalize(tVI[3].xyz - PosW.xyz);
	
	
	///////////////////////////////////////////////////////////////////////////
	// BUMP MAPPING & POM
	//////////////////////////////////////////////////////////////////////////

//	if(useTex[texID]){
//	
//	
//	// compute derivations of the world position
//	float3 p_dx = ddx_fine(PosW.xyz);
//	float3 p_dy = ddy_fine(PosW.xyz);
//	// compute derivations of the texture coordinate
//	float2 tc_dx = ddx_fine(TexCd.xy);
//	float2 tc_dy = ddy_fine(TexCd.xy);
//			
//	// compute initial tangent and bi-tangent
//	float3 t = normalize( (tc_dy.y * p_dx - tc_dx.y * p_dy)  +.0000000000000001 );
//	float3 b = normalize( (tc_dy.x * p_dx - tc_dx.x * p_dy)  +.0000000000000001 ); // sign inversion
//		
//	// get new tangent from a given mesh normal
//	float3 x = cross(N, t);
//	t = cross(x, N);
//	t = normalize(t);
//	// get updated bi-tangent
//	x = cross(b, N);
//	b = cross(N, x);
//	b = normalize(b);
//	
//	#ifdef doPOM
//	if(Material[texID].POM){
//		parallaxOcclusionMapping(TexCd.xy, PosW.xyz, V, float3x3(t,b,N), texID);
//	}
//	#endif
//
//	float3 bumpMap = 0;
//	
//		bumpMap = normalTex.Sample(g_samLinear,float3(TexCd.xy, texID)).rgb;
//		if(length(bumpMap) > 0) bumpMap = (bumpMap * 2.0f) - 1.0f;
//		N = normalize(N + (bumpMap.x * (t) + bumpMap.y * (b)) * Material[texID].bumpy);
//		
//	}
	
	///////////////////////////////////////////////////////////////////////////
	// INITIALIZE PBR PRAMETERS WITH TEXTURE LOOKUP
	///////////////////////////////////////////////////////////////////////////
	
	float4 albedo = 1;
	float roughnessT = 0;
	float aoT = 1;
	float metallicT = 0;
	
	#ifdef doControlTextures
	if(useTex[texID]){
				
		roughnessT = Material[texID].roughness;
		if(Material[texID].sampleRoughness) roughnessT = roughTex.Sample(g_samLinear, float3(TexCd.xy, texID)).r;
		roughnessT = min(max(roughnessT * Material[texID].roughness,.01),.95);
	
		aoT = 1;
		if(Material[texID].sampleAO) aoT = aoTex.Sample(g_samLinear,  float3(TexCd.xy, texID)).r;
	
		metallicT = 1;
		if(Material[texID].sampleMetallic) metallicT = metallTex.Sample(g_samLinear, float3(TexCd.xy, texID)).r;
		metallicT *= Material[texID].metallic;
		
		float4 texCol = 1;
		if(Material[texID].sampleAlbedo) texCol = texture2d.Sample(g_samLinear, float3(TexCd.xy, texID));
	
		albedo = texCol * saturate(Material[texID].Color) * aoT;	
		
	} else {
		roughnessT = min(max(Material[texID].roughness,.01),.95);
		aoT = 1;
		metallicT = Material[texID].metallic;
		albedo = saturate(Material[texID].Color);
	}
	
	#else
		
		roughnessT = min(max(Material[texID].roughness,.01),.95);
		aoT = 1;
		metallicT = Material[texID].metallic;
		albedo = saturate( Material[texID].Color);
		
		
	
	#endif
	
	
	
	///////////////////////////////////////////////////////////////////////////
	// INITIALIZE PBR PRAMETERS WITH TEXTURE LOOKUP
	///////////////////////////////////////////////////////////////////////////
	
	float3 iridescenceColor = 1;
	#ifdef doIridescence
	if (Material[texID].Iridescence){
		float inverseDotView = 1.0 - max(dot(N,V),0.0);
		iridescenceColor = iridescence.Sample(g_samLinear, float3(inverseDotView,0,texID)).rgb;
	} 	
	#endif
		
	///////////////////////////////////////////////////////////////////////////
	// INITIALIZE VARIABLES FOR LIGHT LOOP
	///////////////////////////////////////////////////////////////////////////
	
	float4 viewPosition;
	float4 projectTexCoord;
	
	float3 F0 = lerp(F, albedo.xyz, metallicT);
	
	int shadowCounter = 0;
	int spotLightCount = 0;
	int lightCounter = 0;
	
	float4 shadow = 0;
	
	float3 lightToObject;
	float3 L;
	float lightDist;
	float falloff;

	float3 finalLight = 0;
	
	///////////////////////////////////////////////////////////////////////////
	// SHADING AND SHADOW MAPPING FOR EACH LIGHT
	///////////////////////////////////////////////////////////////////////////
	
	for(uint i = 0; i< num; i++){

		lightToObject = Light[i].lPos.xyz - PosW.xyz;
		L = normalize(lightToObject);
		lightDist = length(lightToObject);
		
		falloff = smoothstep(0,Light[i].lAtt1,(Light[i%num].lightRange-lightDist));
			
		
		switch (Light[i].lightType){
			
		// DIRECTIONAL
			case 0:
				shadow = 0;
			
				if(Light[i].useShadow){
				viewPosition = mul(PosW, LightMatrices[i].VP);
				
				projectTexCoord.x =  viewPosition.x / viewPosition.w / 2.0f + 0.5f;
		   		projectTexCoord.y = -viewPosition.y / viewPosition.w / 2.0f + 0.5f;			
				projectTexCoord.z =  viewPosition.z / viewPosition.w / 2.0f + 0.5f;
			
				if((saturate(projectTexCoord.x) == projectTexCoord.x) && (saturate(projectTexCoord.y) == projectTexCoord.y)
				&& (saturate(projectTexCoord.z) == projectTexCoord.z)){
					doShadow(shadow, Light[i].shadowType, lightDist, Light[i%num].lightRange, projectTexCoord, viewPosition, i, shadowCounter, N, L);
				} else {
					shadow = 1;
				}
					float3 LDir = float3(LightMatrices[i].V._m02,LightMatrices[i].V._m12,LightMatrices[i].V._m22);			
					shadowCounter++;
							
					finalLight += cookTorrance(V, -LDir, N, albedo.xyz, Light[i].Color.rgb,
					lerp(1.0,saturate(shadow),falloff).x, 1.0, 1, lightDist, Material[texID].sssAmount, Material[texID].sssFalloff, F0, Light[i].lAtt0, roughnessT, metallicT, aoT, iridescenceColor, texID);
				} else {
					float3 LDir = float3(LightMatrices[i].V._m02,LightMatrices[i].V._m12,LightMatrices[i].V._m22);	
					finalLight += cookTorrance(V, -LDir, N, albedo.xyz, Light[i].Color.rgb,
					1.0, 1.0, 1.0, lightDist, Material[texID].sssAmount, Material[texID].sssFalloff, F0, Light[i].lAtt0, roughnessT, metallicT, aoT, iridescenceColor, texID);
				}
				lightCounter ++;
				break;
			
			// SPOT
			case 1:
				shadow = 0;
				viewPosition = mul(PosW, LightMatrices[i].VP);
					
				projectTexCoord.x =  viewPosition.x / viewPosition.w / 2.0f + 0.5f;
		   		projectTexCoord.y = -viewPosition.y / viewPosition.w / 2.0f + 0.5f;			
				projectTexCoord.z =  viewPosition.z / viewPosition.w / 2.0f + 0.5f;
			
				float3 falloffSpot = 0;
				if((saturate(projectTexCoord.x) == projectTexCoord.x) && (saturate(projectTexCoord.y) == projectTexCoord.y)
				&& (saturate(projectTexCoord.z) == projectTexCoord.z)){
					
					uint tXS,tYS,mS;
					lightMap.GetDimensions(tXS,tYS,mS);
					if(tXS+tYS > 4) falloffSpot = lightMap.SampleLevel(g_samLinear, float3(projectTexCoord.xy, spotLightCount), 0 ).rgb;
					else if(tXS+tYS < 4) falloffSpot = smoothstep(1,0,saturate(length(.5-projectTexCoord.xy)*2));
					
					if(Light[i].useShadow) doShadow(shadow, Light[i].shadowType, lightDist, Light[i%num].lightRange, projectTexCoord, viewPosition, i, shadowCounter, N, L);
					
				} else {
					shadow = 1;
				}
				
				if(Light[i].useShadow){
						shadowCounter++;
						float attenuation = Light[i].lAtt0;
						finalLight += cookTorrance(V, L, N, albedo.xyz, Light[i].Color.rgb,
						shadow.x, falloffSpot * falloff, falloff, lightDist, Material[texID].sssAmount, Material[texID].sssFalloff, F0, attenuation, roughnessT, metallicT, aoT, iridescenceColor, texID);
					
				} else {
						float attenuation = Light[i].lAtt0;
						finalLight += cookTorrance(V, L, N, albedo.xyz, Light[i].Color.rgb,
						1.0, falloffSpot * falloff, falloff, lightDist, Material[texID].sssAmount, Material[texID].sssFalloff, F0, attenuation, roughnessT, metallicT, aoT, iridescenceColor, texID);
				}
			
				lightCounter ++;
				spotLightCount++;
				break;
	
			// POINT
			case 2:
			
				shadow = 0;
			
				if(Light[i].useShadow){
					
					for(int p = 0; p < 6; p++){
						
						float4x4 LightPcropp = LightMatrices[p + lightCounter].P;
				
						LightPcropp._m00 = 1;
						LightPcropp._m11 = 1;
						
						float4x4 LightVPNew = mul(LightMatrices[p + lightCounter].V,LightPcropp);
						
						viewPosition = mul(PosW, LightVPNew);
						
						projectTexCoord.x =  viewPosition.x / viewPosition.w / 2.0f + 0.5f;
			   			projectTexCoord.y = -viewPosition.y / viewPosition.w / 2.0f + 0.5f;
						projectTexCoord.z =  viewPosition.z / viewPosition.w / 2.0f + 0.5f;
					
						if((saturate(projectTexCoord.x) == projectTexCoord.x) && (saturate(projectTexCoord.y) == projectTexCoord.y)
						&& (saturate(projectTexCoord.z) == projectTexCoord.z)){
							
							viewPosition = mul(PosW, LightMatrices[p + lightCounter].VP);
							
							projectTexCoord.x =  viewPosition.x / viewPosition.w / 2.0f + 0.5f;
				   			projectTexCoord.y = -viewPosition.y / viewPosition.w / 2.0f + 0.5f;
							projectTexCoord.z =  viewPosition.z / viewPosition.w / 2.0f + 0.5f;
							
							doShadow(shadow, Light[i].shadowType, lightDist, Light[i%num].lightRange, projectTexCoord, viewPosition, i, p+shadowCounter, N, L);
							
						}
					}
							float attenuation = Light[i].lAtt0 * falloff;
							finalLight += cookTorrance(V, L, N, albedo.xyz, Light[i].Color.rgb,
							shadow.x, 1.0, falloff, lightDist, Material[texID].sssAmount, Material[texID].sssFalloff, F0, attenuation, roughnessT, metallicT, aoT, iridescenceColor, texID);
				
							shadowCounter += 6;
							lightCounter  += 6;
				} else {
						    float attenuation = Light[i].lAtt0 * falloff;
							finalLight += cookTorrance(V, L, N, albedo.xyz, Light[i].Color.rgb,
							1, 1, falloff, lightDist, Material[texID].sssAmount, Material[texID].sssFalloff, F0, attenuation, roughnessT, metallicT, aoT, iridescenceColor, texID);
			
				}	
			
			

			break;			
		}	
	}
	
	///////////////////////////////////////////////////////////////////////////
	// IMAGE BASED LIGHTING
	///////////////////////////////////////////////////////////////////////////
	#ifdef doIBL
		finalLight += IBL(N, V, F0, albedo, iridescenceColor, roughnessT, metallicT, aoT, texID );
	#elif doIridescence
		finalLight += IRIDESCENCE(N, V, F0, albedo, iridescenceColor, texRoughness, aoT, metallicT );
	#elif doGlobalLight
		finalLight +=  GLOBALLIGHT(N, V, F0, albedo, texRoughness, aoT, metallicT );
	#endif
	
	///////////////////////////////////////////////////////////////////////////
	// EMISSIVE LIGHTING
	///////////////////////////////////////////////////////////////////////////
	
	#ifdef doControlTextures
	if(Material[texID].sampleEmissive) finalLight.rgb += saturate(Material[texID].Emissive.rgb + EmissiveTex.SampleLevel(g_samLinear, float3(TexCd.xy, texID),0).rgb);
	#else
		finalLight.rgb += saturate( Material[texID].Emissive.rgb);
	#endif
	
	#ifdef doToneMap
	finalLight.rgb = ACESFitted(finalLight.rgb);
	#endif
	
	return float4(finalLight,1);
}





technique10 Constant
{
	pass P0
	{
		SetVertexShader( CompileShader( vs_4_0, VS() ) );
		SetPixelShader( CompileShader( ps_5_0, doLighting() ) );
	}
}



