$:.unshift __dir__ + "/.."
require 'docker'
require 'minitest/autorun'

class DockerTest < Minitest::Test
  def test_system_df
    df = from_io Docker::SystemDF.new, "system_df"
    assert_equal 4, df.size

    imgs = df.fetch(:images).to_a

    im = imgs.fetch 0
    assert_equal "d559a9dad056", im.id
    assert_equal 307757056, im.size

    im = imgs.fetch(-1)
    assert_equal "ef3fdd98de8d", im.id
    assert_equal 93, imgs.count

    assert_equal 24, df.fetch(:containers).count
    assert_equal 15, df.fetch(:volumes).count
    assert_equal 0, df.fetch(:caches).count

    assert_equal 0, Docker::SystemDF.new.from_io(StringIO.new("")).size
  end

  private def from_io(parser, f)
    File.open File.join(__dir__, f) do |f|
      parser.from_io(f)
    end
  end

  def test_ps
    ctns = from_io Docker::PS.new, "ps"
    pp ctns
  end
end
