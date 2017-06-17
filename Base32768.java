import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.IOException;
import java.io.OutputStream;

import org.junit.Before;
import org.junit.runner.JUnitCore;
import org.junit.runner.Result;
import org.junit.runner.notification.Failure;
import org.junit.Test;

import static org.junit.Assert.*;

public class Base32768 {
  public static class Bits {
    private final int value;
    private final int count;

    public Bits(int value, int count) {
      this.value = value;
      this.count = count;
    }

    public int getValue() {
      return value;
    }

    public int getCount() {
      return count;
    }
  }

  public static class BitReader {
    private final InputStream is;
    private int value = 0;
    private int count = 0;

    public BitReader(InputStream is) {
      this.is = is;
    }

    public Bits readBits(int n) throws IOException {
      int result = 0;
      int p = 0;

      while (n > 0) {
        if (count == 0) {
          int v = is.read();
          if (v == -1)
            break;
          value = v;
          count = 8;
        }

        int c = n > count ? count : n;
        int m = (1 << c) - 1;
        result = result | (value & m) << p;
        p += c;
        n -= c;
        value = value >> c;
        count -= c;
      }

      return new Bits(result, p);
    }
  }

  public static class BitWriter {
    private final OutputStream os;
    private final int bufferSize;
    private long value = 0;
    private int count = 0;

    public BitWriter(OutputStream os, int bufferSize) {
      this.os = os;
      this.bufferSize = bufferSize >= 0 ? bufferSize : 0;
    }

    public void flush(int pad) throws IOException {
      if (pad >= count || (count - pad) % 8 != 0)
        throw new IllegalStateException("Bad padding");
      count -= pad;
      flushBuffer(0);
      value = 0;
      count = 0;
    }

    public void writeBits(int value, int n) throws IOException {
      if (bufferSize + n + 8 > 64)
        throw new IllegalArgumentException("Bit buffer would overflow");

      this.value = this.value | ((long) value << count);
      count += n;
      flushBuffer(bufferSize);
    }

    private void flushBuffer(int n) throws IOException {
      while (count >= n + 8) {
        os.write((byte) this.value);
        this.value = this.value >> 8;
        count -= 8;
      }
    }
  }

  public static class InvalidInputException extends Exception {
    public InvalidInputException(String message) {
      super(message);
    }
  }

  private static final int DM = 181;
  private static final int BITS = 15;
  private static final int NBASE = DM * DM - (1 << BITS);

  private static final int[] TAB = new int[] {
    0, 37,
    43, 1,
    61, 1,
    127, 34,
    173, 1
  };

  private static int encodeByte(int value) {
    for (int i = 0; i < TAB.length; i += 2) {
      if (value >= TAB[i])
        value += TAB[i + 1];
    }
    return value;
  }

  private static int decodeByte(int value) {
    int result = value;
    for (int i = TAB.length; i > 0; i -= 2) {
      if (result >= TAB[i - 2] + TAB[i - 1])
        result -= TAB[i - 1];
      else if (result >= TAB[i - 2])
        throw new IllegalArgumentException(
          String.format("Invalid byte value 0x%02x", value));
    }
    return result;
  }

  private static int encodeInteger(int value) {
    value += NBASE;
    int rem = value % DM;
    int mod = (rem + DM) % DM;
    int div = (value - mod + rem) / DM;
    return encodeByte(mod + 1) + (encodeByte(div + 1) << 8);
  }

  private static int decodeInteger(int value) {
    int p = decodeByte(value >> 8);
    int q = decodeByte(value & 0xff);

    int result = (p - 1) * DM + (q - 1) - NBASE;

    if (result <= -BITS)
      throw new IllegalArgumentException(String.format(
        "Invalid byte sequence: 0x%02x 0x%02x", value & 0xff, value >> 8));

    return result;
  }

  private static void encode(InputStream is, OutputStream os) throws IOException {
    BitReader br = new BitReader(is);
    while (true) {
      Bits bits = br.readBits(BITS);
      int cnt = bits.getCount();

      if (cnt > 0) {
        int value = encodeInteger(bits.getValue());
        os.write((byte) (value & 0xff));
        os.write((byte) (value >> 8));
      }
      if (cnt > 0 && cnt < BITS) {
        int value = encodeInteger(cnt - BITS);
        os.write((byte) (value & 0xff));
        os.write((byte) (value >> 8));
      }
      if (cnt < BITS)
        return;
    }
  }

