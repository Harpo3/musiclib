# MP4 Registration Authority — Atom/Box Types

This page documents the structural atom or box types for MP4 family file formats. All files in this family are structured as a series of boxes (also known as atoms). Each box has a size and a four-character-code type. Boxes may contain other boxes.

Source: https://cconcolato.github.io/mp4ra/atoms.html

---

## ISO Family Codes

| Code | Description | Specification |
| --- | --- | --- |
| ainf | Asset information to identify, license and play | DECE |
| avcn | AVC NAL Unit Storage Box | DECE |
| bloc | Base location and purchase location for license acquisition | DECE |
| bpcc | Bits per component | JPEG2000 |
| buff | Buffering information | NALu Video |
| bxml | binary XML container | ISO |
| ccid | OMA DRM Content ID | OMA DRM 2.1 |
| cdef | type and ordering of the components within the codestream | JPEG2000 |
| clip | Reserved | ISO |
| cmap | mapping between a palette and codestream components | JPEG2000 |
| co64 | 64-bit chunk offset | ISO |
| coin | Content Information Box | DECE |
| colr | specifies the colourspace of the image | JPEG2000 |
| crgn | Reserved | ISO |
| crhd | reserved for ClockReferenceStream header | MP4v1 |
| cslg | composition to decode timeline mapping | ISO |
| ctab | Reserved | ISO |
| ctts | (composition) time to sample | ISO |
| cvru | OMA DRM Cover URI | OMA DRM 2.1 |
| dinf | data information box, container | ISO |
| dref | data reference box, declares source(s) of media data in track | ISO |
| dsgd | DVB Sample Group Description Box | DVB |
| dstg | DVB Sample to Group Box | DVB |
| edts | edit list container | ISO |
| elst | an edit list | ISO |
| emsg | event message | DASH |
| evti | Event information | ATSC 3.0 |
| fdel | File delivery information (item info extension) | ISO |
| feci | FEC Informatiom | ISO |
| fecr | FEC Reservoir | ISO |
| fiin | FD Item Information | ISO |
| fire | File Reservoir | ISO |
| fpar | File Partition | ISO |
| free | free space | ISO |
| frma | original format box | ISO |
| ftyp | file type and compatibility | ISO |
| gitn | Group ID to name | ISO |
| grpi | OMA DRM Group ID | OMA DRM 2.0 |
| hdlr | handler, declares the media (handler) type | ISO |
| hmhd | hint media header, overall information (hint track only) | ISO |
| hpix | Hipix Rich Picture (user-data or meta-data) | Hipix |
| icnu | OMA DRM Icon URI | OMA DRM 2.0 |
| ID32 | ID3 version 2 container | id3v2 |
| idat | Item data | ISO |
| ihdr | Image Header | JPEG2000 |
| iinf | item information | ISO |
| iloc | item location | ISO |
| imap | Reserved | ISO |
| imif | IPMP Information box | ISO |
| infe | Item information entry | ISO |
| infu | OMA DRM Info URL | OMA DRM 2.0 |
| iods | Object Descriptor container box | MP4v1 |
| iphd | reserved for IPMP Stream header | MP4v1 |
| ipmc | IPMP Control Box | ISO |
| ipro | item protection | ISO |
| iref | Item reference | ISO |
| jP$20$20 | JPEG 2000 Signature | JPEG2000 |
| jp2c | JPEG 2000 contiguous codestream | JPEG2000 |
| jp2h | Header | JPEG2000 |
| jp2i | intellectual property information | JPEG2000 |
| kmat | Reserved | ISO |
| leva | Leval assignment | ISO |
| load | Reserved | ISO |
| loop | Looping behavior | WhatsApp |
| lrcu | OMA DRM Lyrics URI | OMA DRM 2.1 |
| m7hd | reserved for MPEG7Stream header | MP4v1 |
| matt | Reserved | ISO |
| mdat | media data container | ISO |
| mdhd | media header, overall information about the media | ISO |
| mdia | container for the media information in a track | ISO |
| mdri | Mutable DRM information | OMA DRM 2.0 |
| meco | additional metadata container | ISO |
| mehd | movie extends header box | ISO |
| mere | metabox relation | ISO |
| meta | Metadata container | ISO |
| mfhd | movie fragment header | ISO |
| mfra | Movie fragment random access | ISO |
| mfro | Movie fragment random access offset | ISO |
| minf | media information container | ISO |
| mjhd | reserved for MPEG-J Stream header | MP4v1 |
| moof | movie fragment | ISO |
| moov | container for all the meta-data | ISO |
| mvcg | Multiview group | NALu Video |
| mvci | Multiview Information | NALu Video |
| mvex | movie extends box | ISO |
| mvhd | movie header, overall declarations | ISO |
| mvra | Multiview Relation Attribute | NALu Video |
| nmhd | Null media header, overall information (some tracks only) | ISO |
| ochd | reserved for ObjectContentInfoStream header | MP4v1 |
| odaf | OMA DRM Access Unit Format | OMA DRM 2.0 |
| odda | OMA DRM Content Object | OMA DRM 2.0 |
| odhd | reserved for ObjectDescriptorStream header | MP4v1 |
| odhe | OMA DRM Discrete Media Headers | OMA DRM 2.0 |
| odrb | OMA DRM Rights Object | OMA DRM 2.0 |
| odrm | OMA DRM Container | OMA DRM 2.0 |
| odtt | OMA DRM Transaction Tracking | OMA DRM 2.0 |
| ohdr | OMA DRM Common headers | OMA DRM 2.0 |
| padb | sample padding bits | ISO |
| paen | Partition Entry | ISO |
| pclr | palette which maps a single component in index space to a multiple- component image | JPEG2000 |
| pdin | Progressive download information | ISO |
| pitm | primary item reference | ISO |
| pnot | Reserved | ISO |
| prft | Producer reference time | ISO |
| pssh | Protection system specific header | ISO Common Encryption |
| res$20 | grid resolution | JPEG2000 |
| resc | grid resolution at which the image was captured | JPEG2000 |
| resd | default grid resolution at which the image should be displayed | JPEG2000 |
| rinf | restricted scheme information box | ISO |
| saio | Sample auxiliary information offsets | ISO |
| saiz | Sample auxiliary information sizes | ISO |
| sbgp | Sample to Group box | ISO |
| schi | scheme information box | ISO |
| schm | scheme type box | ISO |
| sdep | Sample dependency | NALu Video |
| sdhd | reserved for SceneDescriptionStream header | MP4v1 |
| sdtp | Independent and Disposable Samples Box | ISO |
| sdvp | SD Profile Box | SDV |
| segr | file delivery session group | ISO |
| senc | Sample specific encryption data | ISO Common Encryption |
| sgpd | Sample group definition box | ISO |
| sidx | Segment Index Box | 3GPP |
| sinf | protection scheme information box | ISO |
| skip | free space | ISO |
| smhd | sound media header, overall information (sound track only) | ISO |
| srmb | System Renewability Message | DVB |
| srmc | System Renewability Message container | DVB |
| srpp | STRP Process | ISO |
| ssix | Sub-sample index | ISO |
| stbl | sample table box, container for the time/space map | ISO |
| stco | chunk offset, partial data-offset information | ISO |
| stdp | sample degradation priority | ISO |
| sthd | Subtitle Media Header Box | ISO |
| strd | Sub-track definition | ISO |
| stri | Sub-track information | ISO |
| stsc | sample-to-chunk, partial data-offset information | ISO |
| stsd | sample descriptions (codec types, initialization etc.) | ISO |
| stsg | Sub-track sample grouping | ISO |
| stsh | shadow sync sample table | ISO |
| stss | sync sample table (random access points) | ISO |
| stsz | sample sizes (framing) | ISO |
| stts | (decoding) time-to-sample | ISO |
| styp | Segment Type Box | 3GPP |
| stz2 | compact sample sizes (framing) | ISO |
| subs | Sub-sample information | ISO |
| swtc | Multiview Group Relation | NALu Video |
| tfad | Track fragment adjustment box | 3GPP |
| tfdt | Track fragment decode time | ISO |
| tfhd | Track fragment header | ISO |
| tfma | Track fragment media adjustment box | 3GPP |
| tfra | Track fragment radom access | ISO |
| tibr | Tier Bit rate | NALu Video |
| tiri | Tier Information | NALu Video |
| tkhd | Track header, overall information about the track | ISO |
| traf | Track fragment | ISO |
| trak | container for an individual track or stream | ISO |
| tref | track reference container | ISO |
| trex | track extends defaults | ISO |
| trgr | Track grouping information | ISO |
| trik | Facilitates random access and trick play modes | DECE |
| trun | track fragment run | ISO |
| udta | user-data | ISO |
| uinf | a tool by which a vendor may provide access to additional information associated with a UUID | JPEG2000 |
| UITS | Unique Identifier Technology Solution | Universal Music Group |
| ulst | a list of UUID’s | JPEG2000 |
| url$20 | a URL | JPEG2000 |
| uuid | user-extension box | ISO |
| vmhd | video media header, overall information (video track only) | ISO |
| vwdi | Multiview Scene Information | NALu Video |
| xml$20 | XML container | ISO |
| xml$20 | a tool by which vendors can add XML formatted information | JPEG2000 |

