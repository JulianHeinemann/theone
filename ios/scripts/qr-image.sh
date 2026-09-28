#!/usr/bin/env bash
# QR-Code-Bild erzeugen (für Tests): scripts/qr-image.sh <Inhalt> <Ausgabe.png>
set -euo pipefail
TMP="$(mktemp -d)"
cat > "$TMP/qr.swift" <<'SWIFT'
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
let f = CIFilter.qrCodeGenerator(); f.message = Data(CommandLine.arguments[1].utf8)
let img = f.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
let bg = CIImage(color: .white).cropped(to: img.extent.insetBy(dx: -120, dy: -120))
let cg = CIContext().createCGImage(img.composited(over: bg), from: bg.extent)!
try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
SWIFT
swiftc -O "$TMP/qr.swift" -o "$TMP/qr" 2>/dev/null
"$TMP/qr" "$1" "$2"
rm -rf "$TMP"
