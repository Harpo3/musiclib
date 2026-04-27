# Ogg Vorbis I Format Specification: Comment Field and Header

> **Source:** [https://xiph.org/vorbis/doc/v-comment.html](https://xiph.org/vorbis/doc/v-comment.html)  
> **Copyright:** © 1994–2005 Xiph.Org. All rights reserved.

---

## Overview

The Vorbis text comment header is the second (of three) header packets that begin a Vorbis bitstream. It is meant for short, text comments, not arbitrary metadata; arbitrary metadata belongs in a separate logical bitstream (usually an XML stream type) that provides greater structure and machine parseability.

The comment field is meant to be used much like someone jotting a quick note on the bottom of a CDR. It should be a little information to remember the disc by and explain it to others; a short, to-the-point text note that need not only be a couple words, but isn't going to be more than a short paragraph. The essentials, in other words, whatever they turn out to be, e.g.:

> "Honest Bob and the Factory-to-Dealer-Incentives, *I'm Still Around*, opening for Moxy Früvous, 1997"

---

## Comment Encoding

### Structure

The comment header logically is a list of eight-bit-clean vectors; the number of vectors is bounded to 2^32-1 and the length of each vector is limited to 2^32-1 bytes. The vector length is encoded; the vector contents themselves are not null terminated. In addition to the vector list, there is a single vector for vendor name (also 8 bit clean, length encoded in 32 bits). For example, the 1.0 release of libvorbis set the vendor string to `"Xiph.Org libVorbis I 20020717"`.

The comment header is decoded as follows:

```
1) [vendor_length] = read an unsigned integer of 32 bits
2) [vendor_string] = read a UTF-8 vector as [vendor_length] octets
3) [user_comment_list_length] = read an unsigned integer of 32 bits
4) iterate [user_comment_list_length] times {

     5) [length] = read an unsigned integer of 32 bits
     6) this iteration's user comment = read a UTF-8 vector as [length] octets

   }

7) [framing_bit] = read a single bit as boolean
8) if ( [framing_bit] unset or end of packet ) then ERROR
9) done.
```

### Content Vector Format

The comment vectors are structured similarly to a UNIX environment variable. That is, comment fields consist of a field name and a corresponding value and look like:

```
comment[0]="ARTIST=me";
comment[1]="TITLE=the sound of Vorbis";
```

- A **case-insensitive field name** that may consist of ASCII 0x20 through 0x7D, 0x3D (`=`) excluded. ASCII 0x41 through 0x5A inclusive (A–Z) is to be considered equivalent to ASCII 0x61 through 0x7A inclusive (a–z).
- The field name is immediately followed by ASCII 0x3D (`=`); this equals sign is used to terminate the field name.
- 0x3D is followed by the 8 bit clean UTF-8 encoded value of the field contents to the end of the field.

---

## Standard Field Names

Below is a proposed, minimal list of standard field names with a description of intended use. No single or group of field names is mandatory; a comment header may contain one, all, or none of the names in this list.

| Field Name | Description |
|------------|-------------|
| `TITLE` | Track/Work name |
| `VERSION` | Differentiates multiple versions of the same track title in a single collection (e.g., remix info) |
| `ALBUM` | The collection name to which this track belongs |
| `TRACKNUMBER` | The track number of this piece if part of a specific larger collection or album |
| `ARTIST` | The artist generally considered responsible for the work. In popular music, usually the performing band or singer. For classical music, the composer. For an audio book, the author of the original text. |
| `PERFORMER` | The artist(s) who performed the work. In classical music, the conductor, orchestra, soloists. In an audio book, the actor who did the reading. In popular music, typically the same as ARTIST and is omitted. |
| `COPYRIGHT` | Copyright attribution, e.g., `2001 Nobody's Band` or `1999 Jack Moffitt` |
| `LICENSE` | License information, e.g., `All Rights Reserved`, `Any Use Permitted`, or a URL to a license such as a Creative Commons license |
| `ORGANIZATION` | Name of the organization producing the track (i.e., the record label) |
| `DESCRIPTION` | A short text description of the contents |
| `GENRE` | A short text indication of music genre |
| `DATE` | Date the track was recorded |
| `LOCATION` | Location where track was recorded |
| `CONTACT` | Contact information for the creators or distributors of the track (URL, email, or physical address) |
| `ISRC` | ISRC number for the track |

---

## Implications

- **Field names should not be internationalized**; this is a concession to simplicity, not an attempt to exclude non-English speakers. Field *contents*, however, use UTF-8 character encoding to allow easy representation of any language.
- The length of the entirety of the field and restrictions on the field name ensure that the field name is bounded in a known way.
- Individual vendors may use non-standard field names within reason. Abuse will be discouraged.
- There is no vendor-specific prefix to non-standard field names. Vendors should make some effort to avoid arbitrarily polluting the common namespace.
- **Field names are not required to be unique** (occur once) within a comment header. For example, a track recorded by three artists may use:

  ```
  ARTIST=Dizzy Gillespie
  ARTIST=Sonny Rollins
  ARTIST=Sonny Stitt
  ```

---

## Encoding

The comment header comprises the entirety of the second bitstream header packet. Unlike the first bitstream header packet, it is not generally the only packet on the second page and may not be restricted to within the second bitstream page. The length of the comment header packet is (practically) unbounded. The comment header packet is **not optional**; it must be present in the bitstream even if it is effectively empty.

The comment header is encoded as follows (per Ogg's standard bitstream mapping, which renders the least-significant-bit of the word into the least significant available bit of the current bitstream octet first):

1. Vendor string length (32-bit unsigned quantity specifying number of octets)
2. Vendor string (`[vendor string length]` octets coded from beginning of string to end of string, not null terminated)
3. Number of comment fields (32-bit unsigned quantity specifying number of fields)
4. Comment field 0 length (if `[Number of comment fields]` > 0; 32-bit unsigned quantity specifying number of octets)
5. Comment field 0 (`[Comment field 0 length]` octets coded from beginning of string to end of string, not null terminated)
6. Comment field 1 length (if `[Number of comment fields]` > 1…) …

This is actually somewhat easier to describe in code; implementation of the above can be found in `vorbis/lib/info.c:_vorbis_pack_comment()`, `_vorbis_unpack_comment()`.

---

*The Xiph Fish Logo is a trademark (™) of Xiph.Org.*  
*These pages © 1994–2005 Xiph.Org. All rights reserved.*
