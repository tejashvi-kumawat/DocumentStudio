# Homebrew Cask — Document Studio (macOS)
#
# Publish: see docs/HOMEBREW.md
#   PR to https://github.com/Homebrew/homebrew-cask
#   or host in https://github.com/tejashvi-kumawat/homebrew-tap/Casks/
#
# Before release, set version, sha256, and url to match GitHub Release assets.
#   bash scripts/release/update_homebrew_cask.sh 1.0.3 dist/macos/DocumentStudio-1.0.3-macos.dmg

cask "document-studio" do
  version "1.0.3"
  sha256 "REPLACE_WITH_SHA256"

  url "https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v#{version}/DocumentStudio-#{version}-macos.dmg"
  name "Document Studio"
  desc "Offline PDF workspace with merge, OCR, encryption, and Office conversion"
  homepage "https://github.com/tejashvi-kumawat/DocumentStudio"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :monterey"

  app "Document Studio.app"

  zap trash: [
    "~/Library/Application Support/com.documentstudio.document_studio",
    "~/Library/Preferences/com.documentstudio.document_studio.plist",
    "~/Library/Saved Application State/com.documentstudio.document_studio.savedState",
  ]
end
