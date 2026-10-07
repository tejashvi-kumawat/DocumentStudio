# Homebrew Cask — Document Studio (macOS)
#
# Publish under: https://github.com/tejashvi-kumawat/homebrew-tap
# Install: brew tap tejashvi-kumawat/tap && brew install --cask document-studio

cask "document-studio" do
  version "1.1.0"
  sha256 "9a6d6cdf3645d637587df1315bad4f32434e17ea0a1939a1937f7d4ebc839412"

  url "https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.1.0/DocumentStudio-1.1.0-macos.dmg"
  name "Document Studio"
  desc "Offline PDF workspace with merge, OCR, encryption, and Office conversion"
  homepage "https://github.com/tejashvi-kumawat/DocumentStudio"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :monterey

  app "Document Studio.app"

  caveats <<~EOS
    Until releases are notarized by Apple, macOS may say it cannot verify
    Document Studio. Open it the first time with: Finder → Applications →
    right-click Document Studio → Open → Open (or System Settings →
    Privacy & Security → Open Anyway). Later launches open normally.
  EOS

  zap trash: [
    "~/Library/Application Support/com.documentstudio.document_studio",
    "~/Library/Preferences/com.documentstudio.document_studio.plist",
    "~/Library/Saved Application State/com.documentstudio.document_studio.savedState",
  ]
end
