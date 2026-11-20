//
//  ContentView.swift
//  RayTracing_01
//
//  Created by James Wrenholt on 7/20/26.
//

import SwiftUI

struct ContentView: View
{
    @State private var selectedDemo: DemoType?

    var body: some View
    {
        NavigationStack
        {
            VStack(spacing: 0)
            {
                // ─── Header ─────────────────
                VStack(spacing: 12)
                {
                    Text("Ray Tracing")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("in Swift & Metal")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 60)
                .padding(.bottom, 40)

                // ─── Demo buttons ───────────
                VStack(spacing: 16)
                {
                    ForEach(DemoType.allCases)
                    { demo in
                        Button
                        {
                            selectedDemo = demo
                        }
                    label:
                        {
                            VStack(
                                alignment: .leading,
                                spacing: 6)
                            {
                                Text(demo.title)
                                    .font(.headline)
                                Text(demo.description)
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary)
                            }
                            .frame(
                                maxWidth: 320,
                                alignment: .leading)
                            .padding()
                            .background(
                                .quaternary)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 10
                                ))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
            }
            .frame(
                minWidth: 500,
                minHeight: 400)
            .navigationDestination(
                item: $selectedDemo)
            { demo in
                MetalView(demo: demo)
                    .navigationTitle(demo.title)
                    .ignoresSafeArea()
            }
        }
    }
}
