# Homebrew cask for Shortcut Divan. The Release workflow fills in the version and checksum
# and pushes the result to codingwithsaeed/homebrew-tap (Casks/shortcut-divan.rb).
cask "shortcut-divan" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/codingwithsaeed/shortcut-divan/releases/download/v#{version}/Shortcut-Divan-#{version}.dmg"
  name "Shortcut Divan"
  desc "Keyboard shortcuts in a desktop widget"
  homepage "https://github.com/codingwithsaeed/shortcut-divan"

  depends_on macos: ">= :sonoma"

  app "Shortcut Divan.app"

  # Signed ad hoc, without an Apple Developer ID: without this, macOS refuses to open it the
  # first time. The widget registers when the app first opens.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Shortcut Divan.app"]
  end

  zap trash: [
    "~/Library/Application Support/Shortcut Divan",
    "~/Library/Containers/io.github.codingwithsaeed.shortcutdivan.widget",
    "~/Library/Preferences/io.github.codingwithsaeed.shortcutdivan.plist",
  ]
end
