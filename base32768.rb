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
    return if pad == 0 && @cnt == 0
    raise ArgumentError, "Bad padding" if pad >= @cnt || (@cnt - pad) % 8 != 0

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
  DM = 181
  BITS = 15
  NBASE = DM ** 2 - 2 ** BITS
  CBASE = 0x100 - DM

  def self.encode(input, output)
    reader = BitReader.new(input)
    loop do
      val, bits = reader.read_bits(BITS)
      output.write(encode_integer(val)) if bits > 0
      output.write(encode_integer(bits - BITS)) if bits > 0 && bits < BITS
      return if bits < BITS
    end
  end

  def self.decode(input, output)
    writer = BitWriter.new(output, BITS)
    loop do
      if s = input.read(2)
        val = decode_integer(s)

        if val >= 0
          writer.write_bits(val, BITS)
        else
          writer.flush(-val)
          raise ArgumentError, "Data remaining after padding" if input.read(1)
          return
        end
      else
        writer.flush(0)
        return
      end
    end
  end

  TAB = [      # skip:
    [0, 37],   #   first 37 chars
    [43, 1],   #   +
    [61, 1],   #   =
    [127, 34], #   DEL, and next 33 chars
    [173, 1]   #   soft hyphen
  ]

  # Encodes an integer in range (0..181)
  def self.encode_byte(val)
    TAB.each { |r| val += r[1] if val >= r[0] }
    val.chr
  end

  def self.decode_byte(val)
    val = val.ord
    TAB.reverse_each do |r|
      if val >= r[0] + r[1]
        val -= r[1]
      elsif val >= r[0]
        raise ArgumentError, "Invalid byte value: \\x%02x" % val
      end
    end
    val
  end

  # Encodes an integer between -14 and 32767. Negative values mean padding.
  def self.encode_integer(val)
    # NBASE is added to val such that 0x7fff is encoded as \xff\xff
    p, q = (val + NBASE).divmod(DM)
    # p will be in range (-1..180), and q in range (0..180); 182 symbols are
    # needed to encode them
    encode_byte(q + 1) + encode_byte(p + 1)
  end

  def self.decode_integer(val)
    q, p = val.bytes.map { |x| decode_byte(x) }
    raise ArgumentError, "Non-even char count" unless q && p

    result = (p - 1) * DM + (q - 1) - NBASE
    raise ArgumentError, "Invalid byte sequence: \\x%02x\\x%02x" % val.bytes \
      if result <= -BITS

    result
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
    def test_encode_byte
      assert_equal('%', Base32768.encode_byte(0))
      assert_equal('*', Base32768.encode_byte(5))
      assert_equal(',', Base32768.encode_byte(6))
      assert_equal('<', Base32768.encode_byte(22))
      assert_equal('>', Base32768.encode_byte(23))
      assert_equal('~', Base32768.encode_byte(87))
      assert_equal("\xa1".b, Base32768.encode_byte(88))
      assert_equal("\xac".b, Base32768.encode_byte(99))
      assert_equal("\xae".b, Base32768.encode_byte(100))
      assert_equal("\xff".b, Base32768.encode_byte(181))
    end

    def test_decode_byte
      assert_equal(0, Base32768.decode_byte('%'))
      assert_equal(5, Base32768.decode_byte('*'))
      assert_equal(6, Base32768.decode_byte(','))
      assert_equal(22, Base32768.decode_byte('<'))
      assert_equal(23, Base32768.decode_byte('>'))
      assert_equal(87, Base32768.decode_byte('~'))
      assert_equal(88, Base32768.decode_byte("\xa1".b))
      assert_equal(99, Base32768.decode_byte("\xac".b))
      assert_equal(100, Base32768.decode_byte("\xae".b))
      assert_equal(181, Base32768.decode_byte("\xff".b))
    end

    def test_decode_invalid_byte
      assert_raises(ArgumentError) { Base32768.decode_byte("\xad".b) }
      assert_raises(ArgumentError) { Base32768.decode_byte("\xa0".b) }
      assert_raises(ArgumentError) { Base32768.decode_byte("\x7f".b) }
      assert_raises(ArgumentError) { Base32768.decode_byte('=') }
      assert_raises(ArgumentError) { Base32768.decode_byte('+') }
      assert_raises(ArgumentError) { Base32768.decode_byte('$') }
    end

    def test_encode_integer
      assert_equal("\xff\xff".b, Base32768.encode_integer(0x7fff))
      assert_equal("&\xff".b, Base32768.encode_integer(0x7f4b)) # 0x7fff - 180
      assert_equal("\xf9%".b, Base32768.encode_integer(0))
      assert_equal("\xeb%".b, Base32768.encode_integer(-14))
    end

    def test_decode_integer
      assert_equal(0x7fff, Base32768.decode_integer("\xff\xff".b))
      assert_equal(0x7f4b, Base32768.decode_integer("&\xff".b))
      assert_equal(0, Base32768.decode_integer("\xf9%".b))
      assert_equal(-14, Base32768.decode_integer("\xeb%".b))
    end

    def test_decode_invalid_integer
      assert_raises(ArgumentError) { Base32768.decode_integer("\xea%".b) }
      assert_raises(ArgumentError) { Base32768.decode_integer("\xff".b) }
    end

    def test_encode_buffer_without_padding
      s = StringIO.new
      Base32768.encode(StringIO.new("\x00".b * 15), s)
      assert_equal("\xf9%".b * 8, s.string.b)
    end

    def test_encode_buffer_with_padding_1
      s = StringIO.new
      Base32768.encode(StringIO.new("\x00".b * 13), s)
      assert_equal("\xf9%".b * 7 + "\xf8%".b, s.string.b)
    end

    def test_encode_buffer_with_padding_14
      s = StringIO.new
      Base32768.encode(StringIO.new("\xff\xff".b), s)
      assert_equal("\xff\xff\xfa%\xeb%".b, s.string.b)
    end

    def test_encode_single_byte
      s = StringIO.new
      Base32768.encode(StringIO.new("\xff".b), s)
      assert_equal("k'\xf2%".b, s.string.b)
    end

    def test_encode_empty_string
      s = StringIO.new
      Base32768.encode(StringIO.new("".b), s)
      assert_equal("".b, s.string.b)
    end

    def test_decode_buffer_without_padding
      s = StringIO.new
      Base32768.decode(StringIO.new("\xf9%".b * 8), s)
      assert_equal("\x00".b * 15, s.string.b)
    end

    def test_decode_buffer_with_padding_1
      s = StringIO.new
      Base32768.decode(StringIO.new("\xf9%".b * 7 + "\xf8%".b), s)
      assert_equal("\x00".b * 13, s.string.b)
    end

    def test_decode_buffer_with_padding_14
      s = StringIO.new
      Base32768.decode(StringIO.new("\xff\xff\xfa%\xeb%".b), s)
      assert_equal("\xff\xff".b, s.string.b)
    end

    def test_decode_buffer_with_data_after_padding
      assert_raises(ArgumentError) do
        Base32768.decode(StringIO.new("k'\xf2%".b * 2), StringIO.new)
      end
    end

    def test_decode_empty_string
      s = StringIO.new
      Base32768.decode(StringIO.new("".b), s)
      assert_equal("".b, s.string.b)
    end
  end
end
