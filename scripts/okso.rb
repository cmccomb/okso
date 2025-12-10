class Okso < Formula
  desc "Local MCP-inspired assistant harness"
  homepage "https://github.com/cmccomb/okso"
  version "0.0.0-main"
  url "https://github.com/cmccomb/okso/archive/refs/heads/main.tar.gz"
  sha256 "d644d11f5d35343fcf9864b7c4517cb721ace2a529ad71815157c6302d808739"

  depends_on "llama.cpp"
  depends_on "tesseract"
  depends_on "pandoc"
  depends_on "poppler"
  depends_on "yq"
  depends_on "bash"
  depends_on "coreutils"
  depends_on "jq"
  depends_on "gum"

  def install
    prefix.install Dir["*"]
    bin.install_symlink prefix/"src/bin/okso" => "okso"
  end

  test do
    assert_predicate bin/"okso", :exist?
  end
end
