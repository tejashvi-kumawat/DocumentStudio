# Homebrew Formula — Document Studio (Linux)
#
# Publish under: https://github.com/tejashvi-kumawat/homebrew-tap
# Install: brew tap tejashvi-kumawat/tap && brew install document-studio
#
# macOS users should use the cask instead:
#   brew install --cask document-studio

class DocumentStudio < Formula
  desc "Offline PDF workspace with merge, OCR, encryption, and Office conversion"
  homepage "https://github.com/tejashvi-kumawat/DocumentStudio"
  url "https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.0.3/document-studio_1.0.3_amd64.deb"
  sha256 "cd86f5087d3971f8441afb8c942f6faa26e78b25a62c36416b9438dfc8550f94"
  version "1.0.3"
  license :cannot_represent

  depends_on :linux
  depends_on arch: :x86_64

  def install
    # .deb may already be ar-unpacked by Homebrew; otherwise extract here.
    if Dir["data.tar.*"].empty?
      system "ar", "x", cached_download
    end
    data = Dir["data.tar.*"].first
    odie "No data.tar.* inside the .deb" if data.nil?

    system "tar", "xf", data

    libexec.install Dir["usr/lib/document-studio/*"]

    # Deb launcher hardcodes /usr/lib/document-studio — rewrite for Cellar.
    (bin/"document_studio").write <<~EOS
      #!/bin/bash
      APP="#{libexec}"
      export PATH="$APP/engines:$APP/engines/bin${PATH:+:$PATH}"
      if [[ -d "$APP/engines/tessdata" ]]; then
        export TESSDATA_PREFIX="$APP/engines/tessdata"
      fi
      exec "$APP/document_studio" "$@"
    EOS
    chmod 0755, bin/"document_studio"
    bin.install_symlink "document_studio" => "document-studio"

    desktop = "usr/share/applications/com.documentstudio.document_studio.desktop"
    if File.exist?(desktop)
      (share/"applications").mkpath
      (share/"applications").install desktop
      inreplace share/"applications/com.documentstudio.document_studio.desktop",
                /^Exec=.*/,
                "Exec=#{opt_bin}/document-studio %U"
      inreplace share/"applications/com.documentstudio.document_studio.desktop",
                /^TryExec=.*/,
                "TryExec=#{opt_bin}/document-studio"
    end

    metainfo = "usr/share/metainfo/com.documentstudio.document_studio.metainfo.xml"
    if File.exist?(metainfo)
      (share/"metainfo").mkpath
      (share/"metainfo").install metainfo
    end

    icons = Pathname("usr/share/icons")
    cp_r icons, share if icons.directory?
  end

  def post_install
    # App menus rarely search Homebrew's share/ — link into the user apps dir.
    return if ENV["HOME"].to_s.empty?

    user_apps = Pathname.new(ENV["HOME"])/".local/share/applications"
    user_apps.mkpath
    desktop_src = opt_share/"applications/com.documentstudio.document_studio.desktop"
    if desktop_src.exist?
      desktop_dst = user_apps/"com.documentstudio.document_studio.desktop"
      desktop_dst.unlink if desktop_dst.exist? || desktop_dst.symlink?
      desktop_dst.make_symlink desktop_src
    end

    system "update-desktop-database", user_apps.to_s if which("update-desktop-database")
    icon_dir = opt_share/"icons/hicolor"
    system "gtk-update-icon-cache", "-f", icon_dir.to_s if which("gtk-update-icon-cache") && icon_dir.directory?
  end

  def caveats
    <<~EOS
      Linux (this formula):
        brew install tejashvi-kumawat/tap/document-studio

      After install, Document Studio should appear in your app menu (search
      "Document Studio"). If it does not, log out/in once, or run:

        mkdir -p ~/.local/share/applications
        ln -sf "#{opt_share}/applications/com.documentstudio.document_studio.desktop" \\
          ~/.local/share/applications/
        update-desktop-database ~/.local/share/applications 2>/dev/null || true

      Also ensure brew is on PATH for GUI sessions (login shell):
        eval "$(#{HOMEBREW_PREFIX}/bin/brew shellenv)"

      macOS (cask):
        brew install --cask tejashvi-kumawat/tap/document-studio

      Needs GTK 3 system libraries (e.g. libgtk-3-0 on Debian/Ubuntu).
    EOS
  end

  test do
    assert_predicate bin/"document-studio", :exist?
    assert_predicate libexec/"document_studio", :exist?
  end
end
