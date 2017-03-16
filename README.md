# Base32768

This is a binary-to-text encoder which converts every 15 bits of input to a pair
of printable characters in range `U+0025`..`U+00ff`. In other words, it
generates 16 bytes of ISO8859-1-encoded bytes for every 15 bytes of binary data.

It was invented as a way to transmit binary files through serial devices using a
delimiter-based, human-readable protocol. The output of Base32768 is free of
whitespace (space, no-break space, soft hyphen etc.) and control characters. A
few punctuation characters like `+` and `=` are also left out to be used as
delimiters.

## Main features

* High-efficiency: adds only 6.7% of overhead on average

* Small code and memory requirements (no lookup tables are needed)

* Uses only printable characters encodeable with ISO8859-1, meaning it's
  friendly for debugging and even text editors.

## Usage

```
require 'base32768'

i = StringIO.new("\x17\x65\x23\x1c\x8c\xdc\xaa\xd9\xe5\xbd\x23\x91\xd7\x00\xa3")
o = StringIO.new
Base32768.encode(i, o)

File.open('out.txt', 'w+') { |f| f.write(o.string) }
=> 16
o.string.force_encoding('iso8859-1').encode('utf-8')
=> "õÙ¯w|ìf¸uÐ«[ItR¾"
```

## Contributing

This project is intended to be a set of reference implementations for the
encoder, with a single file per language.

To contribute:

* Fork the project

* Checkout a new branch

* Make a pull request

If you want to implement the encoder in a different language follow these rules:

* Use a single file

* Write some test-cases

* Make the program callable from the command line:

  * With `-e` it _encodes_ the standard input to standard output

  * With `-d` it _decodes_ the standard input to standard output

  * Otherwise it runs the test-cases

## License

MIT. See `LICENSE`.
