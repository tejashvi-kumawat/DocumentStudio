// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "document_studio_os_signing",
  platforms: [
    .macOS(.v10_15),
    .iOS(.v13),
  ],
  products: [
    .library(name: "document-studio-os-signing", targets: ["document_studio_os_signing"]),
  ],
  targets: [
    .target(
      name: "document_studio_os_signing",
      path: "darwin/Sources/document_studio_os_signing"
    ),
  ]
)
