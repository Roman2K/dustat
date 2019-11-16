require 'json'
require_relative 'docker_compose'

class Docker
  def self.short_id(id)
    unless ID === id
      id = begin
        ID.new id
      rescue ID::InvalidHashError
        id
      end
    end
    id.to_s
  end

  def initialize(cmd=["docker"])
    @cmd = cmd
  end

  def system_df_v
    run SystemDF, "system", "df", "-v"
    # TODO rescue `Error response from daemon: a disk usage operation is already
    # running`
  end

  def ps_a
    run PS, "ps", "-a"
  end

  def full_cmd(*cmd)
    @cmd + cmd
  end

  def run_json(*cmd)
    run JSONResult, *cmd
  end

  private def run(parser, *cmd)
    IO.popen full_cmd(*cmd, "--format", "{{json .}}") do |p|
      p.ungetc (p.getc or raise "command failed: `%s`" % [cmd * " "])
      parser.new p
    end
  end

  class JSONResult < Array
    def initialize(io)
      io.each_line do |line|
        self << JSON.load(line)
      end
    end
  end

  class Multisection < Hash
    def initialize(io)
      JSON.load(io).each do |k,items|
        self[k] = self.class.const_get(k).new(items)
      end
    end
  end

  class Section < Array
    def initialize(items)
      items = items.each_line.map { |l| JSON.load l } unless Array === items
      super items.map { |i| new_record i }
    end

    private def new_record(h)
      type = self.class::Record
      values = []
      self.class::COLS.each do |k, type|
        val = h.fetch k
        values << \
          case type
          when nil then next
          when :str then val
          when :arr then val.split(",")
          when :int then val.to_i
          when :size then self.class.conv_size(val)
          else raise "unknown type: %p" % [type]
          end
      end
      values.size == type.members.size or raise "wrong number of values"
      type.new *values
    end

    UNITS = %w[B KB MB GB TB]

    def self.conv_size(s)
      num = s[/^[\d\.]+/] or raise "invalid size: %p" % [s]
      num, unit = num.to_f, $'
      unit = UNITS.index(unit.upcase) or raise "unknown unit: %p" % [s]
      num * (1024 ** unit)
    end
  end # Section

  class SystemDF < Multisection
    class Images < Section
      COLS = {
        "Repository" => :str,
        "Tag" => :str,
        "ID" => :str,
        "Size" => :size,
        "SharedSize" => :size,
        "UniqueSize" => :size,
        "VirtualSize" => :size,
        "Containers" => :int,
      }
      Record = Struct.new \
        :repo, :tag, :id,
        :size, :shared_size, :unique_size, :virtual_size, :containers \
      do
        def to_s
          "#{repo}:#{tag} (#{Docker.short_id id})"
        end
      end
    end

    class Containers < Section
      COLS = {
        "ID" => :str,
        "Image" => :str,
        "Size" => :size,
        "Status" => :str,
        "Names" => :arr,
      }
      Record = Struct.new :id, :image, :size, :status, :names do
        def to_s
          "#{names * ","} (#{Docker.short_id id}) - #{status}"
        end
      end
    end

    class Volumes < Section
      COLS = {
        "Name" => :str,
        "Links" => :int,
        "Size" => :size,
      }
      Record = Struct.new :name, :links, :size do
        alias id name
        def to_s
          Docker.short_id name
        end
      end
    end

    class BuildCache < Section
      COLS = {
        id: :str,
        # type: nil,
        # size: :size,
        # created_at: nil,
        # last_used: nil,
        # usage: nil,
        # shared: nil,
      }
      Record = Struct.new :id#, :size
    end
  end # SystemDF

  class PS < Section
    COLS = {
      "ID" => :str,
      "Image" => :str,
      "Size" => :size,
      "Status" => :str,
      "Names" => :arr,
    }
    Record = Struct.new :id, :image, :size, :status, :names
  end

  class NormImage < Struct.new :repo, :tag, :id
    LATEST = "latest".freeze
    NONE = "<none>".freeze

    def initialize(x)
      super *case x
        when Docker::SystemDF::Images::Record, DockerCompose::Images::Record
          [x.repo, x.tag, x.id].map { |s| s == NONE ? nil : s }
        when /^sha256:[a-f0-9]+$/i
          [nil, nil, x]
        when /:/
          [$`, $', nil]
        when String
          [x, nil, nil]
        else
          raise "unrecognized image representation: %p" % [x]
        end

      self.id = ID.new id if id
      self.tag ||= LATEST if repo
    end

    def to_s
      s = (tag == LATEST ? "#{repo}" : "#{repo}:#{tag}") if repo
      if id
        if s
          s << " (#{id})"
        else
          s = id.to_s
        end
      end
      s
    end

    def ===(x)
      x = self.class.new x unless self.class === x
      match? x
    end

    def match?(b)
      imgs = [self, b]
      if (ids = imgs.map &:id).all?
        self.class.normalize_ids(ids)
      else
        imgs.map { |i| [i.repo, i.tag] }
      end.uniq.size == 1
    end

    def self.normalize_ids(ids)
      min = ids.map { |id| id.im_hash.size }.min
      ids.map { |id| id = id.dup; id.im_hash = id.im_hash[0,min]; id }
    end
  end

  class ID < Struct.new :algo, :im_hash
    DEFAULT_ALGO = "sha256".freeze

    class InvalidHashError < ArgumentError
    end

    def initialize(s)
      s = s.downcase
      super *if s =~ /^(.+):/
          [$1, $']
        else
          [DEFAULT_ALGO, s]
        end
      im_hash =~ /\A[a-f0-9]+\z/ or raise InvalidHashError, "invalid hash"
    end

    def to_s
      s = []
      s << algo unless algo == DEFAULT_ALGO
      s << im_hash[0,12]
      s.join ":"
    end
  end
end
