$:.unshift __dir__ + "/.."
require 'minitest/autorun'
require 'docker_compose'

class DockerComposeTest < Minitest::Test
  def test_unwrap_lines
    lines = File.read(__dir__ + "/compose_ps_a").split("\n")[2..-1]
    res = DockerCompose::Parser.unwrap_lines(lines)
    assert_equal 10, res.size
    assert_equal "0.0.0.0:28086->8086/tcp,0.0.0.0:28088->8088/tcp",
      res.fetch(1).fetch(3)
    assert_equal "docker-compose_prices-websocket_1",
      res.fetch(3).fetch(0)

    lines = File.read(__dir__ + "/compose_ps_a").split("\n")[2..-1]
    res = DockerCompose::Parser.unwrap_lines(lines[-2..-1])
    assert_equal [3,4], res.map(&:size)
    assert_equal %w[Up Up], res.map { |a| a[2] }
    assert_equal [nil, "0.0.0.0:23128->23128/tcp"], res.map { |a| a[3] }
  end

  def test_ps_a
    ps = from_io DockerCompose::PS, "compose_ps_a"
    assert_equal 10, ps.size

    ctn = ps.fetch 0
    assert_equal "docker-compose_grafana_1", ctn.name
    assert_equal "Up", ctn.state
    assert_equal ["3000/tcp"], ctn.ports

    ctn = ps.fetch 3
    assert_equal "docker-compose_prices-websocket_1", ctn.name
    assert_equal "Up", ctn.state
    assert_equal [], ctn.ports

    ctn = ps.fetch 4
    assert_equal "docker-compose_prices_1", ctn.name
    assert_equal "Up", ctn.state
    assert_equal [], ctn.ports

    ctn = ps.fetch 5
    assert_equal "docker-compose_radarr_1", ctn.name
    assert_equal "Up", ctn.state
    assert_equal ["7878/tcp"], ctn.ports

    ctn = ps.fetch 9
    assert_equal "docker-compose_wis-squid_1", ctn.name
    assert_equal "Up", ctn.state
    assert_equal ["0.0.0.0:23128->23128/tcp"], ctn.ports
  end

  def test_images
    imgs = from_io DockerCompose::Images, "compose_images"
    assert_equal 1, imgs.size

    img = imgs.fetch 0
    assert_equal "ytdump", img.repo
    assert_equal "latest", img.tag
    assert_equal "04ec0613c084", img.id
  end

  private def from_io(parser, f)
    File.open File.join(__dir__, f) do |f|
      parser.new f
    end
  end
end
