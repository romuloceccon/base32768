class BitReader
  def initialize(file)
    @file = file
    @val = 0
    @cnt = 0
  end
  
  def read_bits(n)
    result = 0
    p = 0
    while n > 0
      if @cnt == 0
        v = @file.read(1)
        break unless v
        @val = v.ord
        @cnt = 8
      end
      c = n > @cnt ? @cnt : n
      m = (1 << c) - 1
      result = result | (@val & m) << p
      p += c
      n -= c
      @val = @val >> c
      @cnt -= c
    end
    [result, p]
  end
end

class BitWriter
  def initialize(file, buffer_size)
    @file = file
    @buffer_size = buffer_size
    @buffer_size = 0 if @buffer_size < 0
    @val = 0
    @cnt = 0
  end

  def flush(pad)
    if pad >= @cnt || (@cnt - pad) % 8 != 0
      raise ArgumentError, "Bad padding"
    end
    @cnt -= pad
    flush_buffer(0)
    @val = 0
    @cnt = 0
  end
  
  def write_bits(val, n)
    @val = @val | (val << @cnt)
    @cnt += n
    flush_buffer(@buffer_size)
  end

private

  def flush_buffer(n)
    while @cnt >= n + 8
      @file.write((@val & 0xff).chr)
      @val = @val >> 8
      @cnt -= 8
    end
  end
end

module Base32768
  def self.encode(input, output)
    reader = BitReader.new(input)
    loop do
      val, bits = reader.read_bits(15)
      encode_integer(val, output) if bits > 0
      encode_integer(0x7fff + 15 - bits, output) if bits > 0 && bits < 15
      return if bits < 15
    end
  end
  
  def self.decode(input, output)
    writer = BitWriter.new(output, 15)
    loop do
      if s = input.read(2)
        q, p = s.bytes.map { |x| x - 0x4a }
        raise ArgumentError, "Non-even char count" unless p && q
        
        val = p * 181 + q
        if p < 0 || q < 0 || val - 0x7fff > 15
          raise ArgumentError, "Invalid byte sequence: \\x%02x\\x%02x" % s.bytes
        end
        
        if val <= 0x7fff
          writer.write_bits(val, 15)
        else
          writer.flush(val - 0x7fff)
          raise ArgumentError, "Data remaining after padding" if input.read(1)
          return
        end
      else
        writer.flush(0)
        return
      end
    end
  end
  
  def self.encode_integer(val, output)
    p, q = val.divmod(181)
    output.write((q + 0x4a).chr)
    output.write((p + 0x4a).chr)
  end
end

