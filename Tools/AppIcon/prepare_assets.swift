#!/usr/bin/env swift
//
// Prepares the app icon and launch image from the supplied artwork.
//
// Build-time tool, never shipped. Run from the repository root:
//
//     swift Tools/AppIcon/prepare_assets.swift [source.png]
//
// The artwork is a designed asset, not something generated here — this only
// resizes it into the shapes the asset catalog needs.
//
// The app icon is written WITHOUT an alpha channel: an RGBA icon is rejected at
// App Store submission and renders oddly on the home screen. The launch image
// keeps whatever the source had, since it is composited normally.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let defaultSource = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Desktop/memorizethebible.png")
let sourceURL =
    CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : repositoryRoot.appendingPathComponent("Tools/AppIcon/source/memorizethebible.png")

let iconDirectory = repositoryRoot.appendingPathComponent(
    "App/MemorizeBible/Assets.xcassets/AppIcon.appiconset"
)
let launchDirectory = repositoryRoot.appendingPathComponent(
    "App/MemorizeBible/Assets.xcassets/LaunchIcon.imageset"
)

guard
    let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
    let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    FileHandle.standardError.write(Data("cannot read \(sourceURL.path)\n".utf8))
    exit(1)
}

/// Redraws the artwork at `size`. `opaque` drops the alpha channel entirely.
func render(_ image: CGImage, size: Int, opaque: Bool) -> CGImage {
    let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    guard
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        )
    else { fatalError("could not create a \(size)pt context") }

    if opaque {
        // The artwork's own ground, so any rounding at the edges matches it.
        context.setFillColor(
            CGColor(red: 6 / 255, green: 7 / 255, blue: 6 / 255, alpha: 1)
        )
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let output = context.makeImage() else { fatalError("could not render at \(size)pt") }
    return output
}

func write(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        )
    else { fatalError("could not open \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
    let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("  \(url.lastPathComponent) — \(image.width)×\(image.height), \(bytes ?? 0) bytes")
}

print("app icon:")
write(render(artwork, size: 1024, opaque: true), to: iconDirectory.appendingPathComponent("AppIcon-1024.png"))

print("launch image:")
for (scale, size) in [(1, 418), (2, 836), (3, 1254)] {
    let name = scale == 1 ? "LaunchIcon.png" : "LaunchIcon@\(scale)x.png"
    write(render(artwork, size: size, opaque: false), to: launchDirectory.appendingPathComponent(name))
}
