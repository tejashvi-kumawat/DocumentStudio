# Homebrew Cask — Document Studio (macOS)
#
# Publish under: https://github.com/tejashvi-kumawat/homebrew-tap
# Install: brew tap tejashvi-kumawat/tap && brew install --cask document-studio

cask "document-studio" do
  version "1.2.0"
  sha256 "f48e106c47827995b737801d11c1c3d6eb70d3098860f231c720448c0f61386e"

  url "https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.2.0/DocumentStudio-1.2.0-macos.dmg"
  name "Document Studio"
  desc "Offline PDF workspace with merge, OCR, encryption, and Office conversion"
  homepage "https://github.com/tejashvi-kumawat/DocumentStudio"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :monterey

  app "Document Studio.app"

  # Document Studio is not notarized by Apple yet, so Gatekeeper may block the
  # first launch. Ask the user; only on an explicit "y" is the quarantine flag
  # cleared. Non-interactive installs (no terminal) never change anything.
  postflight do
    if $stdin.tty?
      print "Document Studio is not notarized by Apple. Remove macOS's quarantine flag so it " \
            "opens without the Gatekeeper warning? [y/N] "
      if %w[y yes].include?($stdin.gets.to_s.strip.downcase)
        system_command "/usr/bin/xattr",
                       args: ["-dr", "com.apple.quarantine", "#{appdir}/Document Studio.app"]
      end
    end
  end

  caveats <<~EOS
    Document Studio is not notarized by Apple yet, so macOS may say the app
    cannot be opened. If you answered no, right-click the app and choose Open once to allow it.
  EOS

  zap trash: [
    "~/Library/Application Support/com.documentstudio.document_studio",
    "~/Library/Preferences/com.documentstudio.document_studio.plist",
    "~/Library/Saved Application State/com.documentstudio.document_studio.savedState",
  ]
end