if $0 == __FILE__
  case ARGV.first
  when '-e' then
    STDIN.binmode
    STDOUT.binmode
    Base32768.encode(STDIN, STDOUT)
    exit(0)
  when '-d' then
    STDIN.binmode
    STDOUT.binmode
    Base32768.decode(STDIN, STDOUT)
    exit(0)
  end
  
  require 'test/unit'
  
  class BitReaderTest < Test::Unit::TestCase
    def create_bit_reader(str)
      file = StringIO.new(str.b)
      file.rewind
      BitReader.new(file)
    end
    
    def test_read_whole_byte
      br = create_bit_reader("\xc3")
      assert_equal([0xc3, 8], br.read_bits(8))
    end
    
    def test_read_partial_byte
      br = create_bit_reader("\xc3")
      assert_equal([0x03, 4], br.read_bits(4))
    end
    
    def test_read_partial_byte_continuation
      br = create_bit_reader("\xc3")
      br.read_bits(4)
      assert_equal([0x0c, 4], br.read_bits(4))
    end
    
    def test_read_multi_byte
      br = create_bit_reader("\xc3\xd4")
      assert_equal([0x4c3, 12], br.read_bits(12))
    end
    
    def test_read_byte_at_eof
      br = create_bit_reader("\xc3")
      br.read_bits(4)
      assert_equal([0x0c, 4], br.read_bits(8))
    end
    
    def test_read_byte_past_eof
      br = create_bit_reader("\xc3")
      br.read_bits(8)
      assert_equal([0, 0], br.read_bits(8))
    end
  end
  
  class BitWriterTest < Test::Unit::TestCase
    def create_bit_writer(buffer_size)
      s = StringIO.new
      [BitWriter.new(s, buffer_size), s]
    end
    
    def test_write_whole_byte
      bw, s = create_bit_writer(0)
      bw.write_bits(0xc3, 8)
      assert_equal("\xc3".b, s.string.b)
    end
    
    def test_write_partial_byte
      bw, s = create_bit_writer(0)
      bw.write_bits(0x03, 4)
      bw.write_bits(0x0c, 4)
      assert_equal("\xc3".b, s.string.b)
    end
    
    def test_write_second_byte
      bw, s = create_bit_writer(0)
      bw.write_bits(0xc3, 8)
      bw.write_bits(0xd4, 8)
      assert_equal("\xc3\xd4".b, s.string.b)
    end
    
    def test_write_byte_continuation
      bw, s = create_bit_writer(0)
      bw.write_bits(0x03, 4)
      bw.write_bits(0x4c, 8)
      bw.write_bits(0x0d, 4)
      assert_equal("\xc3\xd4".b, s.string.b)
    end
    
    def test_write_multi_byte
      bw, s = create_bit_writer(0)
      bw.write_bits(0xd4c3, 16)
      assert_equal("\xc3\xd4".b, s.string.b)
    end
    
    def test_buffer_bits
      bw, s = create_bit_writer(16)
      bw.write_bits(0x00c3, 23)
      assert_equal("".b, s.string.b)
      bw.write_bits(0, 1)
      assert_equal("\xc3".b, s.string.b)
    end
    
    def test_flush_buffer
      bw, s = create_bit_writer(16)
      bw.write_bits(0xd4c3, 16)
      bw.flush(0)
      assert_equal("\xc3\xd4".b, s.string.b)
    end
    
    def test_flush_buffer_with_padding
      bw, s = create_bit_writer(16)
      bw.write_bits(0x00c3, 23)
      bw.flush(15)
      assert_equal("\xc3".b, s.string.b)
    end
    
    def test_flush_twice
      bw, s = create_bit_writer(16)
      bw.write_bits(0x00c3, 23)
      bw.flush(15)
      assert_equal("\xc3".b, s.string.b)
      assert_raises(ArgumentError) { bw.flush(8) }
    end
    
    def test_flush_with_invalid_padding
      bw, s = create_bit_writer(16)
      bw.write_bits(0x00c3, 23)
      assert_raises(ArgumentError) { bw.flush(14) }
    end
    
    def test_flush_with_big_padding
      bw, s = create_bit_writer(16)
      bw.write_bits(0x00c3, 23)
      assert_raises(ArgumentError) { bw.flush(23) }
    end
  end
  
  class Base32768Test < Test::Unit::TestCase
    def test_encode_buffer_without_padding
      s = StringIO.new
      Base32768.encode(StringIO.new("\x00".b * 15), s)
      assert_equal("\x4a".b * 16, s.string.b)
    end
    
    def test_encode_buffer_with_padding
      s = StringIO.new
      Base32768.encode(StringIO.new("\x00".b * 13), s)
      assert_equal("\x4a".b * 14 + "\x51\xff".b, s.string.b)
    end
    
    def test_encode_single_byte
      s = StringIO.new
      Base32768.encode(StringIO.new("\xff".b), s)
      assert_equal("\x94\x4b\x57\xff".b, s.string.b)
    end
    
    def test_decode_buffer_without_padding
      s = StringIO.new
      Base32768.decode(StringIO.new("\x4a".b * 16), s)
      assert_equal("\x00".b * 15, s.string.b)
    end
    
    def test_decode_buffer_with_padding
      s = StringIO.new
      Base32768.decode(StringIO.new("\x4a".b * 14 + "\x51\xff".b), s)
      assert_equal("\x00".b * 13, s.string.b)
    end
    
    def test_decode_buffer_with_invalid_sequence
      assert_raises(ArgumentError) do
        Base32768.decode(StringIO.new("\x49".b * 16), StringIO.new)
      end
    end
    
    def test_decode_buffer_with_data_after_padding
      assert_raises(ArgumentError) do
        Base32768.decode(StringIO.new("\x94\x4b\x57\xff\x4a\x4a".b),
          StringIO.new)
      end
    end
    
    def test_decode_buffer_with_invalid_padding
      assert_raises(ArgumentError) do
        Base32768.decode(StringIO.new("\x4a\x4a".b), StringIO.new)
      end
    end
    
    def test_decode_buffer_with_non_even_char_count
      assert_raises(ArgumentError) do
        Base32768.decode(StringIO.new("\x4a".b), StringIO.new)
      end
    end
  end
end
