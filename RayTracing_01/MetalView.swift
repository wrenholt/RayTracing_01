//
//  MetalView.swift
//  RayTracing_01
//
//  Created by James Wrenholt on 7/20/26.
//

import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable
{
    let demo: DemoType

    func makeNSView(
        context: Context
    ) -> MTKView
    {
        let mtkView = MTKView()
        mtkView.device =
        MTLCreateSystemDefaultDevice()
        mtkView.preferredFramesPerSecond = 60

        if let renderer = Renderer(
            metalKitView: mtkView,
            demo: demo)
        {
            context.coordinator.renderer = renderer
            mtkView.delegate = renderer
            renderer.mtkView(
                mtkView,
                drawableSizeWillChange:
                    mtkView.drawableSize)
        }

        return mtkView
    }

    func updateNSView(
        _ nsView: MTKView,
        context: Context)
    {
    }

    func makeCoordinator() -> Coordinator
    {
        Coordinator()
    }

    class Coordinator
    {
        var renderer: Renderer?
    }
}
