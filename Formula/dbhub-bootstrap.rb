class DbhubBootstrap < Formula
  desc "One command to give your AI assistant database access"
  homepage "https://github.com/m-gris/dbhub-bootstrap"
  url "https://github.com/m-gris/dbhub-bootstrap/archive/refs/heads/main.tar.gz"
  version "0.1.0"
  license "MIT"

  depends_on "gum"
  depends_on "just"

  def install
    # Install the bootstrap script (source of truth)
    bin.install "bootstrap.sh" => "dbhub-bootstrap"

    # Install the CLI wrapper (same logic as gh-dbhub)
    bin.install "gh-dbhub" => "dbhub"
  end

  def post_install
    # Run bootstrap in auto mode to complete setup
    system bin/"dbhub-bootstrap", "--auto"
  end

  def caveats
    <<~EOS
      Setup complete! To configure a database for your project:

        dbhub init

      Or using just:

        just -g mcp dbhub init
    EOS
  end

  test do
    assert_predicate bin/"dbhub", :executable?
    assert_predicate bin/"dbhub-bootstrap", :executable?
  end
end