  private static void decode(InputStream is, OutputStream os)
      throws IOException, InvalidInputException {
    BitWriter bw = new BitWriter(os, BITS);
    while (true) {
      int b1 = is.read();
      int b2 = is.read();

      try {
        if (b1 != -1 && b2 != -1) {
          int value = decodeInteger(b1 + (b2 << 8));

          if (value >= 0) {
            bw.writeBits(value, BITS);
          } else {
            bw.flush(-value);
            if (is.read() != -1)
              throw new InvalidInputException("Data remaining after padding");
            return;
          }
        } else if (b1 != -1 || b2 != -1) {
          throw new InvalidInputException("Non-even char count");
        } else {
          bw.flush(0);
          return;
        }
      } catch (IllegalStateException e) {
        throw new InvalidInputException(e.getMessage());
      }
    }
  }

  public static class BitReaderTest {
    private BitReader createBitReader(byte[] bytes) {
      return new BitReader(new ByteArrayInputStream(bytes));
    }

    @Test
    public void readWholeByte() throws Exception {
      BitReader br = createBitReader(new byte[] { -61 });
      Bits bits = br.readBits(8);
      assertEquals(0xc3, bits.getValue());
      assertEquals(8, bits.getCount());
    }

    @Test
    public void readPartialByte() throws Exception {
      BitReader br = createBitReader(new byte[] { -61 });
      Bits bits = br.readBits(4);
      assertEquals(0x03, bits.getValue());
      assertEquals(4, bits.getCount());
    }

    @Test
    public void readPartialByteContinuation() throws Exception {
      BitReader br = createBitReader(new byte[] { -61 });
      br.readBits(4);
      Bits bits = br.readBits(4);
      assertEquals(0x0c, bits.getValue());
      assertEquals(4, bits.getCount());
    }

    @Test
    public void readMultiByte() throws Exception {
      BitReader br = createBitReader(new byte[] { -61, -44 });
      Bits bits = br.readBits(12);
      assertEquals(0x4c3, bits.getValue());
      assertEquals(12, bits.getCount());
    }

    @Test
    public void readByteAtEof() throws Exception {
      BitReader br = createBitReader(new byte[] { -61 });
      br.readBits(4);
      Bits bits = br.readBits(8);
      assertEquals(0x0c, bits.getValue());
      assertEquals(4, bits.getCount());
    }

    @Test
    public void readBytePastEof() throws Exception {
      BitReader br = createBitReader(new byte[] { -61 });
      br.readBits(8);
      Bits bits = br.readBits(8);
      assertEquals(0, bits.getValue());
      assertEquals(0, bits.getCount());
    }
  }

  public static class BitWriterTest {
    private ByteArrayOutputStream bos;

    @Before
    public void setup() {
      bos = new ByteArrayOutputStream();
    }

    @Test
    public void writeWholeByte() throws Exception {
      BitWriter bw = new BitWriter(bos, 0);
      bw.writeBits(0xc3, 8);
      assertArrayEquals(new byte[] { -61 }, bos.toByteArray());
    }

    @Test
    public void writePartialByte() throws Exception {
      BitWriter bw = new BitWriter(bos, 0);
      bw.writeBits(0x03, 4);
      bw.writeBits(0x0c, 4);
      assertArrayEquals(new byte[] { -61 }, bos.toByteArray());
    }

    @Test
    public void writeSecondByte() throws Exception {
      BitWriter bw = new BitWriter(bos, 0);
      bw.writeBits(0xc3, 8);
      bw.writeBits(0xd4, 8);
      assertArrayEquals(new byte[] { -61, -44 }, bos.toByteArray());
    }

    @Test
    public void writeByteContinuation() throws Exception {
      BitWriter bw = new BitWriter(bos, 0);
      bw.writeBits(0x03, 4);
      bw.writeBits(0x4c, 8);
      bw.writeBits(0x0d, 4);
      assertArrayEquals(new byte[] { -61, -44 }, bos.toByteArray());
    }

    @Test
    public void writeMultiByte() throws Exception {
      BitWriter bw = new BitWriter(bos, 0);
      bw.writeBits(0xd4c3, 16);
      assertArrayEquals(new byte[] { -61, -44 }, bos.toByteArray());
    }

    @Test
    public void bufferBits() throws Exception {
      BitWriter bw = new BitWriter(bos, 16);
      bw.writeBits(0x00c3, 23);
      assertArrayEquals(new byte[] {}, bos.toByteArray());
      bw.writeBits(0, 1);
      assertArrayEquals(new byte[] { -61 }, bos.toByteArray());
    }

    @Test
    public void flushBuffer() throws Exception {
      BitWriter bw = new BitWriter(bos, 16);
      bw.writeBits(0xd4c3, 16);
      bw.flush(0);
      assertArrayEquals(new byte[] { -61, -44 }, bos.toByteArray());
    }

