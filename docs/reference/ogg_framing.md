# Ogg Logical Bitstream Framing

## Purpose

The Ogg transport bitstream provides framing, error protection, and seeking structure for higher-level codec streams that consist of raw, unencapsulated data packets — such as Vorbis audio or Theora video.

Vorbis encodes short-time PCM blocks into raw packets of bit-packed data. For stream-based storage (files) and transport (TCP, pipes), Ogg provides:

- Framing and sync
- Sync recapture after error
- Landmarks for seeking
- Exact packet boundary recovery without decoding

---

## Logical vs. Physical Bitstream

A **logical** Ogg bitstream is a contiguous sequence of pages belonging only to that stream. A **physical** Ogg bitstream is constructed from one or more logical bitstreams. The simplest physical bitstream is a single logical bitstream. Combining logical bitstreams into complex physical bitstreams is handled at a higher layer.

---

## Page Structure

An Ogg stream is structured by dividing incoming packets into **segments of up to 255 bytes**, then wrapping a group of contiguous segments into a **variable-length page** preceded by a page header. Both the header size and page size are variable. The page header contains sizing information and a checksum to determine header/page size and data integrity.

Stream capture (or recapture) works by:

1. Searching for the capture pattern (`OggS`)
2. Verifying page sync and integrity via checksum
3. Extracting packets from the verified page

---

## Packet Segmentation and Lacing

Packets are logically divided into segments before encoding into a page. The segmentation process is **logical only** — the original data need not be rearranged. Segmentation computes page header values; the packet body remains intact.

### Lacing Value Encoding

A raw packet is divided into segments of 255 bytes, with a final fractional segment of < 255 bytes.

| Scenario | Lacing Values |
|---|---|
| 753-byte packet | `255, 255, 243` |
| 255-byte packet | `255, 0` |
| Zero-length (nil) packet | `0` |

- A lacing value of **255** means another segment follows
- A lacing value of **< 255** marks the end of the packet
- A packet whose size is an exact multiple of 255 is terminated with a trailing `0` lacing value

### Overhead Characteristics

| Packet Size | Overhead |
|---|---|
| < 255 bytes (typical) | 1 byte (minimum possible) |
| > 512 bytes | ~0.5% |

Small packets (50–200 bytes, the dominant case) see the minimum byte-aligned overhead of 1 byte. Large packets see a fairly constant ~0.5% overhead.

---

## Spanning Page Boundaries

Packets are not restricted to beginning and ending within a single page. When a packet spans a page boundary:

1. Lacing values for segments placed on the current page go into the current segment table; the page is finished.
2. The next page begins with the remaining segment lacing values.
3. The header flag `0x01` is set on the new page to indicate a **continued packet**.

This flag allows a decoder to determine packet continuity by inspecting only the current page header — no look-back at the prior page is required. It also speeds error recovery if the preceding page is corrupt.

A packet can span an arbitrary number of pages. The nil termination case (`0` lacing value for a packet whose size is an exact multiple of 255) must appear even if it falls on the next page.

---

## Page Header Format

| Byte(s) | Field | Value / Notes |
|---|---|---|
| 0–3 | Capture pattern | `0x4f 0x67 0x67 0x53` (`OggS`) |
| 4 | Stream structure revision | `0x00` |
| 5 | Header type flags | See flags table below |
| 6–13 | Granule position | 64-bit signed, codec-defined sample/frame position |
| 14–17 | Bitstream serial number | 32-bit, unique per logical stream within a physical stream |
| 18–21 | Page sequence number | 32-bit counter; detects lost pages |
| 22–25 | CRC checksum | 32-bit CRC (poly `0x04c11db7`); computed over full header+page with CRC field zeroed |
| 26 | Page segments count | 0–255 |
| 27–(26+n) | Segment table (lacing values) | One byte per segment; n = page_segments count |

### Header Type Flags (Byte 5)

| Bit | Value | Meaning |
|---|---|---|
| 0 | `0x01` | **Continued packet** — first lacing value continues a packet from the prior page |
| 1 | `0x02` | **Beginning of stream (bos)** — first page of the logical bitstream |
| 2 | `0x04` | **End of stream (eos)** — last page of the logical bitstream |

Flags are packed LSb of LSB first. All three bits are independent and may be combined.

---

## Granule Position Semantics

The granule position (bytes 6–13) is the total number of samples (or frames) encoded **after including all packets that finish on this page**. Packets that begin on a page but continue to the next page are **not** counted.

- A special value of `-1` (all bits set, two's complement) indicates that **no packets finish on this page**
- The codec defines the exact semantic meaning of the granule value (e.g., PCM sample count, video frame number)
- A truncated stream still returns the correct number of fully decodable samples from the last complete page

---

## Page Size and Overhead

- Maximum segments per page: **255**
- Maximum segment size: **255 bytes**
- Maximum physical page size: **65,307 bytes** (~64 KB)
- A corrupted size field is bounded by this maximum, preventing runaway reads; the CRC mismatch then triggers re-sync

Overhead summary for nominal ~8 KB pages at 44.1 kHz / 128 kbps stereo:

| Overhead Source | Approximate Cost |
|---|---|
| Page header (flat) | 0.25–0.5% |
| Segment table (lacing) | 0.5–1.0% |
| Combined nominal overhead | ~0.75–1.5% |

---

## CRC Algorithm

The 32-bit CRC uses the following parameters:

- **Polynomial**: `0x04c11db7`
- **Initial value**: `0x00000000`
- **Final XOR**: `0x00000000`
- **Input**: Entire page header (CRC field set to zero) concatenated with the page body

---

## Design Rationale

The segmentation and header generation process is designed to avoid copying or reassembling packet data. The encoder buffers packet data until a complete page is formed, then writes the header (derived directly from the buffered lacing values) followed by the buffered segments. This keeps encoding logic simple and avoids memory reallocation.

Explicit per-segment tracking enables advanced encoder tricks without requiring knowledge of packet size — for example, simple bandwidth limiting by truncating the least-sensitive portion of a packet, which is placed last by convention.
