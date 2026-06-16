# Source-of-truth template for the Homebrew cask. The live copy lives in the
# separate tap repo (abgregs/homebrew-river) at Casks/river.rb. On each
# release, bump `version` and `sha256` (from the published River-x.y.z.dmg.sha256)
# and copy this file across. See packaging/homebrew/README.md.
cask "river" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # release .sha256

  url "https://github.com/abgregs/river/releases/download/v#{version}/River-#{version}.dmg"
  name "River"
  desc "Menu bar dictation app with on-device transcription"
  homepage "https://github.com/abgregs/river"

  depends_on macos: ">= :sonoma" # macOS 14+
  depends_on arch: :arm64        # Apple Silicon only

  app "River.app"

  caveats <<~EOS
    River needs Microphone, Input Monitoring, and Accessibility permissions.
    On first launch, onboarding guides you through granting them in
    System Settings -> Privacy & Security.

    First launch downloads the speech model (~240 MB). Every launch and
    dictation after that is fully on-device.
  EOS

  # Leaves the shared WhisperKit model cache (~/Documents/huggingface) in place
  # on uninstall — it may be used by other tools and is expensive to re-download.
  zap trash: [
    "~/Library/Preferences/com.river.app.plist",
  ]
end