    @Test
    public void flushBufferWithPadding() throws Exception {
      BitWriter bw = new BitWriter(bos, 16);
      bw.writeBits(0x00c3, 23);
      bw.flush(15);
      assertArrayEquals(new byte[] { -61 }, bos.toByteArray());
    }

    @Test(expected=IllegalStateException.class)
    public void flushTwice() throws Exception {
      BitWriter bw = new BitWriter(bos, 16);
      bw.writeBits(0x00c3, 23);
      bw.flush(15);
      bw.flush(14);
    }

    @Test(expected=IllegalStateException.class)
    public void flushWithInvalidPadding() throws Exception {
      BitWriter bw = new BitWriter(bos, 16);
      bw.writeBits(0x00c3, 23);
      bw.flush(14);
    }

    @Test(expected=IllegalStateException.class)
    public void flushWithBigPadding() throws Exception {
      BitWriter bw = new BitWriter(bos, 16);
      bw.writeBits(0x00c3, 23);
      bw.flush(23);
    }

    @Test
    public void writeLongBuffer() throws Exception {
      BitWriter bw = new BitWriter(bos, 28);
      // write 63 bits of alternating 0s and 1s
      bw.writeBits(0x2a, 7);
      bw.writeBits(0x5555555, 28); // buffer holds 35 bits
      bw.writeBits(0x5555555, 28); // holds 31 bits after partial flush
      bw.writeBits(0, 1);
      bw.flush(0);
      // result should be: aa aa aa aa aa aa aa 2a
      assertArrayEquals(new byte[] { -86, -86, -86, -86, -86, -86, -86, 42 },
        bos.toByteArray());
    }

    @Test(expected=IllegalArgumentException.class)
    public void writeBeyondBufferCapacity() throws Exception {
      BitWriter bw = new BitWriter(bos, 29);
      bw.writeBits(0x5555555, 28);
    }
  }

  public static class EncoderTest {
    @Test
    public void testEncodeByte() throws Exception {
      assertEquals(37, encodeByte(0));
      assertEquals(42, encodeByte(5));
      assertEquals(44, encodeByte(6));
      assertEquals(60, encodeByte(22));
      assertEquals(62, encodeByte(23));
      assertEquals(126, encodeByte(87));
      assertEquals(161, encodeByte(88));
      assertEquals(172, encodeByte(99));
      assertEquals(174, encodeByte(100));
      assertEquals(255, encodeByte(181));
    }

    @Test
    public void testEncodeInteger() throws Exception {
      assertEquals(0xffff, encodeInteger(0x7fff));
      assertEquals(0xff26, encodeInteger(0x7f4b));
      assertEquals(0x25f9, encodeInteger(0));
      assertEquals(0x25eb, encodeInteger(-14));
    }

