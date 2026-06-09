// SPDX-License-Identifier: MIT

// UAX#11 / Unicode 15.1 width tables.
// cpWidth: 0=combining, 1=normal, 2=wide

const std = @import("std");

// A half-open codepoint range [lo, hi).
const Range = struct { lo: u21, hi: u21 };

// These are the combining and zero-width ranges (where cell width is 0).
// It includes C0/C1 controls, the soft hyphen, and all the combining marks
// from the spec.
// Do not unsort this, it relies on binary search.

// <AI>
const COMBINING: []const Range = &.{
    .{ .lo = 0x0000, .hi = 0x0020 }, // C0 controls
    .{ .lo = 0x007F, .hi = 0x00A0 }, // DEL + C1 controls
    .{ .lo = 0x00AD, .hi = 0x00AE }, // SOFT HYPHEN
    .{ .lo = 0x0300, .hi = 0x0370 }, // Combining Diacritical Marks
    .{ .lo = 0x0483, .hi = 0x048A }, // Combining Cyrillic
    .{ .lo = 0x0591, .hi = 0x05BE },
    .{ .lo = 0x05BF, .hi = 0x05C0 },
    .{ .lo = 0x05C1, .hi = 0x05C3 },
    .{ .lo = 0x05C4, .hi = 0x05C6 },
    .{ .lo = 0x05C7, .hi = 0x05C8 },
    .{ .lo = 0x0610, .hi = 0x061B },
    .{ .lo = 0x064B, .hi = 0x0660 },
    .{ .lo = 0x0670, .hi = 0x0671 },
    .{ .lo = 0x06D6, .hi = 0x06DD },
    .{ .lo = 0x06DF, .hi = 0x06E5 },
    .{ .lo = 0x06E7, .hi = 0x06E9 },
    .{ .lo = 0x06EA, .hi = 0x06EE },
    .{ .lo = 0x0711, .hi = 0x0712 },
    .{ .lo = 0x0730, .hi = 0x074B },
    .{ .lo = 0x07A6, .hi = 0x07B1 },
    .{ .lo = 0x07EB, .hi = 0x07F4 },
    .{ .lo = 0x07FD, .hi = 0x07FE },
    .{ .lo = 0x0816, .hi = 0x0824 },
    .{ .lo = 0x0825, .hi = 0x082E },
    .{ .lo = 0x0829, .hi = 0x082E },
    .{ .lo = 0x0859, .hi = 0x085C },
    .{ .lo = 0x08D3, .hi = 0x08E2 },
    .{ .lo = 0x08E3, .hi = 0x0903 },
    .{ .lo = 0x093A, .hi = 0x093B },
    .{ .lo = 0x093C, .hi = 0x093D },
    .{ .lo = 0x0941, .hi = 0x0949 },
    .{ .lo = 0x094D, .hi = 0x094E },
    .{ .lo = 0x0951, .hi = 0x0958 },
    .{ .lo = 0x0962, .hi = 0x0964 },
    .{ .lo = 0x0981, .hi = 0x0982 },
    .{ .lo = 0x09BC, .hi = 0x09BD },
    .{ .lo = 0x09C1, .hi = 0x09C5 },
    .{ .lo = 0x09CD, .hi = 0x09CE },
    .{ .lo = 0x09E2, .hi = 0x09E4 },
    .{ .lo = 0x09FE, .hi = 0x09FF },
    .{ .lo = 0x0A01, .hi = 0x0A03 },
    .{ .lo = 0x0A3C, .hi = 0x0A3D },
    .{ .lo = 0x0A41, .hi = 0x0A43 },
    .{ .lo = 0x0A47, .hi = 0x0A49 },
    .{ .lo = 0x0A4B, .hi = 0x0A4E },
    .{ .lo = 0x0A51, .hi = 0x0A52 },
    .{ .lo = 0x0A70, .hi = 0x0A72 },
    .{ .lo = 0x0A75, .hi = 0x0A76 },
    .{ .lo = 0x0A81, .hi = 0x0A83 },
    .{ .lo = 0x0ABC, .hi = 0x0ABD },
    .{ .lo = 0x0AC1, .hi = 0x0AC6 },
    .{ .lo = 0x0AC7, .hi = 0x0AC9 },
    .{ .lo = 0x0ACD, .hi = 0x0ACE },
    .{ .lo = 0x0AE2, .hi = 0x0AE4 },
    .{ .lo = 0x0AFA, .hi = 0x0B00 },
    .{ .lo = 0x0B01, .hi = 0x0B02 },
    .{ .lo = 0x0B3C, .hi = 0x0B3D },
    .{ .lo = 0x0B3F, .hi = 0x0B40 },
    .{ .lo = 0x0B41, .hi = 0x0B45 },
    .{ .lo = 0x0B4D, .hi = 0x0B4E },
    .{ .lo = 0x0B55, .hi = 0x0B57 },
    .{ .lo = 0x0B62, .hi = 0x0B64 },
    .{ .lo = 0x0B82, .hi = 0x0B83 },
    .{ .lo = 0x0BC0, .hi = 0x0BC1 },
    .{ .lo = 0x0BCD, .hi = 0x0BCE },
    .{ .lo = 0x0C00, .hi = 0x0C01 },
    .{ .lo = 0x0C04, .hi = 0x0C05 },
    .{ .lo = 0x0C3C, .hi = 0x0C3D },
    .{ .lo = 0x0C3E, .hi = 0x0C41 },
    .{ .lo = 0x0C46, .hi = 0x0C49 },
    .{ .lo = 0x0C4A, .hi = 0x0C4E },
    .{ .lo = 0x0C55, .hi = 0x0C57 },
    .{ .lo = 0x0C62, .hi = 0x0C64 },
    .{ .lo = 0x0C81, .hi = 0x0C82 },
    .{ .lo = 0x0CBC, .hi = 0x0CBD },
    .{ .lo = 0x0CBF, .hi = 0x0CC0 },
    .{ .lo = 0x0CC6, .hi = 0x0CC7 },
    .{ .lo = 0x0CCC, .hi = 0x0CCE },
    .{ .lo = 0x0CE2, .hi = 0x0CE4 },
    .{ .lo = 0x0D00, .hi = 0x0D02 },
    .{ .lo = 0x0D3B, .hi = 0x0D3D },
    .{ .lo = 0x0D41, .hi = 0x0D45 },
    .{ .lo = 0x0D4D, .hi = 0x0D4E },
    .{ .lo = 0x0D62, .hi = 0x0D64 },
    .{ .lo = 0x0D81, .hi = 0x0D82 },
    .{ .lo = 0x0DCA, .hi = 0x0DCB },
    .{ .lo = 0x0DD2, .hi = 0x0DD5 },
    .{ .lo = 0x0DD6, .hi = 0x0DD7 },
    .{ .lo = 0x0E31, .hi = 0x0E32 },
    .{ .lo = 0x0E34, .hi = 0x0E3B },
    .{ .lo = 0x0E47, .hi = 0x0E4F },
    .{ .lo = 0x0EB1, .hi = 0x0EB2 },
    .{ .lo = 0x0EB4, .hi = 0x0EBD },
    .{ .lo = 0x0EC8, .hi = 0x0ECE },
    .{ .lo = 0x0F18, .hi = 0x0F1A },
    .{ .lo = 0x0F35, .hi = 0x0F36 },
    .{ .lo = 0x0F37, .hi = 0x0F38 },
    .{ .lo = 0x0F39, .hi = 0x0F3A },
    .{ .lo = 0x0F71, .hi = 0x0F7F },
    .{ .lo = 0x0F80, .hi = 0x0F85 },
    .{ .lo = 0x0F86, .hi = 0x0F88 },
    .{ .lo = 0x0F8D, .hi = 0x0F98 },
    .{ .lo = 0x0F99, .hi = 0x0FBD },
    .{ .lo = 0x0FC6, .hi = 0x0FC7 },
    .{ .lo = 0x102D, .hi = 0x1031 },
    .{ .lo = 0x1032, .hi = 0x1038 },
    .{ .lo = 0x1039, .hi = 0x103B },
    .{ .lo = 0x103D, .hi = 0x103F },
    .{ .lo = 0x1058, .hi = 0x105A },
    .{ .lo = 0x105E, .hi = 0x1061 },
    .{ .lo = 0x1071, .hi = 0x1075 },
    .{ .lo = 0x1082, .hi = 0x1083 },
    .{ .lo = 0x1085, .hi = 0x1087 },
    .{ .lo = 0x108D, .hi = 0x108E },
    .{ .lo = 0x109D, .hi = 0x109E },
    .{ .lo = 0x1160, .hi = 0x1200 }, // Hangul Jamo fillers
    .{ .lo = 0x135D, .hi = 0x1360 },
    .{ .lo = 0x1712, .hi = 0x1715 },
    .{ .lo = 0x1732, .hi = 0x1734 },
    .{ .lo = 0x1752, .hi = 0x1754 },
    .{ .lo = 0x1772, .hi = 0x1774 },
    .{ .lo = 0x17B4, .hi = 0x17B6 },
    .{ .lo = 0x17B7, .hi = 0x17BE },
    .{ .lo = 0x17C6, .hi = 0x17C7 },
    .{ .lo = 0x17C9, .hi = 0x17D4 },
    .{ .lo = 0x17DD, .hi = 0x17DE },
    .{ .lo = 0x180B, .hi = 0x180E },
    .{ .lo = 0x180F, .hi = 0x1810 },
    .{ .lo = 0x1885, .hi = 0x1887 },
    .{ .lo = 0x18A9, .hi = 0x18AA },
    .{ .lo = 0x1920, .hi = 0x1923 },
    .{ .lo = 0x1927, .hi = 0x1929 },
    .{ .lo = 0x1932, .hi = 0x1933 },
    .{ .lo = 0x1939, .hi = 0x193C },
    .{ .lo = 0x1A17, .hi = 0x1A19 },
    .{ .lo = 0x1A1B, .hi = 0x1A1C },
    .{ .lo = 0x1A56, .hi = 0x1A57 },
    .{ .lo = 0x1A58, .hi = 0x1A5F },
    .{ .lo = 0x1A60, .hi = 0x1A61 },
    .{ .lo = 0x1A62, .hi = 0x1A63 },
    .{ .lo = 0x1A65, .hi = 0x1A6D },
    .{ .lo = 0x1A73, .hi = 0x1A7D },
    .{ .lo = 0x1A7F, .hi = 0x1A80 },
    .{ .lo = 0x1AB0, .hi = 0x1ACF },
    .{ .lo = 0x1B00, .hi = 0x1B04 },
    .{ .lo = 0x1B34, .hi = 0x1B35 },
    .{ .lo = 0x1B36, .hi = 0x1B3B },
    .{ .lo = 0x1B3C, .hi = 0x1B3D },
    .{ .lo = 0x1B42, .hi = 0x1B43 },
    .{ .lo = 0x1B6B, .hi = 0x1B74 },
    .{ .lo = 0x1B80, .hi = 0x1B82 },
    .{ .lo = 0x1BA2, .hi = 0x1BA6 },
    .{ .lo = 0x1BA8, .hi = 0x1BAA },
    .{ .lo = 0x1BAB, .hi = 0x1BAE },
    .{ .lo = 0x1BE6, .hi = 0x1BE7 },
    .{ .lo = 0x1BE8, .hi = 0x1BEA },
    .{ .lo = 0x1BED, .hi = 0x1BEE },
    .{ .lo = 0x1BEF, .hi = 0x1BF2 },
    .{ .lo = 0x1C2C, .hi = 0x1C34 },
    .{ .lo = 0x1C36, .hi = 0x1C38 },
    .{ .lo = 0x1CD0, .hi = 0x1CD3 },
    .{ .lo = 0x1CD4, .hi = 0x1CE1 },
    .{ .lo = 0x1CE2, .hi = 0x1CE9 },
    .{ .lo = 0x1CED, .hi = 0x1CEE },
    .{ .lo = 0x1CF4, .hi = 0x1CF5 },
    .{ .lo = 0x1CF8, .hi = 0x1CFA },
    .{ .lo = 0x1DC0, .hi = 0x1E00 },
    .{ .lo = 0x20D0, .hi = 0x20F1 },
    .{ .lo = 0x2CEF, .hi = 0x2CF2 },
    .{ .lo = 0x2D7F, .hi = 0x2D80 },
    .{ .lo = 0x2DE0, .hi = 0x2E00 },
    .{ .lo = 0x302A, .hi = 0x302E },
    .{ .lo = 0x3099, .hi = 0x309B },
    .{ .lo = 0xA66F, .hi = 0xA670 },
    .{ .lo = 0xA674, .hi = 0xA67E },
    .{ .lo = 0xA69E, .hi = 0xA6A0 },
    .{ .lo = 0xA6F0, .hi = 0xA6F2 },
    .{ .lo = 0xA802, .hi = 0xA803 },
    .{ .lo = 0xA806, .hi = 0xA807 },
    .{ .lo = 0xA80B, .hi = 0xA80C },
    .{ .lo = 0xA825, .hi = 0xA827 },
    .{ .lo = 0xA82C, .hi = 0xA82D },
    .{ .lo = 0xA8C4, .hi = 0xA8C6 },
    .{ .lo = 0xA8E0, .hi = 0xA8F2 },
    .{ .lo = 0xA8FF, .hi = 0xA900 },
    .{ .lo = 0xA926, .hi = 0xA92E },
    .{ .lo = 0xA947, .hi = 0xA952 },
    .{ .lo = 0xA980, .hi = 0xA983 },
    .{ .lo = 0xA9B3, .hi = 0xA9B4 },
    .{ .lo = 0xA9B6, .hi = 0xA9BA },
    .{ .lo = 0xA9BC, .hi = 0xA9BE },
    .{ .lo = 0xA9E5, .hi = 0xA9E6 },
    .{ .lo = 0xAA29, .hi = 0xAA2F },
    .{ .lo = 0xAA31, .hi = 0xAA33 },
    .{ .lo = 0xAA35, .hi = 0xAA37 },
    .{ .lo = 0xAA43, .hi = 0xAA44 },
    .{ .lo = 0xAA4C, .hi = 0xAA4D },
    .{ .lo = 0xAA7C, .hi = 0xAA7D },
    .{ .lo = 0xAAB0, .hi = 0xAAB1 },
    .{ .lo = 0xAAB2, .hi = 0xAAB5 },
    .{ .lo = 0xAAB7, .hi = 0xAAB9 },
    .{ .lo = 0xAABE, .hi = 0xAAC0 },
    .{ .lo = 0xAAC1, .hi = 0xAAC2 },
    .{ .lo = 0xAAEC, .hi = 0xAAEE },
    .{ .lo = 0xAAF6, .hi = 0xAAF7 },
    .{ .lo = 0xABE5, .hi = 0xABE6 },
    .{ .lo = 0xABE8, .hi = 0xABE9 },
    .{ .lo = 0xABED, .hi = 0xABEE },
    .{ .lo = 0xFB1E, .hi = 0xFB1F },
    .{ .lo = 0xFE00, .hi = 0xFE10 }, // variation selectors
    .{ .lo = 0xFE20, .hi = 0xFE30 }, // combining half marks
    .{ .lo = 0xFFF9, .hi = 0xFFFC }, // interlinear annotation
    .{ .lo = 0x101FD, .hi = 0x101FE },
    .{ .lo = 0x102E0, .hi = 0x102E1 },
    .{ .lo = 0x10376, .hi = 0x1037B },
    .{ .lo = 0x10A01, .hi = 0x10A04 },
    .{ .lo = 0x10A05, .hi = 0x10A07 },
    .{ .lo = 0x10A0C, .hi = 0x10A10 },
    .{ .lo = 0x10A38, .hi = 0x10A3B },
    .{ .lo = 0x10A3F, .hi = 0x10A40 },
    .{ .lo = 0x10AE5, .hi = 0x10AE7 },
    .{ .lo = 0x10D24, .hi = 0x10D28 },
    .{ .lo = 0x10EAB, .hi = 0x10EAD },
    .{ .lo = 0x10EFD, .hi = 0x10F00 },
    .{ .lo = 0x10F46, .hi = 0x10F51 },
    .{ .lo = 0x10F82, .hi = 0x10F86 },
    .{ .lo = 0x11001, .hi = 0x11002 },
    .{ .lo = 0x11038, .hi = 0x11047 },
    .{ .lo = 0x11070, .hi = 0x11071 },
    .{ .lo = 0x11073, .hi = 0x11075 },
    .{ .lo = 0x1107F, .hi = 0x11082 },
    .{ .lo = 0x110B3, .hi = 0x110B7 },
    .{ .lo = 0x110B9, .hi = 0x110BB },
    .{ .lo = 0x110C2, .hi = 0x110C3 },
    .{ .lo = 0x11100, .hi = 0x11103 },
    .{ .lo = 0x11127, .hi = 0x1112C },
    .{ .lo = 0x1112D, .hi = 0x11135 },
    .{ .lo = 0x11173, .hi = 0x11174 },
    .{ .lo = 0x11180, .hi = 0x11182 },
    .{ .lo = 0x111B6, .hi = 0x111BF },
    .{ .lo = 0x111C9, .hi = 0x111CD },
    .{ .lo = 0x111CF, .hi = 0x111D0 },
    .{ .lo = 0x1122F, .hi = 0x11232 },
    .{ .lo = 0x11234, .hi = 0x11235 },
    .{ .lo = 0x11236, .hi = 0x11238 },
    .{ .lo = 0x1123E, .hi = 0x1123F },
    .{ .lo = 0x11241, .hi = 0x11242 },
    .{ .lo = 0x112DF, .hi = 0x112E0 },
    .{ .lo = 0x112E3, .hi = 0x112EB },
    .{ .lo = 0x11300, .hi = 0x11302 },
    .{ .lo = 0x1133B, .hi = 0x1133D },
    .{ .lo = 0x11340, .hi = 0x11341 },
    .{ .lo = 0x11366, .hi = 0x1136D },
    .{ .lo = 0x11370, .hi = 0x11375 },
    .{ .lo = 0x11438, .hi = 0x11440 },
    .{ .lo = 0x11442, .hi = 0x11445 },
    .{ .lo = 0x11446, .hi = 0x11447 },
    .{ .lo = 0x1145E, .hi = 0x1145F },
    .{ .lo = 0x114B3, .hi = 0x114B9 },
    .{ .lo = 0x114BA, .hi = 0x114BB },
    .{ .lo = 0x114BF, .hi = 0x114C1 },
    .{ .lo = 0x114C2, .hi = 0x114C4 },
    .{ .lo = 0x115B2, .hi = 0x115B6 },
    .{ .lo = 0x115BC, .hi = 0x115BE },
    .{ .lo = 0x115BF, .hi = 0x115C1 },
    .{ .lo = 0x115DC, .hi = 0x115DE },
    .{ .lo = 0x11633, .hi = 0x1163B },
    .{ .lo = 0x1163D, .hi = 0x1163E },
    .{ .lo = 0x1163F, .hi = 0x11641 },
    .{ .lo = 0x116AB, .hi = 0x116AC },
    .{ .lo = 0x116AD, .hi = 0x116AE },
    .{ .lo = 0x116B0, .hi = 0x116B6 },
    .{ .lo = 0x116B7, .hi = 0x116B8 },
    .{ .lo = 0x1171D, .hi = 0x11720 },
    .{ .lo = 0x11722, .hi = 0x11726 },
    .{ .lo = 0x11727, .hi = 0x1172C },
    .{ .lo = 0x1182F, .hi = 0x11838 },
    .{ .lo = 0x11839, .hi = 0x1183B },
    .{ .lo = 0x1193B, .hi = 0x1193D },
    .{ .lo = 0x1193E, .hi = 0x1193F },
    .{ .lo = 0x11943, .hi = 0x11944 },
    .{ .lo = 0x119D4, .hi = 0x119D8 },
    .{ .lo = 0x119DA, .hi = 0x119DC },
    .{ .lo = 0x119E0, .hi = 0x119E1 },
    .{ .lo = 0x11A01, .hi = 0x11A0B },
    .{ .lo = 0x11A33, .hi = 0x11A39 },
    .{ .lo = 0x11A3B, .hi = 0x11A3F },
    .{ .lo = 0x11A47, .hi = 0x11A48 },
    .{ .lo = 0x11A51, .hi = 0x11A57 },
    .{ .lo = 0x11A59, .hi = 0x11A5C },
    .{ .lo = 0x11A8A, .hi = 0x11A97 },
    .{ .lo = 0x11A98, .hi = 0x11A9A },
    .{ .lo = 0x11C30, .hi = 0x11C37 },
    .{ .lo = 0x11C38, .hi = 0x11C3E },
    .{ .lo = 0x11C3F, .hi = 0x11C40 },
    .{ .lo = 0x11C92, .hi = 0x11CA8 },
    .{ .lo = 0x11CAA, .hi = 0x11CB1 },
    .{ .lo = 0x11CB2, .hi = 0x11CB4 },
    .{ .lo = 0x11CB5, .hi = 0x11CB7 },
    .{ .lo = 0x11D31, .hi = 0x11D37 },
    .{ .lo = 0x11D3A, .hi = 0x11D3B },
    .{ .lo = 0x11D3C, .hi = 0x11D3E },
    .{ .lo = 0x11D3F, .hi = 0x11D46 },
    .{ .lo = 0x11D47, .hi = 0x11D48 },
    .{ .lo = 0x11D90, .hi = 0x11D92 },
    .{ .lo = 0x11D95, .hi = 0x11D96 },
    .{ .lo = 0x11D97, .hi = 0x11D98 },
    .{ .lo = 0x11EF3, .hi = 0x11EF5 },
    .{ .lo = 0x11F00, .hi = 0x11F02 },
    .{ .lo = 0x11F36, .hi = 0x11F3B },
    .{ .lo = 0x11F40, .hi = 0x11F41 },
    .{ .lo = 0x11F42, .hi = 0x11F43 },
    .{ .lo = 0x11F5A, .hi = 0x11F5B },
    .{ .lo = 0x13440, .hi = 0x13441 },
    .{ .lo = 0x13447, .hi = 0x13456 },
    .{ .lo = 0x16AF0, .hi = 0x16AF5 },
    .{ .lo = 0x16B30, .hi = 0x16B37 },
    .{ .lo = 0x16F4F, .hi = 0x16F50 },
    .{ .lo = 0x16F8F, .hi = 0x16F93 },
    .{ .lo = 0x16FE4, .hi = 0x16FE5 },
    .{ .lo = 0x1BC9D, .hi = 0x1BC9F },
    .{ .lo = 0x1CF00, .hi = 0x1CF2E },
    .{ .lo = 0x1CF30, .hi = 0x1CF47 },
    .{ .lo = 0x1D167, .hi = 0x1D16A },
    .{ .lo = 0x1D17B, .hi = 0x1D183 },
    .{ .lo = 0x1D185, .hi = 0x1D18C },
    .{ .lo = 0x1D1AA, .hi = 0x1D1AE },
    .{ .lo = 0x1D242, .hi = 0x1D245 },
    .{ .lo = 0x1DA00, .hi = 0x1DA37 },
    .{ .lo = 0x1DA3B, .hi = 0x1DA6D },
    .{ .lo = 0x1DA75, .hi = 0x1DA76 },
    .{ .lo = 0x1DA84, .hi = 0x1DA85 },
    .{ .lo = 0x1DA9B, .hi = 0x1DAA0 },
    .{ .lo = 0x1DAA1, .hi = 0x1DAB0 },
    .{ .lo = 0x1E000, .hi = 0x1E007 },
    .{ .lo = 0x1E008, .hi = 0x1E019 },
    .{ .lo = 0x1E01B, .hi = 0x1E022 },
    .{ .lo = 0x1E023, .hi = 0x1E025 },
    .{ .lo = 0x1E026, .hi = 0x1E02B },
    .{ .lo = 0x1E08F, .hi = 0x1E090 },
    .{ .lo = 0x1E130, .hi = 0x1E137 },
    .{ .lo = 0x1E2AE, .hi = 0x1E2AF },
    .{ .lo = 0x1E2EC, .hi = 0x1E2F0 },
    .{ .lo = 0x1E4EC, .hi = 0x1E4F0 },
    .{ .lo = 0x1E8D0, .hi = 0x1E8D7 },
    .{ .lo = 0x1E944, .hi = 0x1E94B },
    .{ .lo = 0xE0020, .hi = 0xE0080 }, // tags
    .{ .lo = 0xE0100, .hi = 0xE01F0 }, // variation selectors supplement
};

