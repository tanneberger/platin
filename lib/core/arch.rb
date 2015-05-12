#
# platin tool set
#
# Architecture-specific stuff, Configuration of the execution platform
require 'core/pmlbase'
module PML

# architectures
class Architecture
  @@register = {}
  def Architecture.register(archname,klass)
    die("architecture #{archname} already registered to #{@@register[archname]}") if @@register[archname]
    @@register[archname] = klass
  end
  def Architecture.simulator_options(opts)
    opts.on("--trace-file FILE", "FILE generated by architecture simulator") { |f| opts.options.trace_file = f }
    @@register.each { |arch,klass|
      klass.simulator_options(opts)
    }
  end
  def Architecture.from_triple(triple, machine_config)
    archname = triple.first
    die("unknown architecture #{triple} (#{@@register})") unless @@register[archname]
    @@register[archname].new(triple, machine_config)
  end
  def return_stall_cycles(ret_instruction, ret_latency)
    0 # no miss costs by the return instruction itself in the traces
  end
  def path_wcet(ilist)
    ilist.length # 1-cycle per instruction pseudo cost
  end
  def edge_wcet(ilist,index,edge)
    0 # control flow is for free
  end
end


# configuration of the execution platform (memory areas, timing, etc.)
class MachineConfig < PMLObject
  ##
  # :attr_reader: memories
  #
  # internal/external memory and their timing
  # * YAML key: +memories+
  # * Type: [ -> MemoryConfig ]
  attr_reader :memories

  ##
  # :attr_reader: memory_areas
  #
  # list of memory area descriptions
  # * YAML key: +memory-areas+
  # * Type: [ -> MemoryArea ]
  attr_reader :memory_areas

  ##
  # :attr_reader: caches
  #
  # list of cache configurations
  # * YAML key: +caches+
  # * Type: [ -> CacheConfig ]
  attr_reader :caches

  def initialize(memories, caches, memory_areas, data = nil)
    @memories, @caches, @memory_areas = memories, caches, memory_areas
    set_yaml_repr(data)
  end

  def MachineConfig.from_pml(ctx, data)
    memories = MemoryConfigList.from_pml(ctx, data['memories'] || [])
    caches   = CacheConfigList.from_pml(ctx, data['caches'] || [])
    areas    = MemoryAreaList.from_pml([memories,caches], data['memory-areas'] || [])
    MachineConfig.new(memories, caches, areas, data)
  end
  def to_pml
    { "memories" => memories.to_pml,
      "memory-areas" => memory_areas.to_pml,
      "caches" => caches.to_pml
    }.delete_if { |k,v| v.nil? }
  end

  def main_memory
    if @memories.size == 1
      @memories.first
    else
      @memories.by_name('main')
    end
  end
end

class MemoryConfigList < PMLList
  extend PMLListGen
  pml_list :MemoryConfig, [:name]
end

class MemoryConfig < PMLObject
  ##
  # :attr_reader: name
  #
  # name of the internal or external memory
  # * YAML key: +name+
  # * Type: <tt>str</tt>
  attr_reader :name

  ##
  # :attr_reader: size
  #
  # size in bytes
  # * YAML key: +size+
  # * Type: <tt>int</tt>
  attr_reader :size

  ##
  # :attr_reader: transfer_size
  #
  # number of bytes for a single access (block size)
  # * YAML key: +transfer-size+
  # * Type: <tt>int</tt>
  attr_reader :transfer_size

  # we need to transfer ceil(line size / transfer-size) blocks
  # for one cache line
  def blocks_per_line(cache_line_size)
    (cache_line_size + transfer_size - 1) / transfer_size
  end

  ##
  # :attr_reader: read_latency
  #
  # latency per read request
  # * YAML key: +read-latency+
  # * Type: <tt>int</tt>
  attr_reader :read_latency

  ##
  # :attr_reader: read_transfer_time
  #
  # cycles to the transfer one block from memory (excluding per-request latency)
  # * YAML key: +read-transfer-time+
  # * Type: <tt>int</tt>
  attr_reader :read_transfer_time

  ##
  # :attr_reader: write_latency
  #
  # latency per write request
  # * YAML key: +write-latency+
  # * Type: <tt>int</tt>
  attr_reader :write_latency

  ##
  # :attr_reader: write_transfer_time
  #
  # cycles to the transfer one block from memory (excluding per-request latency)
  # * YAML key: +write-transfer-time+
  # * Type: <tt>int</tt>
  attr_reader :write_transfer_time

  def initialize(name, size, transfer_size, read_latency, read_transfer_time, write_latency,
                 write_transfer_time, data=nil)
    @name, @size, @transfer_size, @read_latency, @read_transfer_time, @write_latency, @write_transfer_time =
      name, size, transfer_size, read_latency, read_transfer_time, write_latency, write_transfer_time
    set_yaml_repr(data)
  end

  def MemoryConfig.from_pml(ctx, data)
    MemoryConfig.new(
      data['name'],
      data['size'],
      data['transfer-size'],
      data['read-latency'],
      data['read-transfer-time'],
      data['write-latency'],
      data['write-transfer-time'],
      data)
  end
  def to_pml
    { "name" => name,
      "size" => size,
      "transfer-size" => transfer_size,
      "read-latency" => read_latency,
      "read-transfer-time" => read_transfer_time,
      "write-latency" => write_latency,
      "write-transfer-time" => write_transfer_time,
    }.delete_if { |k,v| v.nil? }
  end


  # delay for an (not necessarily aligned) read request
  def read_delay(start_address, size)
    start_padding = start_address & (@transfer_size-1)
    read_delay_aligned(start_padding + size)
  end

  # delay for an (not necessarily aligned) read request
  def max_read_delay(size)
    read_delay(size + transfer_size - 4)
  end

  # delay for a read request aligned to the transfer (burst) size
  def read_delay_aligned(size)
    read_latency + bytes_to_blocks(size) * read_transfer_time
  end

  # delay for an (not necessarily aligned write_request)
  def write_delay(start_address, size)
    start_padding = start_address & (@transfer_size-1)
    write_delay_aligned(start_padding + size)
  end

  def max_write_delay(size)
    write_delay(size + transfer_size - 4)
  end

  def write_delay_aligned(size)
    write_latency + bytes_to_blocks(size) * write_transfer_time
  end


  def bytes_to_blocks(bytes)
    div_ceil(bytes,transfer_size)
  end

  def ideal?
    [read_latency, read_transfer_time, write_latency, write_transfer_time].all? { |t| t == 0 }
  end
