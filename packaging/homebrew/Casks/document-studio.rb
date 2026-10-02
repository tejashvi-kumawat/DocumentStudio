# Homebrew Cask — Document Studio (macOS)
#
# Publish under: https://github.com/tejashvi-kumawat/homebrew-tap
# Install: brew tap tejashvi-kumawat/tap && brew install --cask document-studio

cask "document-studio" do
  version "1.0.3"
  sha256 "e4bee7d80a70d23fc9d7a8e1a5b2daa812c742c45766c87914b6c01b59399242"

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