// Wide character ranges (cell width = 2), per UAX#11 East Asian Wide/Fullwidth.
const WIDE: []const Range = &.{
    .{ .lo = 0x1100, .hi = 0x1160 }, // Hangul Jamo
    .{ .lo = 0x2329, .hi = 0x232B }, // angle brackets (CJK compat)
    .{ .lo = 0x2E80, .hi = 0x303F }, // CJK Radicals through CJK Symbols
    .{ .lo = 0x3041, .hi = 0x33C0 }, // Hiragana..CJK Compat
    .{ .lo = 0x33FF, .hi = 0x3400 },
    .{ .lo = 0x3400, .hi = 0x4DC0 }, // CJK Ext A
    .{ .lo = 0x4E00, .hi = 0xA4D0 }, // CJK Unified + Yi
    .{ .lo = 0xA960, .hi = 0xA980 }, // Hangul Jamo Ext-A
    .{ .lo = 0xAC00, .hi = 0xD800 }, // Hangul Syllables + Ext-B
    .{ .lo = 0xF900, .hi = 0xFB00 }, // CJK Compat Ideographs
    .{ .lo = 0xFE10, .hi = 0xFE1A }, // Vertical Forms
    .{ .lo = 0xFE30, .hi = 0xFE70 }, // CJK Compat Forms + Small Form Variants
    .{ .lo = 0xFF00, .hi = 0xFF61 }, // Fullwidth Latin, Katakana
    .{ .lo = 0xFFE0, .hi = 0xFFE7 }, // Fullwidth signs
    .{ .lo = 0x1B000, .hi = 0x1B300 }, // Kana Extended + Nushu
    .{ .lo = 0x1F004, .hi = 0x1F005 }, // Mahjong Tile
    .{ .lo = 0x1F0CF, .hi = 0x1F0D0 }, // Joker
    .{ .lo = 0x1F200, .hi = 0x1F300 }, // Enclosed Ideographic
    .{ .lo = 0x1F300, .hi = 0x1F650 }, // Misc symbols + emoticons
    .{ .lo = 0x1F67C, .hi = 0x1F680 }, // ornamental brackets
    .{ .lo = 0x1F900, .hi = 0x1FA00 }, // Supplemental Symbols and Pictographs
    .{ .lo = 0x1FA00, .hi = 0x1FA70 }, // Chess + Draughts
    .{ .lo = 0x1FA70, .hi = 0x1FB00 }, // Symbols and Pictographs Ext-A
    .{ .lo = 0x20000, .hi = 0x30000 }, // CJK Ext B-F
    .{ .lo = 0x30000, .hi = 0x40000 }, // CJK Ext G
};