end # class MemoryConfig


# list of cache configurations
class CacheConfigList < PMLList
  extend PMLListGen
  pml_list :CacheConfig, [:name], [:type]
end

class CacheConfig < PMLObject
  ##
  # :attr_reader: name
  #
  # unique name of the cache
  # * YAML key: +name+
  # * Type: <tt>str</tt>
  attr_reader :name

  ##
  # :attr_reader: type
  #
  # type of the cache
  # * YAML key: +type+
  # * Type: <tt>"set-associative" | "method-cache" | "stack-cache"</tt>
  attr_reader :type

  ##
  # :attr_reader: policy
  #
  # replacement policy
  # * YAML key: +policy+
  # * Type: <tt>str</tt>
  attr_reader :policy

  ##
  # :attr_reader: associativity
  #
  # associativity of the cache
  # * YAML key: +associativity+
  # * Type: <tt>int</tt>
  attr_reader :associativity

  ##
  # :attr_reader: block_size
  #
  # size of a cache block / cache line
  # * YAML key: +block-size+
  # * Type: <tt>int</tt>
  attr_reader :block_size

  ##
  # :attr_reader: attributes
  #
  # additional attributes for the cache (key/value pairs)
  attr_reader :attributes

  def get_attribute(key)
    attribute_pair = attributes.find { |e| e['key'] == key }
    return nil unless attribute_pair
    attribute_pair['value']
  end

  # synonymous with block_size at the moment
  def line_size
    block_size
  end

  def bytes_to_blocks(bytes)
    (bytes+block_size-1) / block_size
  end

  ##
  # :attr_reader: size
  #
  # size of the cache in bytes
  # * YAML key: +size+
  # * Type: <tt>int</tt>
  attr_reader :size

  def initialize(name, type, policy, associativity, block_size, size, data = nil)
    @name, @type, @policy, @associativity, @block_size, @size =
      name, type, policy, associativity, block_size, size
    set_yaml_repr(data)
    @attributes = data ? (data['attributes'] ||= []) : []
  end

  def CacheConfig.from_pml(ctx, data)
    CacheConfig.new(
      data['name'],
      data['type'],
      data['policy'],
      data['associativity'],
      data['block-size'],
      data['size'],
      data)
  end
  def to_pml
    { "name" => name,
      "type" => type,
      "policy" => policy,
      "associativity" => associativity,
      "block-size" => block_size,
      "size" => size,
      "attributes" => attributes
    }.delete_if { |k,v| v.nil? }
  end
end # class CacheConfig

class MemoryAreaList < PMLList
  extend PMLListGen
  pml_list :MemoryArea,[:name],[:type]
end

# list of memory area descriptions
class MemoryArea < PMLObject
  ##
  # :attr_reader: name
  #
  # unique name of the memory area
  # * YAML key: +name+
  # * Type: <tt>str</tt>
  attr_reader :name

  ##
  # :attr_reader: type
  #
  # type / address space
  # * YAML key: +type+
  # * Type: <tt>"code" | "data" | "scratchpad"</tt>
  attr_reader :type

  ##
  # :attr_reader: cache
  #
  # name of the cache configured for this memory area (possibly bypassed)
  # * YAML key: +cache+
  # * Type: <tt>str</tt>
  attr_reader :cache

  ##
  # :attr_reader: memory
  #
  # name of the internal or external memory this area is mapped to
  # * YAML key: +memory+
  # * Type: <tt>str</tt>
  attr_reader :memory

  ##
  # :attr_reader: address_range
  #
  # due to an aiT workaround, we may update this range on-the-fly
  # * YAML key: +address-range+
  # * Type: -> ValueRange
  attr_accessor :address_range

  ##
  # :attr_reader: attributes
  #
  # additional attributes for the memory area (key/value pairs)
  attr_reader :attributes

  def get_attribute(key)
    attribute_pair = attributes.find { |e| e['key'] == key }
    return nil unless attribute_pair
    attribute_pair['value']
  end


  def initialize(name, type, cache, memory, address_range,data = nil)
    @name, @type, @cache, @memory, @address_range =
      name, type, cache, memory, address_range
    set_yaml_repr(data)
    @attributes = data ? (data['attributes'] ||= []) : []
  end

  def MemoryArea.from_pml(memories_caches, data)
    memories, caches = memories_caches
    MemoryArea.new(
      data['name'],
      data['type'],
      data['cache'] ?  caches.by_name(data['cache']) : nil,
      data['memory'] ? memories.by_name(data['memory']) : nil,
      data['address-range'] ? ValueRange.from_pml(nil, data['address-range']) : nil,
      data)
  end
  def to_pml
    { "name" => name,
      "type" => type,
      "cache" => cache ? cache.name : nil,
      "memory" => memory ? memory.name : nil,
      "address-range" => address_range.to_pml,
      "attributes" => attributes
    }.delete_if { |k,v| v.nil? }
  end
end # class MemoryArea

end # module PML

require 'arch/patmos'
require 'arch/arm'

