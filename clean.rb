require 'open3'
require_relative 'docker'
require_relative 'docker_compose'

class Cleaner
  def initialize(docker, composes, keep_images: [])
    @log = Utils::Log.new
    @log[keep_images: keep_images].debug "new cleaner"

    @docker, @composes = docker, composes
    @docker_state = DockerState.new @docker, @composes,
      keep_images: keep_images

    vol = self.class.find_volume(composes, "ytdump-meta") \
      or raise "ytdump-meta volume not found"
    @ytdump_meta = YtdumpMeta.new(docker, vol.full)
  end

  def self.find_volume(composes, short)
    composes.each do |c|
      c.volumes.each do |v|
        return v if v.short == short
      end
    end
    nil
  end

  def self.capture3(*cmd, log:)
    log.debug "running: `%s`" % [cmd * " "]
    Open3.capture3(*cmd).tap do |out, err, st|
      st.success? or raise ExecError.new(cmd, out, err, st)
    end
  end

  class ExecError < StandardError
    def initialize(cmd, stdout, stderr, status)
      super()
      @cmd, @stdout, @stderr, @status = cmd, stdout, stderr, status
    end

    attr_reader :cmd, :stdout, :stderr, :status

    def to_s
      "command failed: %p: (exit status: %d) stdout=%p stderr=%p" \
        % [@cmd, @status.exitstatus, @stdout, @stderr]
    end
  end

  def cmd_cleanup(dry_run: true)
    log = @log["cleanup"]
    log[dry_run: dry_run].info "running"

    total_freed = 0
    run = if dry_run
      -> cmd { log.debug "dry run: `%s`" % [cmd * " "] }
    else
      -> cmd { self.class.capture3 *cmd, log: log }
    end

    {docker: @docker_state, ytdump: @ytdump_meta}.each do |name, obj|
      obj_log = log[name]
      obj_log.info "cleaning up"
      freed = obj.cleanup log: obj_log, &run
      obj_log.info "finished - freed %s" % [Utils::Fmt.size(freed)]
      total_freed += freed unless dry_run
    end
    log.info "finished - freed %s" % [Utils::Fmt.size(total_freed)]
  end

  def cmd_stats(influx, write_influx: true)
    log = @log["stats"]
    log[write_influx: write_influx].info "running"

    influx = Utils::Influx.new_client influx
    influx = Utils::Influx::WritesDebug.new influx, log if !write_influx
    timestamp = InfluxDB.convert_timestamp Time.now,
      influx.config.time_precision

    points = [@docker_state, @ytdump_meta].flat_map do |obj|
      obj.stats_influx_points timestamp, log: log
    end

    influx.write_points points
  end

  class YtdumpMeta
    def initialize(docker, vol)
      @docker, @vol = docker, vol
    end

    def stats_influx_points(timestamp, log:)
      du(log).map do |size, name|
        { series: "du_ytdump",
          timestamp: timestamp,
          tags: {playlist: name},
          values: {size: size} }
      end
    end

    private def du(log)
      cmd = [
        "run", "--rm", "-v", "#{@vol}:/meta", "-w", "/meta",
        "bash", "-c", "du -sk *",
      ]
      out, = Cleaner.capture3 *@docker.full_cmd(*cmd), log: log
      out.split("\n").map do |l|
        size, name = l.split "\t", 2
        [size.to_i * 1024, name]
      end
    end

    def cleanup(log:)
      du_total = -> { du(log).sum { |size,| size } }
      before = du_total[]
      yield @docker.full_cmd(
        "run", "--rm", "-v", "#{@vol}:/meta", "-w", "/meta",
        "find", "-type", "f", "-not", "-name", "*.skip", "-delete",
      )
      du_total[] - before
    end
  end

  Usage = Struct.new :wanted, :rest

  class DockerState
    def initialize(docker, composes, keep_images: [])
      super()

      @docker = docker
      df = docker.system_df_v

      wanted = composes.flat_map { |c| c.ps_a.map &:name }
      @containers = Usage.new *df.fetch("Containers").
        reject { |c| c.status =~ /^Up/ }.
        partition { |c| !(c.names & wanted).empty? }

      wanted = @containers.wanted.map(&:image).
        concat(composes.flat_map &:images).
        concat(composes.flat_map &:config_images).
        concat(keep_images).
        map { |i| Docker::NormImage.new i }.
        uniq
      @images = Usage.new *df.fetch("Images").
        partition { |i| wanted.any? { |w| w === i } }

      wanted = composes.flat_map { |c| c.volumes.map &:full }
      @volumes = Usage.new *df.fetch("Volumes").
        partition { |v| wanted.include? v.name }
    end

    attr_reader :containers, :images, :volumes

    def stats_influx_points(timestamp, log:)
      {wanted: true, rest: false}.map do |portion, wanted|
        { series: "du_docker",
          timestamp: timestamp,
          tags: {wanted: wanted},
          values: {}.tap { |values|
            %i[containers images volumes].each do |kind|
              values[kind] = instance_variable_get("@#{kind}").
                public_send(portion).
                sum(&:size)
            end
          } }
      end
    end

    def cleanup(log:)
      freed = 0
      run = -> *cmd do
        yield @docker.full_cmd(*cmd)
      end

      @containers.rest.each do |ctn|
        log.info "deleting container %s" % [ctn]
        begin
          run["rm", ctn.id]
          freed += ctn.size
        rescue ExecError
          raise unless $!.stderr =~ /No such container/
        end
      end

      @images.rest.each do |img|
        log.info "deleting image %s" % [img]
        begin
          run["image", "rm", img.id]
          freed += img.size
        rescue ExecError
          case $!.stderr
          when /has dependent child images/
          when /is being used by running container/
          else raise
          end
        end
      end

      @volumes.rest.each do |vol|
        log.info "deleting volume %s" % [vol]
        begin
          run["volume", "rm", vol.name]
          freed += vol.size
        rescue ExecError
          raise unless $!.stderr =~ /volume is in use/
        end
      end

      freed
    end
  end
end

if $0 == __FILE__
  require 'metacli'

  cleaner = Cleaner.new(Docker.new, [
    DockerCompose.new(["~/code/services2/docker-compose_oneshot"]),
    DockerCompose.new(["~/code/services2/docker-compose/run"]),
  ], keep_images: (ENV["DUSTAT_KEEP_IMAGES"] || "").split(","))

  MetaCLI.new(ARGV).run cleaner
end