// </AI>

fn rangeContains(ranges: []const Range, cp: u21) bool {
    // binary search over sorted table
    var lo: usize = 0;
    var hi: usize = ranges.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const r = ranges[mid];
        if (cp < r.lo) {
            hi = mid;
        } else if (cp >= r.hi) {
            lo = mid + 1;
        } else {
            return true;
        }
    }
    return false;
}

pub fn cpWidth(cp: u21) u2 {
    if (rangeContains(COMBINING, cp)) return 0;
    if (rangeContains(WIDE, cp)) return 2;
    return 1;
}

// Cell width of a plain UTF-8 string
pub fn rawWidth(s: []const u8) usize {
    var w: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const len = std.unicode.utf8ByteSequenceLength(s[i]) catch {
            i += 1;
            continue;
        };
        if (i + len > s.len) break;
        const cp = std.unicode.utf8Decode(s[i .. i + len]) catch 0xFFFD;
        w += cpWidth(cp);
        i += len;
    }
    return w;
}

// Cell width of an ANSI-escaped string
// Skips CSI, OSC, DCS, and plain ESC+byte sequences
pub fn strWidth(s: []const u8) usize {
    var w: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const b = s[i];
        if (b == 0x1B and i + 1 < s.len) {
            const next = s[i + 1];
            i += 2;
            if (next == '[') {
                // CSI: consume until 0x40-0x7E
                while (i < s.len and (s[i] < 0x40 or s[i] > 0x7E)) : (i += 1) {}
                if (i < s.len) i += 1; // consume final byte
            } else if (next == ']') {
                // OSC: consume until ESC\ or BEL
                while (i < s.len) {
                    if (s[i] == 0x07) {
                        i += 1;
                        break;
                    }
                    if (s[i] == 0x1B and i + 1 < s.len and s[i + 1] == '\\') {
                        i += 2;
                        break;
                    }
                    i += 1;
                }
            } else if (next == 'P') {
                // DCS: consume until ESC\
                while (i < s.len) {
                    if (s[i] == 0x1B and i + 1 < s.len and s[i + 1] == '\\') {
                        i += 2;
                        break;
                    }
                    i += 1;
                }
            } else if (next == '_') {
                // APC: consume until ESC\
                while (i < s.len) {
                    if (s[i] == 0x1B and i + 1 < s.len and s[i + 1] == '\\') {
                        i += 2;
                        break;
                    }
                    i += 1;
                }
            }
            // any other ESC+byte: already consumed 2 bytes above
            continue;
        }
        if (b < 0x20 or b == 0x7F) {
            // C0/C1 control, zero width
            i += 1;
            continue;
        }
        const seq_len = std.unicode.utf8ByteSequenceLength(b) catch {
            i += 1;
            continue;
        };
        if (i + seq_len > s.len) break;
        const cp = std.unicode.utf8Decode(s[i .. i + seq_len]) catch 0xFFFD;
        w += cpWidth(cp);
        i += seq_len;
    }
    return w;
}

test "cpWidth ASCII" {
    try std.testing.expectEqual(@as(u2, 1), cpWidth('A'));
}

test "cpWidth CJK wide" {
    try std.testing.expectEqual(@as(u2, 2), cpWidth(0x4E2D));
}

test "cpWidth combining grave" {
    try std.testing.expectEqual(@as(u2, 0), cpWidth(0x0300));
}

test "rawWidth hello" {
    try std.testing.expectEqual(@as(usize, 5), rawWidth("hello"));
}

test "rawWidth CJK" {
    try std.testing.expectEqual(@as(usize, 4), rawWidth("\xe4\xb8\xad\xe6\x96\x87"));
}

test "strWidth bold hello" {
    try std.testing.expectEqual(@as(usize, 5), strWidth("\x1b[1mhello\x1b[0m"));
}

test "strWidth rgb color hi" {
    try std.testing.expectEqual(@as(usize, 2), strWidth("\x1b[38;2;255;0;0mhi\x1b[0m"));
}
