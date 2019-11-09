require 'pathname'
require 'utils'

class DockerCompose
  def initialize(exe)
    @exe = Utils.expand_tilde(Pathname exe)
    @project = @exe.dirname.basename.to_s.tap { |s|
      s =~ /[a-z0-9]/i or raise "couldn't determine project name"
    }
  end

  def volumes
    vols = 
      IO.popen([@exe.to_s, "config", "--volumes"], &:read).
        tap { $?.success? or raise "config --volumes failed" }.
        split("\n").
        map { |name| Volume[self, name] }
  end

  Volume = Struct.new :compose, :name do
  end
end

if $0 == __FILE__
  dcs = [
    DockerCompose.new("~/code/services2/docker-compose_oneshot"),
    DockerCompose.new("~/code/services2/docker-compose/run"),
  ]
  pp dcs.map &:volumes
end
