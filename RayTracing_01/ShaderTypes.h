//------------------------------------------------------------------------------
//  ShaderTypes.h
//------------------------------------------------------------------------------
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) \
enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>
//------------------------------------------------------------------------------
typedef NS_ENUM(EnumBackingType, BufferIndex)
{
    BufferIndexUniforms = 0,
    BufferIndexVertices = 1,
};
//------------------------------------------------------------------------------
typedef struct
{
    vector_float2 resolution;
    float time;
    float padding;
    matrix_float4x4 inverseViewProjection;
    vector_float3 cameraPosition;
    float padding2;
} Uniforms;
//------------------------------------------------------------------------------
#endif /* ShaderTypes_h */
