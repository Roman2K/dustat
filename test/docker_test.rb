$:.unshift __dir__ + "/.."
require 'docker'
require 'minitest/autorun'

class DockerTest < Minitest::Test
  def test_system_df
    df = from_io Docker::SystemDF, "system_df_a.json"
    assert_equal 4, df.size

    imgs = df.fetch("Images")
    im = imgs.fetch 0
    assert_match /^sha256:d559a9dad056/, im.id
    assert_equal 308281344, im.size
    im = imgs.fetch(-1)
    assert_match /^sha256:ef3fdd98de8d/, im.id

    assert_equal 93, imgs.count
    assert_equal 24, df.fetch("Containers").count
    assert_equal 15, df.fetch("Volumes").count
    assert_equal 0, df.fetch("BuildCache").count
  end

  private def from_io(parser, f)
    File.open File.join(__dir__, f) do |f|
      parser.new f
    end
  end

  def test_ps
    ctns = from_io Docker::PS, "ps_a.json"
    assert_equal 24, ctns.size

    ctn = ctns.fetch 0
    assert_equal "5b0491df9933", ctn.id
    assert_equal "ytdump", ctn.image
    assert_equal 0, ctn.size
    assert_equal "Created", ctn.status
    assert_equal ["services2_ytdump_run_4ec94cd52717"], ctn.names
  end
end
