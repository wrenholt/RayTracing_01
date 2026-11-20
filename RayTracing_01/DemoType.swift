//
//  DemoType.swift
//  RayTracing_01
//
//  Created by James Wrenholt on 7/20/26.
//

import Foundation

enum DemoType: String, CaseIterable, Identifiable
{
    case conicSections
    case coneSphere

    var id: String { rawValue }

    var title: String
    {
        switch self
        {
        case .conicSections:
            return "Conic Sections"
        case .coneSphere:
            return "Cone & Sphere"
        }
    }

    var description: String
    {
        switch self
        {
        case .conicSections:
            return "A double cone intersected by "
            + "a rotating plane, revealing "
            + "circle, ellipse, parabola, "
            + "and hyperbola."
        case .coneSphere:
            return "A rotating cone with its apex "
            + "at the center of a sphere, "
            + "tracing a circle where they "
            + "intersect."
        }
    }

    var vertexFunction: String
    {
        switch self
        {
        case .conicSections:
            return "conicVertex"
        case .coneSphere:
            return "coneSphereVertex"
        }
    }

    var fragmentFunction: String
    {
        switch self
        {
        case .conicSections:
            return "conicFragment"
        case .coneSphere:
            return "coneSphereFragment"
        }
    }
}