---

## User-data Codes

| Code | Description | Specification |
| --- | --- | --- |
| albm | Album title and track number for media | 3GPP |
| alou | Album loudness base | ISO |
| angl | Name of the camera angle through which the clip was shot | Apple |
| auth | Author of the media | 3GPP |
| clfn | Name of the clip file | Apple |
| clid | Identifier of the clip | Apple |
| clsf | Classification of the media | 3GPP |
| cmid | Identifier of the camera | Apple |
| cmnm | Name that identifies the camera | Apple |
| coll | Name of the collection from which the media comes | 3GPP |
| cprt | copyright etc. | ISO |
| date | Date and time, formatted according to ISO 8601, when the content was created. For clips captured by recording devices, this is typically the date and time when the clip’s recording started. | Apple |
| dscp | Media description | 3GPP |
| gnre | Media genre | 3GPP |
| hinf | hint information | ISO |
| hnti | Hint information | ISO |
| hpix | Hipix Rich Picture (user-data or meta-data) | Hipix |
| kywd | Media keywords | 3GPP |
| loci | Media location information | 3GPP |
| ludt | Track loudness container | ISO |
| manu | Manufacturer name of the camera | Apple |
| modl | Model name of the camera | Apple |
| orie | Orientation information | 3GPP |
| perf | Media performer name | 3GPP |
| reel | Name of the tape reel | Apple |
| rtng | Media rating | 3GPP |
| scen | Name of the scene for which the clip was shot | Apple |
| shot | Name that identifies the shot | Apple |
| slno | Serial number of the camera | Apple |
| strk | Sub track information | ISO |
| thmb | Thumbnail image of the media | 3GPP |
| titl | Media title | 3GPP |
| tlou | Track loudness base | ISO |
| tsel | Track selection | ISO |
| tsel | Track selection | 3GPP |
| urat | User 'star' rating of the media | 3GPP |
| yrrc | Year when media was recorded | 3GPP |

---

## QuickTime Codes

| Code | Description | Specification |
| --- | --- | --- |
| albm | Album title and track number (user-data) | 3GPP |
| auth | Media author name (user-data) | 3GPP |
| clip | Visual clipping region container | QT |
| clsf | Media classification (user-data) | 3GPP |
| cprt | copyright etc. (user-data) | ISO |
| crgn | Visual clipping region definition | QT |
| ctab | Track color-table | QT |
| dcfD | Marlin DCF Duration, user-data atom type | OMArlin |
| elng | Extended Language Tag | QT |
| imap | Track input map definition | QT |
| kmat | Compressed visual track matte | QT |
| load | Track pre-load definitions | QT |
| matt | Visual track matte for compositing | QT |
| pnot | Preview container | QT |
| wide | Expansion space reservation | QT |