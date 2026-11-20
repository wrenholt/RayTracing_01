//
//  Renderer.swift
//  RayTracing_01
//
//  Created by James Wrenholt on 6/27/26.
//

import Metal
import MetalKit
import simd

let alignedUniformsSize =
(MemoryLayout<Uniforms>.size + 0xFF) & -0x100

let maxBuffersInFlight = 3

class Renderer: NSObject, MTKViewDelegate
{
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState
    var dynamicUniformBuffer: MTLBuffer
    var vertexBuffer: MTLBuffer

    let inFlightSemaphore =
    DispatchSemaphore(value: maxBuffersInFlight)

    var uniformBufferOffset = 0
    var uniformBufferIndex = 0
    var uniforms: UnsafeMutablePointer<Uniforms>

    var projectionMatrix = matrix_float4x4()
    var time: Float = 0
    var viewportSize = SIMD2<Float>(1, 1)

    // ─── Init ───────────────────────────────

    @MainActor
    init?(metalKitView: MTKView, demo: DemoType)
    {
        guard let device = metalKitView.device,
              let queue = device.makeCommandQueue()
                else { return nil }

        self.device = device
        self.commandQueue = queue

        // Uniform buffer
        let uniformSize =
        alignedUniformsSize * maxBuffersInFlight
        guard let uBuf = device.makeBuffer(
            length: uniformSize,
            options: .storageModeShared)
                else { return nil }

        self.dynamicUniformBuffer = uBuf
        uBuf.label = "UniformBuffer"

        uniforms = UnsafeMutableRawPointer(
            uBuf.contents()
        ).bindMemory(to: Uniforms.self, capacity: 1)

        // Fullscreen quad (two triangles)
        let quadVerts: [SIMD2<Float>] = [
            SIMD2(-1, -1), SIMD2( 1, -1),
            SIMD2(-1,  1),
            SIMD2(-1,  1), SIMD2( 1, -1),
            SIMD2( 1,  1),
        ]
        guard let vBuf = device.makeBuffer(
            bytes: quadVerts,
            length: MemoryLayout<SIMD2<Float>>
                .stride * quadVerts.count,
            options: .storageModeShared)
                else { return nil }

        self.vertexBuffer = vBuf
        vBuf.label = "QuadVertices"

        // Configure view
        metalKitView.colorPixelFormat =
            .bgra8Unorm_srgb
        metalKitView.depthStencilPixelFormat =
            .invalid
        metalKitView.sampleCount = 1

        // Build pipeline from demo's shader names
        guard let library =
                device.makeDefaultLibrary(),
              let vertFunc = library.makeFunction(
                name: demo.vertexFunction),
              let fragFunc = library.makeFunction(
                name: demo.fragmentFunction)
                else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "\(demo.title) Pipeline"
        desc.vertexFunction = vertFunc
        desc.fragmentFunction = fragFunc
        desc.colorAttachments[0].pixelFormat =
        metalKitView.colorPixelFormat

        do
        {
            pipelineState =
            try device.makeRenderPipelineState(
                descriptor: desc)
        }
        catch
        {
            print("Pipeline error: \(error)")
            return nil
        }

        super.init()
    }

    // ─── Per-frame update ───────────────────

    private func updateUniforms()
    {
        uniformBufferIndex =
        (uniformBufferIndex + 1)
        % maxBuffersInFlight
        uniformBufferOffset =
        alignedUniformsSize * uniformBufferIndex

        uniforms = UnsafeMutableRawPointer(
            dynamicUniformBuffer.contents()
            + uniformBufferOffset
        ).bindMemory(to: Uniforms.self, capacity: 1)

        // Camera orbits the scene
        let radius: Float = 8.0
        let speed: Float = 0.3
        let angle = time * speed

        let eyeX = radius * sin(angle)
        let eyeY: Float = 3.0
        let eyeZ = radius * cos(angle)
        let eye = SIMD3<Float>(eyeX, eyeY, eyeZ)
        let target = SIMD3<Float>(0, 0, 0)
        let up = SIMD3<Float>(0, 1, 0)

        let view = lookAt(eye: eye,
                          center: target,
                          up: up)
        let proj = projectionMatrix
        let viewProj = proj * view

        // Invert for ray generation
        let invVP = simd_inverse(viewProj)

        uniforms[0].resolution = viewportSize
        uniforms[0].time = time
        uniforms[0].inverseViewProjection = invVP
        uniforms[0].cameraPosition = eye

        time += Float(1.0 / 60.0)
    }

    // ─── Draw ───────────────────────────────

    func draw(in view: MTKView)
    {
        _ = inFlightSemaphore.wait(
            timeout: .distantFuture)

        guard let commandBuffer =
                commandQueue.makeCommandBuffer()
                else
        {
            inFlightSemaphore.signal()
            return
        }

        let sem = inFlightSemaphore
        commandBuffer.addCompletedHandler
        { _ in
            sem.signal()
        }

        updateUniforms()

        guard let rpd =
                view.currentRenderPassDescriptor,
              let encoder =
                commandBuffer
            .makeRenderCommandEncoder(
                descriptor: rpd)
                else
        {
            commandBuffer.commit()
            return
        }

        encoder.label = "RayTrace Encoder"
        encoder.setRenderPipelineState(pipelineState)

        encoder.setVertexBuffer(
            vertexBuffer, offset: 0,
            index: Int(
                BufferIndex.vertices.rawValue))

        encoder.setFragmentBuffer(
            dynamicUniformBuffer,
            offset: uniformBufferOffset,
            index: Int(
                BufferIndex.uniforms.rawValue))

        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6)

        encoder.endEncoding()

        if let drawable = view.currentDrawable
        {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }

    // ─── Resize ─────────────────────────────

    func mtkView(
        _ view: MTKView,
        drawableSizeWillChange size: CGSize)
    {
        let w = Float(size.width)
        let h = Float(size.height)
        viewportSize = SIMD2<Float>(w, h)

        let aspect = w / h
        projectionMatrix =
        perspectiveRH(
            fovY: radians(65),
            aspect: aspect,
            near: 0.1,
            far: 100.0)
    }
}

// ─── Matrix utilities ───────────────────────────

func radians(_ degrees: Float) -> Float
{
    return degrees * .pi / 180.0
}

func perspectiveRH(
    fovY: Float,
    aspect: Float,
    near: Float,
    far: Float) -> matrix_float4x4
{
    let ys = 1.0 / tan(fovY * 0.5)
    let xs = ys / aspect
    let zs = far / (near - far)
    return matrix_float4x4(columns: (
        SIMD4(xs,  0,  0,  0),
        SIMD4( 0, ys,  0,  0),
        SIMD4( 0,  0, zs, -1),
        SIMD4( 0,  0, zs * near, 0)
    ))
}

func lookAt(
    eye: SIMD3<Float>,
    center: SIMD3<Float>,
    up: SIMD3<Float>) -> matrix_float4x4
{
    let f = normalize(center - eye)
    let s = normalize(cross(f, up))
    let u = cross(s, f)

    return matrix_float4x4(columns: (
        SIMD4(s.x, u.x, -f.x, 0),
        SIMD4(s.y, u.y, -f.y, 0),
        SIMD4(s.z, u.z, -f.z, 0),
        SIMD4(-dot(s, eye),
               -dot(u, eye),
               dot(f, eye), 1)
    ))
}
