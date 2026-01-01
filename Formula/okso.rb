class Okso < Formula
  desc "Local assistant harness"
  homepage "https://github.com/cmccomb/okso"
  url "https://github.com/cmccomb/okso/archive/refs/tags/v0.0.1.tar.gz"
  sha256 "3d21414737243c357bee91a2615e23e87d07f7128e925d7fb62ee8c68e1c4f09"
  license "MIT"

  depends_on "llama.cpp"
  depends_on "tesseract"
  depends_on "pandoc"
  depends_on "libxml2"
  depends_on "poppler"
  depends_on "yq"
  depends_on "bash"
  depends_on "coreutils"
  depends_on "jq"
  depends_on "sourcemeta/apps/jsonschema"
  depends_on "gum"
  depends_on "ripgrep"
  depends_on "fd"

  def install
    prefix.install Dir["*"]
    bin.install_symlink prefix/"src/bin/okso" => "okso"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/okso --version")
  end
end
