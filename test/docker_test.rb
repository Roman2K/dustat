$:.unshift __dir__ + "/.."
require 'docker'
require 'minitest/autorun'

class DockerTest < Minitest::Test
  def test_system_df
    df = from_io Docker::SystemDF, "system_df_v.json"
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

  def test_NormImage
    a = Docker::NormImage.new("sha256:7b3df4ce7e5e")
    b = Docker::NormImage.new("sha256:7b3df4ce7e5efff")
    c = Docker::NormImage.new("sha256:7b3df4ce7e5eff0")
    assert a === a
    assert a === b
    refute b === c
    refute c === b

    img = Docker::NormImage.new("traefik")
    assert_equal "traefik", img.repo
    assert_equal "latest", img.tag
    assert_nil img.id

    b = Docker::NormImage.new("traefik")
    assert img === b

    b = Docker::NormImage.new("traefik:latest")
    assert img === b

    b = Docker::NormImage.new("traefik:2")
    refute img === b

    b = Docker::NormImage.new(DockerCompose::Images::Record[
      "traefik", "latest", nil,
    ])
    assert img === b

    b = Docker::NormImage.new(DockerCompose::Images::Record[
      "traefik", "latest", "7b3df4ce7e5e",
    ])
    assert img === b

    img = Docker::NormImage.new(DockerCompose::Images::Record[
      "traefik", "latest", "0b3df4ce7e5e",
    ])
    refute img === b
  end
end
