# Source-of-truth template for the Homebrew cask. The live copy lives in the
# separate tap repo (abgregs/homebrew-freeflow) at Casks/freeflow.rb. On each
# release, bump `version` and `sha256` (from the published FreeFlow-x.y.z.dmg.sha256)
# and copy this file across. See packaging/homebrew/README.md.
cask "freeflow" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # release .sha256

  url "https://github.com/abgregs/free-flow/releases/download/v#{version}/FreeFlow-#{version}.dmg"
  name "Free Flow"
  desc "Menu bar dictation app with on-device transcription"
  homepage "https://github.com/abgregs/free-flow"

  depends_on macos: ">= :sonoma" # macOS 14+
  depends_on arch: :arm64        # Apple Silicon only

  app "FreeFlow.app"

  caveats <<~EOS
    Free Flow needs Microphone, Input Monitoring, and Accessibility permissions.
    On first launch, onboarding guides you through granting them in
    System Settings -> Privacy & Security.

    First launch downloads the speech model (~240 MB). Every launch and
    dictation after that is fully on-device.
  EOS

  # Leaves the shared WhisperKit model cache (~/Documents/huggingface) in place
  # on uninstall — it may be used by other tools and is expensive to re-download.
  zap trash: [
    "~/Library/Preferences/com.freeflow.app.plist",
  ]
end
