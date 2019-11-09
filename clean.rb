require 'pathname'
require 'utils'
require_relative 'docker'
require_relative 'docker_compose'

if $0 == __FILE__
  dcs = [
    DockerCompose.new(["~/code/services2/docker-compose_oneshot"]),
    DockerCompose.new(["~/code/services2/docker-compose/run"]),
  ]
  # pp vols: dcs.map(&:volumes)
  pp pss: dcs.map(&:ps_a)

#   docker = Docker.new
#   df = docker.system_df_v
#   ps = docker.ps_a

#   pp ps: ps, df: df
end
