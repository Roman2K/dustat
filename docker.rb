require 'json'

class Docker
  def initialize(cmd)
    @cmd = cmd
  end

  def system_df_a
    run SystemDF, "system", "df", "-a"
  end

  private def run(parser, *cmd)
    IO.popen [*@cmd, *cmd, "--format", "{{json .}}"] do |p|
      parser.new p
    end
  end

  class Multisection < Hash
    def initialize(io)
      JSON.load(io).each do |k,items|
        self[k] = self.class.const_get(k).new(items)
      end
      freeze
    end
  end

  class Section < Array
    def initialize(items)
      items = items.each_line.map { |l| JSON.load l } unless Array === items
      super items.map { |i| new_record i }
      freeze
    end

    private def new_record(h)
      type = self.class::Record
      values = self.class::COLS.map { |k, type|
        val = h.fetch k
        case type
        when nil then next
        when :str then val
        when :arr then val.split(",")
        when :int then val.to_i
        when :size then self.class.conv_size(val)
        else raise "unknown type: %p" % [type]
        end
      }
      values.size == type.members.size or raise "wrong number of values"
      type.new *values
    end

    UNITS = %w[B KB MB GB TB]

    def self.conv_size(s)
      num = s[/^[\d\.]+/] or raise "invalid size: %p" % [s]
      num, unit = num.to_f, $'
      unit = UNITS.index(unit) or raise "unknown unit: %p" % [s]
      num * (1024 ** unit)
    end
  end # SectionParser

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
        :size, :shared_size, :unique_size, :virtual_size, :containers
    end

    class Containers < Section
      COLS = {
        "ID" => :str,
        "Image" => :str,
        "Size" => :size,
        "Status" => :str,
        "Names" => :arr,
      }

      Record = Struct.new :id, :image, :size, :status, :names
    end

    class Volumes < Section
      COLS = {
        "Name" => :str,
        "Links" => :int,
        "Size" => :size,
      }

      Record = Struct.new :name, :links, :size
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
end
