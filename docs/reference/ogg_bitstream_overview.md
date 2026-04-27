# Ogg Bitstream

## Purpose

Ogg is a simplest-possible container format concerned only with framing, ordering, and interleave. It can be used as a stream delivery mechanism, for media file storage, or as a building block for a more complex, non-linear container.

---

## Design Philosophy

Ogg is not a monolithic kitchen-sink container. It exists only to frame and deliver in-order stream data. The entire structure is built from a single building block — the **Ogg page** — with no optional fields or alternate encodings.

Stream and media metadata is stored *by* the Ogg container rather than being built *into* it. This compartmentalization isolates the container from metadata design flux and allows any metadata specification to be used without altering the container itself.

---

## Page Structure

Every Ogg page is identical in structure and consists of:

- **Page header** — eight fields totalling 28 bytes
- **Packet length list** — up to 255 bytes
- **Payload data** — up to 65,025 bytes (maximum page size just under 64 KB)

There are no optional fields or context-dependent encodings. Ogg is fully byte-aligned and requires no repacking of codec data.

---

## Efficiency

| Packet Size | Approximate Overhead |
|---|---|
| 50 bytes | ~2% |
| Medium | ~1% (maximum working) |
| Typical use | ~0.5–0.7% |

Ogg is designed to contain any size data payload with bounded, predictable efficiency. Packets have no maximum size and a zero-byte minimum size.

---

## Bitstream Hierarchy

### Packets

Codecs place raw compressed data into **packets** — octet payloads representing one decompressed unit (e.g., one audio frame). Packets have no internal framing landmarks.

### Logical Bitstream

Packets grouped and framed into Ogg pages with a unique stream **serial number** form a **logical bitstream**.

### Physical Bitstream (Elementary Stream)

A **physical bitstream** containing only a single logical bitstream is called an **elementary stream**. Each page is self-contained, although a packet may be split across one or more pages.

### Multiplexed Bitstream

Multiple elementary streams can be combined into a **multiplexed bitstream** by interleaving whole pages from each stream in time order. Each logical stream is identified by its unique serial number.

### Chained Bitstream

Multiple physical bitstreams may be concatenated into a single **chained** stream. Streams do not overlap — the final page of one logical bitstream is immediately followed by the initial page of the next. Each logical bitstream in a chain must have a unique serial number within the scope of the full physical bitstream.

---

## Stream Types

Ogg streams belong to one of two categories:

| Type | Description | Buffering Behavior | Timestamp |
|---|---|---|---|
| **Continuous** | Gapless, time-continuous media (e.g., audio, video) | Buffered ahead to prevent starvation | Stamped by **end time** |
| **Discontinuous** | Irregular or widely-spaced data (e.g., captions) | Taken as-it-comes; not buffered ahead | Stamped by **begin time** |

Buffering requirements do not need to be explicitly declared in the stream. The decoder reads only as much data as needed to keep all continuous streams gapless; discontinuous data is processed as it arrives.

---

## Granule Position (Timestamps)

Every Ogg page is stamped with a 64-bit **granule position** that serves as an absolute timestamp for muxing and seeking. The granule position is mapped to an absolute time value by the **codec**, not the container. This allows:

- Maximally efficient use of 64 bits to address every sample without approximation
- Support for new and previously unknown timebase encodings without updating the mux layer
- Novel uses such as "rolling INTRA" (keyframeless video)

Pages in a multiplexed stream are interleaved in order of their timestamp regardless of stream type.

---

## Seeking

Ogg implements both coarse and fine-grained seeking without requiring an index:

- **Coarse seeking** — Move to a new position in the stream; rapid capture and timecode acquisition are guaranteed from any point.
- **Fine seeking** — Full sample-granularity seeking via interpolated bisection search built on the same capture and timecode mechanisms.

All Ogg streams are fully seekable from creation. Seekability is unaffected by truncation or missing data and is tolerant of gross corruption. Seek operations are neither fuzzy nor heuristic.

The optional **OggSkeleton** format now defines a proposed index for implementations that require one.

---

## Multiplexing Rules

When constructing a single-link (unchained) physical bitstream from multiple elementary streams:

1. The **initial header** for each stream appears in sequence, one header per page, with no intervening data.
2. All **auxiliary headers** for all streams follow; the final auxiliary header of each stream must flush its page.
3. **Data pages** for each stream follow, interleaved in time order.
4. The **final page** of each stream sets the end-of-stream flag (terminal pages need not appear contiguously).
5. Each grouped bitstream must have a **unique serial number** within the scope of the physical bitstream.

---

## Codec Mapping

Each codec defines how its logical bitstream is encapsulated into an Ogg bitstream. Ogg imposes the following mapping requirements on any codec:

- The **first page** must contain a single small initial header packet sufficient to identify the codec type, timebase, and stream continuity.
- The initial header must fit on a **single page**.
- Any **auxiliary headers** must immediately follow the initial header; the last header finishes its page before data begins.
- Granule positions must be translatable to an **exact absolute time value**.
- Packets and pages must be arranged in **ascending granule-position and time order**.

As an example, Ogg Vorbis places the codec name and revision, audio rate, and quality setting in its initial header, with Vorbis comments and detailed codec setup in the auxiliary headers.

---

## Stream Capture Confidence

Any Ogg stream can be captured with high confidence after seeing **128 KB or less** of data from any random starting point in the stream (typical figure is 6 KB). Maximum page size is just under 64 KB, which guarantees this bound.