    @Test
    public void encodeWithoutPadding() throws Exception {
      ByteArrayInputStream i = new ByteArrayInputStream(
        new byte[] { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
      ByteArrayOutputStream o = new ByteArrayOutputStream();

      encode(i, o);

      assertArrayEquals(new byte[] { -7, 37, -7, 37, -7, 37, -7, 37, -7, 37,
        -7, 37, -7, 37, -7, 37 }, o.toByteArray());
    }

    @Test
    public void encodeWithPadding1() throws Exception {
      ByteArrayInputStream i = new ByteArrayInputStream(
        new byte[] { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
      ByteArrayOutputStream o = new ByteArrayOutputStream();

      encode(i, o);

      assertArrayEquals(new byte[] { -7, 37, -7, 37, -7, 37, -7, 37, -7, 37,
        -7, 37, -7, 37, -8, 37 }, o.toByteArray());
    }

    @Test
    public void encodeWithPadding14() throws Exception {
      ByteArrayInputStream i = new ByteArrayInputStream(new byte[] { -1, -1 });
      ByteArrayOutputStream o = new ByteArrayOutputStream();

      encode(i, o);

      assertArrayEquals(new byte[] { -1, -1, -6, 37, -21, 37 }, o.toByteArray());
    }

    @Test
    public void encodeSingleByte() throws Exception {
      ByteArrayInputStream i = new ByteArrayInputStream(new byte[] { -1 });
      ByteArrayOutputStream o = new ByteArrayOutputStream();

      encode(i, o);

      assertArrayEquals(new byte[] { 107, 39, -14, 37 }, o.toByteArray());
    }
  }

  public static class DecoderTest {
    @Test
    public void testDecodeByte() throws Exception {
      assertEquals(0, decodeByte(37));
      assertEquals(5, decodeByte(42));
      assertEquals(6, decodeByte(44));
      assertEquals(22, decodeByte(60));
      assertEquals(23, decodeByte(62));
      assertEquals(87, decodeByte(126));
      assertEquals(88, decodeByte(161));
      assertEquals(99, decodeByte(172));
      assertEquals(100, decodeByte(174));
      assertEquals(181, decodeByte(255));
    }

    @Test(expected=IllegalArgumentException.class)
    public void decodeInvalidByte36() throws Exception {
      decodeByte(36);
    }

    @Test(expected=IllegalArgumentException.class)
    public void decodeInvalidByte43() throws Exception {
      decodeByte(43);
    }

    @Test(expected=IllegalArgumentException.class)
    public void decodeInvalidByte61() throws Exception {
      decodeByte(61);
    }

    @Test(expected=IllegalArgumentException.class)
    public void decodeInvalidByte127() throws Exception {
      decodeByte(127);
    }

    @Test(expected=IllegalArgumentException.class)
    public void decodeInvalidByte160() throws Exception {
      decodeByte(160);
    }

    @Test(expected=IllegalArgumentException.class)
    public void decodeInvalidByte173() throws Exception {
      decodeByte(173);
    }

    @Test
    public void testDecodeInteger() throws Exception {
      assertEquals(0x7fff, decodeInteger(0xffff));
      assertEquals(0x7f4b, decodeInteger(0xff26));
      assertEquals(0, decodeInteger(0x25f9));
      assertEquals(-14, decodeInteger(0x25eb));
    }

    @Test(expected=IllegalArgumentException.class)
    public void decodeInvalidInteger() throws Exception {
      decodeInteger(0x25ea);
    }

    @Test
    public void decodeWithoutPadding() throws Exception {
      ByteArrayInputStream i = new ByteArrayInputStream(new byte[] { -7, 37,
          -7, 37, -7, 37, -7, 37, -7, 37, -7, 37, -7, 37, -7, 37 });
      ByteArrayOutputStream o = new ByteArrayOutputStream();

      decode(i, o);

      assertArrayEquals(new byte[] { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0 }, o.toByteArray());
    }

    @Test
    public void decodeWithPadding1() throws Exception {
      ByteArrayInputStream i = new ByteArrayInputStream(new byte[] { -7, 37,
          -7, 37, -7, 37, -7, 37, -7, 37, -7, 37, -7, 37, -8, 37 });
      ByteArrayOutputStream o = new ByteArrayOutputStream();

      decode(i, o);

      assertArrayEquals(new byte[] { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        o.toByteArray());
    }

    @Test
    public void decodeWithPadding14() throws Exception {
      ByteArrayInputStream i = new ByteArrayInputStream(
        new byte[] { -1, -1, -6, 37, -21, 37 });
      ByteArrayOutputStream o = new ByteArrayOutputStream();

      decode(i, o);

      assertArrayEquals(new byte[] { -1, -1 }, o.toByteArray());
    }

    @Test(expected=InvalidInputException.class)
    public void decodeWithInvalidPadding() throws Exception {
      ByteArrayInputStream i = new ByteArrayInputStream(
        new byte[] { -1, -1, -6, 37, -8, 37 });
      ByteArrayOutputStream o = new ByteArrayOutputStream();

      decode(i, o);
    }

    @Test(expected=InvalidInputException.class)
    public void decodeWithDataAfterPadding() throws Exception {
      ByteArrayInputStream i = new ByteArrayInputStream(
        new byte[] { 107, 39, -14, 37, 107, 39, -14, 37 });
      ByteArrayOutputStream o = new ByteArrayOutputStream();

      decode(i, o);
    }

    @Test(expected=InvalidInputException.class)
    public void decodeWithNonEvenCharCount() throws Exception {
      ByteArrayInputStream i = new ByteArrayInputStream(new byte[] { -7, 37,
        -7, 37, -7, 37, -7, 37, -7, 37, -7, 37, -7, 37, -7, 37, -1 });
      ByteArrayOutputStream o = new ByteArrayOutputStream();

      decode(i, o);
    }
  }

  public static void main(String[] args) {
    try {
      if (args.length >= 2 && args[1].equals("-e")) {
        Base32768.encode(System.in, System.out);
        System.out.flush();
        return;
      }
      if (args.length >= 2 && args[1].equals("-d")) {
        Base32768.decode(System.in, System.out);
        System.out.flush();
        return;
      }
    } catch (IOException e) {
      System.err.println("IO error: " + e.getMessage());
      System.exit(1);
    } catch (InvalidInputException e) {
      System.err.println("Invalid input: " + e.getMessage());
      System.exit(1);
    }

    Result result = JUnitCore.runClasses(BitReaderTest.class,
      BitWriterTest.class, EncoderTest.class, DecoderTest.class);
    for (Failure failure : result.getFailures()) {
      System.out.println(failure.toString());
    }
  }
}
