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
  url "https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.1.0/document-studio_1.1.0_amd64.deb"
  sha256 "496194f336ad033e898f7ccf7315e926dea0f6c9d2eed53b24833fdeac2c0b83"
  version "1.1.0"
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
    # Homebrew runs post_install with a *sandbox* HOME on Linux. Use the real
    # login home so the app appears in GNOME/KDE/Cosmic application menus.
    require "etc"
    require "fileutils"
    real_home = begin
      Etc.getpwuid(Process.euid).dir
    rescue StandardError
      ENV["HOME"]
    end
    return if real_home.to_s.empty? || real_home.start_with?("/var/tmp", "/tmp")

    user_apps = Pathname.new(real_home)/".local/share/applications"
    user_apps.mkpath
    desktop_src = opt_share/"applications/com.documentstudio.document_studio.desktop"
    if desktop_src.exist?
      %w[
        com.documentstudio.document_studio.desktop
        document-studio.desktop
      ].each do |name|
        desktop_dst = user_apps/name
        desktop_dst.unlink if desktop_dst.exist? || desktop_dst.symlink?
        FileUtils.cp desktop_src, desktop_dst
      end
    end

    # Icons: menus resolve Icon= via ~/.local/share/icons more reliably than
    # Homebrew's Cellar share/ path (not on default XDG_DATA_DIRS).
    icon_src = opt_share/"icons/hicolor"
    if icon_src.directory?
      user_icons = Pathname.new(real_home)/".local/share/icons"
      user_icons.mkpath
      FileUtils.cp_r icon_src, user_icons
    end

    system "update-desktop-database", user_apps.to_s if which("update-desktop-database")
    user_icon_theme = Pathname.new(real_home)/".local/share/icons/hicolor"
    if which("gtk-update-icon-cache") && user_icon_theme.directory?
      # Create a minimal index.theme if missing so gtk-update-icon-cache succeeds.
      index = user_icon_theme/"index.theme"
      unless index.exist?
        index.write <<~EOS
          [Icon Theme]
          Name=Hicolor
          Comment=Fallback icon theme
          Inherits=hicolor
          Directories=
        EOS
      end
      system "gtk-update-icon-cache", "-f", user_icon_theme.to_s
    end
  end

  def caveats
    <<~EOS
      Linux (this formula):
        brew install tejashvi-kumawat/tap/document-studio

      After install you should find **Document Studio** in your app menu /
      Activities search (same idea as Start Menu / Spotlight).

      If the menu entry is missing, run:
        brew postinstall tejashvi-kumawat/tap/document-studio
      then log out and back in (or restart the shell / desktop session).

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
