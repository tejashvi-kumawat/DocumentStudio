# FFmpeg (bundled binary)

## Version / origin

- **Windows default:** `https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip` (see `DS_FFMPEG_URL`).
- **Linux default:** Ubuntu `ffmpeg` binary extracted from `.deb` packages (see `bundle_linux_engines.sh`).

Exact version string is recorded in `bundled-versions.json` on installed builds.

## License status — not fully verified in this repository

FFmpeg is **license-sensitive**: the effective license (GPL-3.0-only, LGPL-3.0,
or mixed) depends on **configure options** used when the binary was built.
Document Studio **does not** build FFmpeg from source in this repository and
**has not** recorded the configure line for third-party zips or distro packages.

**Before redistributing**, maintainers should run on the **exact** bundled binary:

```text
ffmpeg -version
```

and retain the `configuration:` / license lines in release notes or this folder.

## Distribution in Document Studio

- **Mode:** standalone `ffmpeg` executable under `engines/bin/` (external process).
- **Not** linked into `document_studio.exe`.

## Corresponding source

If the shipped build is GPL-licensed, obligations may include offering
corresponding source. See [docs/CORRESPONDING_SOURCE.md](../../docs/CORRESPONDING_SOURCE.md)
and https://ffmpeg.org/download.html

## Uncertainty

Do **not** assume LGPL without verification. Treat FFmpeg as **potentially GPL**
until the bundled binary's license line is documented for each release artifact.
