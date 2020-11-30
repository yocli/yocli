require "formula"

class Yo < Formula
  desc "CLI to pair with the yo iOS app"
  homepage "https://github.com/dongcarl/yocli"
  url "https://github.com/dongcarl/yocli/archive/v0.0.1.tar.gz", :using => GitHubPrivateRepositoryReleaseDownloadStrategy
  sha256 "4b302b150fde00649f1fd08f4fa416459eccbb0f3c0427f0437f39b4a2a7fa59"
  head "https://github.com/dongcarl/yocli.git"

  depends_on "qrencode"

  def install
    system "make", "PREFIX=#{prefix}", "install"
  end

  test do
    system "true"
  end
end
