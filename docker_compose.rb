require 'pathname'
require 'yaml'

class DockerCompose
  def initialize(file, cmd: ["docker-compose"], log:)
    file = Pathname file
    @log = log
    @cmd = cmd
    @config = self.class.trim_config(file)
    @project = project_name(file)
  end

  private def project_name(file)
    src, name =
      if file.basename.to_s =~ /^(.+)\..+\./
        ["filename", $1]
      else
        ["parent directory", file.dirname.basename.to_s.tap { |s|
          s =~ /[a-z0-9]/i or raise "couldn't determine project name"
        }]
      end

    @log[
      name: name,
      file: "#{file.dirname.basename}/#{file.basename}"
    ].info "determined project name from #{src}"

    name
  end

  def self.trim_config(file)
    config = file.open('r') { |f| YAML.load f }
    services = config.fetch "services"
    services.delete "check"
    services.each do |name, svc|
      svc.delete "build"
    end
    YAML.dump config
  end

  def images
    run_parser Images, "images"
  end

  def config_images
    run("config") { |p| YAML.load p }.
      fetch("services").map { |k,v| v["image"] }.compact.uniq
  end

  def volumes
    run("config", "--volumes").split.map { |v| Volume["#{@project}_#{v}", v] }
  end

  Volume = Struct.new :full, :short

  private def run(*cmd)
    out, = full_command! cmd do
      Cleaner.capture3 *cmd, log: @log
    end
    if block_given?
      yield StringIO.new(out)
    else
      out
    end
  end

  private def full_command!(cmd)
    Tempfile.create "dustat-docker-compose" do |f|
      f << @config
      f.close
      cmd.unshift *@cmd
      cmd.insert 1, "-f", f.path, "-p", @project
      yield
    end
  end

  def ps_a
    Utils.retry 5, RETRIABLE_PS_A_ERR, wait: -> { 1 + rand } do
      run_parser PS, "ps", "-a"
    end
  end

  RETRIABLE_PS_A_ERR = -> err do
    Cleaner::ExecError === err && err.stderr =~ /^No such container:/i
  end

  private def run_parser(parser, *cmd)
    run(*cmd) { |p| parser.new p }
  end

  class Parser < Array
    def initialize(io)
      lines = io.each_line.to_a
      lines[1] =~ /^-----/ or raise "unexpected output format"
      lines = lines[2..-1] or raise "unexpected number of lines"
      self.class.unwrap_lines(lines).each do |values|
        rec = self.class::Record.new
        n = 0
        self.class::COLS.zip values do |(attr, type), val|
          rec[attr] = 
            case type
            when nil then next
            when :str then val.to_s
            when :arr then val.to_s.split(",")
            else raise "unknown type: %p" % [type]
            end
          n += 1
        end
        n == rec.size or raise "some columns missing"
        self << rec
      end
    end

    SEP = / {3,}/
    WRAPPABLE_RE = /[-,]$/

    def self.unwrap_lines(lines)
      res = []
      skip = 0
      lines.each_with_index do |line, idx|
        if skip > 0 then skip -= 1; next end
        line.chomp!
        row = []
        pos = 0
        while line[pos..-1] =~ SEP
          col = $`
          adv = col.size + $&.size
          lines[idx+1..-1].each_with_index do |next_line, cur_skip|
            col =~ WRAPPABLE_RE or break
            next_line[pos..-1] =~ SEP or break
            col << $`
            skip = [skip, cur_skip+1].max
          end
          pos += adv
          row << col
        end
        res << row
      end
      res
    end
  end

  class PS < Parser
    COLS = {
      name: :str,
      cmd: nil,
      state: :str,
      ports: :arr,
    }
    Record = Struct.new :name, :state, :ports
  end

  class Images < Parser
    COLS = {
      container: nil,
      repo: :str,
      tag: :str,
      id: :str,
      size: nil,
    }
    Record = Struct.new :repo, :tag, :id
  end
end
