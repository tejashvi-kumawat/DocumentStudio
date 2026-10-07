# Code signing — removing the Windows and macOS security warnings

Unsigned apps trigger:

- **Windows:** "Windows protected your PC — Microsoft Defender SmartScreen
  prevented an unrecognized app from starting".
- **macOS:** "Apple could not verify 'Document Studio' is free of malware".

Neither is a malware detection. Both mean the download is not signed with a
certificate that ties it to a verified publisher. The build is ready to
sign: add the secrets below and the next **Release** workflow run signs
everything. Without them it builds exactly as before (unsigned / ad-hoc).

## Windows — Microsoft Store (recommended, no certificate needed)

Your Microsoft developer (Partner Center) account is enough: apps the Store
publishes are signed by Microsoft, so neither SmartScreen nor Defender warns,
the Store updates them, and `winget install` can install them from the
`msstore` source.

1. Partner Center → Apps and games → **New product → MSIX or PWA app**,
   reserve the name *Document Studio*.
2. Open the app → **Product management → Product identity** and copy:
   - Package/Identity/Name → secret `MSSTORE_IDENTITY_NAME`
   - Package/Identity/Publisher (starts with `CN=`) → secret `MSSTORE_PUBLISHER`
   - Package/Properties/PublisherDisplayName → secret `MSSTORE_PUBLISHER_DISPLAY_NAME`
3. Run the **Release** workflow. The `windows-store` artifact contains
   `DocumentStudio-<version>-store.msix` (built with the self-updater turned
   off, as Store policy requires).
4. Start a submission: Pricing (Free), Properties, Age rating, Store
   listing, then **Packages → upload the .msix**. The package declares
   `runFullTrust` (it is a desktop app that runs bundled tools); explain in
   the "Submission options → restricted capabilities" box: *"Desktop PDF
   editor that runs bundled command-line engines (qpdf, Tesseract,
   LibreOffice) for document processing."*
5. After certification (usually 1–3 days) users install with the Store or
   `winget install "Document Studio" --source msstore`.

To build it on your own Windows PC instead: set the three values as
environment variables `DS_MSSTORE_IDENTITY_NAME`, `DS_MSSTORE_PUBLISHER` and
`DS_MSSTORE_PUBLISHER_DISPLAY_NAME`, then run
`scripts\windows\package_store_msix.ps1`.

## Windows — signed Setup.exe (Authenticode)

1. Get a code-signing certificate. Options that work for an individual
   developer:
   - **Certum "Open Source Code Signing"** or Certum Standard — low cost,
     available worldwide to individuals; delivered on a SimplySign cloud
     key.
   - **Sectigo / SSL.com OV code signing** — standard option; since 2023 the
     key lives on a hardware token or cloud HSM.
   - **Azure Trusted Signing** (now "Artifact Signing") — about USD 10 a
     month, fastest SmartScreen reputation. Check whether individual
     identity validation is offered in your country before choosing it.
   - **Microsoft Store** (free individual account) — Store installs are
     signed by Microsoft and never show SmartScreen.
2. If the certificate comes as a `.pfx` you may export (some OV
   certificates), add these repository secrets:
   - `WINDOWS_CERT_PFX_BASE64` — `base64 -w0 cert.pfx`
   - `WINDOWS_CERT_PASSWORD`
3. For a hardware token, a cloud key (Certum SimplySign) or Trusted
   Signing, sign on your own Windows PC instead, by setting one of the
   options in `scripts/windows/sign_windows.ps1` (`DS_WIN_CERT_SHA1`, or
   `DS_WIN_TRUSTED_SIGNING_DLIB` + `DS_WIN_TRUSTED_SIGNING_METADATA`) and
   running `scripts\windows\package_release.ps1`.

`package_release.ps1` signs `document_studio.exe`, its DLLs and the bundled
tools that are not already signed by their own publishers, then passes the
signer to Inno Setup, which signs `Setup.exe` and the uninstaller.

SmartScreen builds reputation per certificate. A new OV certificate can
still show the warning for its first downloads; it fades as people install.

## macOS (Developer ID + notarization)

1. Join the **Apple Developer Program** (USD 99 a year). Without it, macOS
   always warns on downloaded apps; there is no free route.
2. In Xcode → Settings → Accounts → Manage Certificates, create a
   **Developer ID Application** certificate. Export it from Keychain Access
   as a `.p12` file.
3. Create an app-specific password at appleid.apple.com (Sign-In and
   Security → App-Specific Passwords).
4. Add these repository secrets:
   - `MACOS_CERT_P12_BASE64` — `base64 -i DeveloperID.p12`
   - `MACOS_CERT_PASSWORD` — the .p12 password
   - `MACOS_SIGN_IDENTITY` — e.g. `Developer ID Application: Your Name (TEAMID)`
   - `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`

`scripts/macos/package_release.sh` then signs every binary inside the app
(hardened runtime; bundled engines use `scripts/macos/engines.entitlements`),
notarizes and staples the app, builds the DMG/ZIP, and signs, notarizes and
staples the DMG.

## Until then (users)

- **Windows:** in the SmartScreen dialog, click *More info* → *Run anyway*.
  Installing with `winget install DocumentStudio.DocumentStudio` (once the
  winget-pkgs pull request is merged), or updating from inside the app,
  avoids the prompt.
- **macOS:** right-click *Document Studio* in Applications → *Open* → *Open*
  (or System Settings → Privacy & Security → *Open Anyway*), once.
