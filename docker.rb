module Docker
  class MultisectionParser
    def from_io(io)
      res, cur = {}, nil
      sep, skip_sep = true, 0
      until io.eof?
        l = io.readline.chomp
        case
        when l.empty?
          if skip_sep > 0 then skip_sep -= 1 else sep = true end
        when sep
          id, section = (section_parser(l) or raise "unknown section: %p" % [l])
          cur = res[id] = section.new
          sep = false
          skip_sep = 1
        when cur
          cur << l
        else
          raise "unhandled line: %p" % [l]
        end
      end
      res
    end

    private def section_parser(s)
      self.class::SECTIONS.each do |id,(re,cl)|
        re === s or next
        return [id, cl] if re === s
      end
      nil
    end
  end # MultisectionParser

  class SectionParser
    def initialize
      @items = nil
    end

    def each(&block); @items&.each &block end
    include Enumerable

    def <<(s)
      values = s.split(/ {3,}/)
      actual, expected = values.size, self.class::COLS.size
      actual == expected \
        or raise "unexpected number of columns: %d instead of %d" \
          % [actual, expected]
      if @items.nil?
        @items = []
      else
        rec = self.class::Record.new
        types = self.class::COLS.values
        self.class::COLS.zip(values) do |(name, type), val|
          rec[name] = 
            case type
            when nil then next
            when :str then val
            when :arr then val.split(",")
            when :int then val.to_i
            when :size then self.class.conv_size(val)
            else raise "unknown type: %p" % [type]
            end
        end
        @items << rec
      end
      self
    end

    UNITS = %w[B KB MB GB TB]

    def self.conv_size(s)
      num = s[/^[\d\.]+/] or raise "invalid size: %p" % [s]
      num, unit = num.to_f, $'
      unit = UNITS.index(unit) or raise "unknown unit: %p" % [s]
      num * (1024 ** unit)
    end
  end # SectionParser

  class SystemDF < MultisectionParser
    class Images < SectionParser
      COLS = {
        repo: :str,
        tag: :str,
        id: :str,
        created_at: nil,
        size: :size,
        shared_size: :size,
        unique_size: :size,
        containers: :int,
      }

      Record = Struct.new \
        :repo, :tag, :id,
        :size, :shared_size, :unique_size, :containers
    end

    class Containers < SectionParser
      COLS = {
        id: :str,
        image: :str,
        cmd: nil,
        local_vols: nil,
        size: :size,
        created_at: nil,
        status: :str,
        names: :arr,
      }

      Record = Struct.new :id, :image, :size, :status, :names
    end

    class Volumes < SectionParser
      COLS = {
        name: :str,
        links: :int,
        size: :size,
      }

      Record = Struct.new :name, :links, :size
    end

    class Caches < SectionParser
      COLS = {
        id: :str,
        type: nil,
        size: :size,
        created_at: nil,
        last_used: nil,
        usage: nil,
        shared: nil,
      }

      Record = Struct.new :id, :size
    end

    SECTIONS = {
      images:     [/^images /i,      Images],
      containers: [/^containers /i,  Containers],
      volumes:    [/^local vol/i,    Volumes],
      caches:     [/^build cache/i,  Caches],
    }
  end # SystemDF

  class PS < SectionParser
    COLS = {
      id: :str,
      image: :str,
      cmd: nil,
      created_at: nil,
      status: :str,
      size: :size,
      names: :arr,
    }

    Record = Struct.new :id, :image, :size, :status, :names
  end
end
