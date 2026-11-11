// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title TIME CARDS art renderer
/// @notice Builds each card fully on-chain from 64x64 pixel layers stored in `data`
///  (raw PNG bytes kept as contract code). Zodiac animal = Beijing hour (时辰);
///  hat / glasses / neckwear and their colors = digits of the date and time.
///  No owner, nothing can be changed after deploy.
contract TimeCardsArt {
    using Strings for uint256;

    address public immutable data;

    // 24 assets: uint16 offset + uint16 length each.
    // 0-11 animals (rat..pig), 12-15 hats (beanie tint/fixed, cap tint/fixed),
    // 16-19 glasses (3D t/f, shades t/f), 20-23 neck (scarf t/f, bowtie t/f)
    bytes private constant IDX =
        hex"000006f306f305c00cb30674132705f1191806cc1fe40657263b05982bd305fb31ce05e237b004f53ca5068b4330046c479c01b8495400ef4a4301444b8700e94c7000e04d5001214e7101264f9700e3507a013051aa00c8527200e8535a0064";

    uint256 private constant TZ = 8 hours;

    constructor(address data_) {
        require(data_.code.length > 0, "data");
        data = data_;
    }

    // ------------------------------------------------------------ public

    function tokenURI(uint256 tokenId, uint256 t, uint8 tier, bool genesis) external view returns (string memory) {
        Moment memory m = _moment(t);
        string memory hms = string.concat(_two(m.hh), ":", _two(m.mi), ":", _two(m.ss));
        string memory date = string.concat(m.yy.toString(), ".", _two(m.mo), ".", _two(m.dd));
        string memory svg = _svg(m, hms, date, tier, genesis, tokenId);
        string memory json = string.concat(
            '{"name":"TIME ', hms, " ", date, genesis ? ' (Genesis)' : "",
            '","description":"A moment in time, drawn fully on-chain. Beijing time (UTC+8).",',
            '"attributes":', _attrs(m, hms, date, tier, genesis, t),
            ',"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '"}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    // ------------------------------------------------------------ traits

    struct Moment {
        uint256 yy; uint256 mo; uint256 dd; uint256 hh; uint256 mi; uint256 ss;
        uint256 animal; uint256 hat; uint256 eyes; uint256 neck;
        uint256 cHat; uint256 cEyes; uint256 cNeck; uint256 bg; uint256 lcd;
    }

    function _moment(uint256 t) private pure returns (Moment memory m) {
        uint256 lt = t + TZ;
        uint256 sod = lt % 86400;
        m.hh = sod / 3600; m.mi = (sod % 3600) / 60; m.ss = sod % 60;
        (m.yy, m.mo, m.dd) = _civil(lt / 86400);
        m.animal = ((m.hh + 1) / 2) % 12;
        m.hat = (m.mi / 10) % 3;          // 0 none, 1 beanie, 2 cap
        m.eyes = (m.mi % 10) % 3;         // 0 none, 1 3D, 2 shades
        m.neck = (m.dd % 10) % 3;         // 0 none, 1 scarf, 2 bow tie
        m.cHat = m.dd % 10;
        m.cEyes = m.mo % 10;
        m.cNeck = m.mi % 10;
        m.bg = m.dd % 10;
        m.lcd = m.ss / 10;
    }

    function _civil(uint256 days_) private pure returns (uint256 y, uint256 mo, uint256 d) {
        int256 z = int256(days_) + 719468;
        int256 era = z / 146097;
        int256 doe = z - era * 146097;
        int256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        int256 yy = yoe + era * 400;
        int256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        int256 mp = (5 * doy + 2) / 153;
        int256 dd = doy - (153 * mp + 2) / 5 + 1;
        int256 mm = mp < 10 ? mp + 3 : mp - 9;
        if (mm <= 2) yy += 1;
        return (uint256(yy), uint256(mm), uint256(dd));
    }

    function _attrs(Moment memory m, string memory hms, string memory date, uint8 tier, bool genesis, uint256 t)
        private pure returns (string memory)
    {
        string[12] memory an = ["Rat", "Ox", "Tiger", "Rabbit", "Dragon", "Snake", "Horse", "Goat", "Monkey", "Rooster", "Dog", "Pig"];
        string[3] memory ht = ["None", "Beanie", "Cap"];
        string[3] memory ey = ["None", "3D Glasses", "Shades"];
        string[3] memory nk = ["None", "Scarf", "Bow Tie"];
        string memory a = string.concat(
            '[{"trait_type":"Zodiac","value":"', an[m.animal],
            '"},{"trait_type":"Hat","value":"', m.hat == 0 ? "None" : string.concat(_colName(m.cHat), " ", ht[m.hat]),
            '"},{"trait_type":"Eyes","value":"', m.eyes == 0 ? "None" : string.concat(_colName(m.cEyes), " ", ey[m.eyes]),
            '"},{"trait_type":"Neck","value":"', m.neck == 0 ? "None" : string.concat(_colName(m.cNeck), " ", nk[m.neck])
        );
        return string.concat(
            a,
            '"},{"trait_type":"Tier","value":"', _tierName(tier),
            '"},{"trait_type":"Edition","value":"', genesis ? "Genesis" : "Moment",
            '"},{"trait_type":"Time","value":"', hms,
            '"},{"trait_type":"Date","value":"', date,
            '"},{"display_type":"date","trait_type":"Timestamp","value":', t.toString(), "}]"
        );
    }

    // ------------------------------------------------------------ palette

    function _col(uint256 i) private pure returns (uint256 rgb) {
        // 0 white 1 red 2 orange 3 yellow 4 green 5 teal 6 blue 7 purple 8 pink 9 black
        uint24[10] memory p = [0xf4f4f4, 0xe5484d, 0xf5873a, 0xf6c945, 0x46c26a, 0x22b5a8, 0x3c7be8, 0x8e5cf0, 0xf06fb0, 0x3a3a46];
        return p[i];
    }

    function _colName(uint256 i) private pure returns (string memory) {
        string[10] memory n = ["White", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink", "Black"];
        return n[i];
    }

    function _bg(uint256 i) private pure returns (string memory) {
        string[10] memory b = ["#e6dcff", "#f2e3d0", "#ffd8e6", "#cdf0de", "#ffe0cc", "#fff2b8", "#d6ecff", "#dff5c8", "#f8d8ff", "#cfeff5"];
        return b[i];
    }

    function _hex(uint256 rgb) private pure returns (string memory) {
        bytes memory h = "0123456789abcdef";
        bytes memory o = new bytes(7);
        o[0] = "#";
        for (uint256 i = 0; i < 6; i++) o[6 - i] = h[(rgb >> (4 * i)) & 0xf];
        return string(o);
    }

    /// fixed-point milli value -> "0.123"
    function _dec(uint256 milli) private pure returns (string memory) {
        uint256 f = milli % 1000;
        string memory fs = f < 10 ? string.concat("00", f.toString()) : f < 100 ? string.concat("0", f.toString()) : f.toString();
        return string.concat((milli / 1000).toString(), ".", fs);
    }

    /// tint filter: out = color * (0.35 + 0.8 * luminance)
    function _filter(string memory id, uint256 rgb) private pure returns (string memory) {
        string memory rows;
        for (uint256 s = 16; ; s -= 8) {
            uint256 c = (rgb >> s) & 0xff;
            string memory k = _dec((c * 800) / 765);
            rows = string.concat(rows, k, " ", k, " ", k, " 0 ", _dec((c * 350) / 255), " ");
            if (s == 0) break;
        }
        return string.concat(
            '<filter id="', id, '" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="',
            rows, '0 0 0 1 0"/></filter>'
        );
    }

    // ------------------------------------------------------------ images

    function _png(uint256 i) private view returns (string memory) {
        uint256 off = (uint256(uint8(IDX[i * 4])) << 8) | uint8(IDX[i * 4 + 1]);
        uint256 len = (uint256(uint8(IDX[i * 4 + 2])) << 8) | uint8(IDX[i * 4 + 3]);
        bytes memory b = new bytes(len);
        address d = data;
        assembly {
            extcodecopy(d, add(b, 32), add(off, 1), len)
        }
        return Base64.encode(b);
    }

    function _img(uint256 i, string memory extra) private view returns (string memory) {
        return string.concat(
            '<image width="64" height="64" image-rendering="optimizeSpeed" style="image-rendering:pixelated" ', extra,
            ' xlink:href="data:image/png;base64,', _png(i), '"/>'
        );
    }

    /// accessory = tinted part + fixed part (outlines, lenses), optionally moved per animal
    function _acc(uint256 base, uint256 style, string memory fid, string memory xf) private view returns (string memory) {
        uint256 i = base + (style - 1) * 2;
        return string.concat(
            "<g", bytes(xf).length > 0 ? string.concat(' transform="', xf, '"') : "", ">",
            _img(i, string.concat('filter="url(#', fid, ')"')), _img(i + 1, ""), "</g>"
        );
    }

    function _svg(Moment memory m, string memory hms, string memory date, uint8 tier, bool genesis, uint256 tokenId)
        private view returns (string memory s)
    {
        s = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 400 400" shape-rendering="crispEdges">',
            "<defs>", _filter("h", _col(m.cHat)), _filter("e", _col(m.cEyes)), _filter("n", _col(m.cNeck)), "</defs>",
            '<rect width="400" height="400" fill="', _bg(m.bg), '"/>',
            '<g transform="translate(24 48) scale(5.5)">', _img(m.animal, "")
        );
        // per-animal fit: snake (5) and monkey (8) have taller heads
        if (m.neck > 0) s = string.concat(s, _acc(20, m.neck, "n", ""));
        if (m.hat > 0) {
            string memory xf = m.animal == 5
                ? "translate(0 -9.4) translate(32 30) scale(1.15) translate(-32 -30)"
                : m.animal == 8 ? "translate(0 -7.5)" : "";
            s = string.concat(s, _acc(12, m.hat, "h", xf));
        }
        if (m.eyes > 0) {
            string memory xe = m.animal == 5 ? "translate(0 -6.6) translate(32 41) scale(1.1) translate(-32 -41)" : "";
            s = string.concat(s, _acc(16, m.eyes, "e", xe));
        }
        s = string.concat(s, "</g>", _header(genesis, tokenId, hms, date, tier), _lcd(hms, m.lcd), "</svg>");
    }

    function _header(bool genesis, uint256 tokenId, string memory hms, string memory date, uint8 tier)
        private pure returns (string memory h)
    {
        h = string.concat(
            '<g font-family="monospace" font-weight="bold" fill="#3f3a4a"><text x="14" y="24" font-size="13">',
            genesis ? string.concat("GENESIS #", tokenId.toString()) : "TIME CARDS",
            '</text><text x="14" y="42" font-size="11">', date, " ", hms, "</text></g>"
        );
        if (tier > 0) {
            string[4] memory pc = ["", "#2f6fe0", "#8b4de0", "#c48a00"];
            h = string.concat(
                h, '<rect x="296" y="10" width="92" height="22" rx="11" fill="', pc[tier],
                '"/><text x="342" y="26" text-anchor="middle" font-family="monospace" font-weight="bold" font-size="12" fill="#fff">',
                _tierName(tier), "</text>"
            );
        }
        if (tier == 3) {
            h = string.concat(h, '<rect x="3" y="3" width="394" height="394" rx="10" fill="none" stroke="#f2bc23" stroke-width="6"/>');
        }
    }

    function _lcd(string memory hms, uint256 c) private pure returns (string memory) {
        string memory col = (c == 0 || c == 9) ? "#7cf0b0" : _hex(_col(c));
        string memory chain;
        for (uint256 y = 326; y < 348; y += 6) {
            chain = string.concat(chain, '<rect x="197" y="', y.toString(), '" width="6" height="4" fill="#cdaa3c"/>');
        }
        return string.concat(
            chain,
            '<rect x="126" y="348" width="148" height="44" fill="#2b2d3a"/><rect x="130" y="352" width="140" height="36" fill="#11131c"/>',
            _text(hms, 138, 360, 4, col)
        );
    }

    // ------------------------------------------------------------ pixel font

    function _tierName(uint8 tier) private pure returns (string memory) {
        if (tier == 3) return "LEGENDARY";
        if (tier == 2) return "EPIC";
        if (tier == 1) return "RARE";
        return "COMMON";
    }

    function _two(uint256 v) private pure returns (string memory) {
        return v < 10 ? string.concat("0", v.toString()) : v.toString();
    }

    function _glyph(bytes1 c) private pure returns (uint16) {
        if (c == "0") return 0x7B6F;
        if (c == "1") return 0x2C97;
        if (c == "2") return 0x73E7;
        if (c == "3") return 0x73CF;
        if (c == "4") return 0x5BC9;
        if (c == "5") return 0x79CF;
        if (c == "6") return 0x79EF;
        if (c == "7") return 0x7292;
        if (c == "8") return 0x7BEF;
        if (c == "9") return 0x7BCF;
        if (c == ":") return 0x0410;
        return 0;
    }

    function _text(string memory s, uint256 x, uint256 y, uint256 px, string memory col) private pure returns (string memory out) {
        bytes memory b = bytes(s);
        string memory p = px.toString();
        for (uint256 i = 0; i < b.length; i++) {
            uint16 g = _glyph(b[i]);
            for (uint256 k = 0; k < 15; k++) {
                if ((g >> (14 - k)) & 1 == 1) {
                    out = string.concat(
                        out, '<rect x="', (x + (k % 3) * px).toString(), '" y="', (y + (k / 3) * px).toString(),
                        '" width="', p, '" height="', p, '" fill="', col, '"/>'
                    );
                }
            }
            x += 4 * px;
        }
    }
}
