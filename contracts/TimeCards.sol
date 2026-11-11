// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

interface ITimeCardsArt {
    function tokenURI(uint256 tokenId, uint256 t, uint8 tier, bool genesis) external view returns (string memory);
}

interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title TIME CARDS
/// @notice Every card is a moment in time, drawn fully on-chain.
///  Phase 1 (72h): 2,000 free Genesis cards, one per wallet, stamped with the claim time.
///  Phase 2 (1 year): one moment released every 20s, interval doubles each quarter (20/40/80/160s).
///  Art: zodiac animal by Beijing hour, accessories and colors from the date/time digits.
///  Each moment can be minted for 10 minutes after it is released; the first 5 minutes are
///  reserved for Genesis holders. Unminted moments are gone forever.
///  Rarity comes from the digits of the Beijing time (UTC+8): 3 same in a row = Rare,
///  4 same in a row or a palindrome = Epic, 00:00:00 = Legendary.
///  No owner, no admin, no pause, no withdraw. Payments go straight to the creator.
contract TimeCards is ERC721, ERC2981 {
    // ---- fixed rules ----
    IAgentID public constant AGENT_ID = IAgentID(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);
    uint256 public constant FREE_SUPPLY = 2000;
    uint256 public constant FREE_DURATION = 72 hours;
    uint256 public constant QUARTER = 7_884_000; // 91.25 days
    uint256 public constant QUARTERS = 4;
    uint256 public constant BASE_INTERVAL = 20; // seconds
    uint256 public constant MINT_WINDOW = 10 minutes;
    uint256 public constant HOLDER_WINDOW = 5 minutes;
    uint256 public constant PRICE = 0.001 ether;
    uint256 public constant HOLDER_PRICE = 0.0005 ether;
    uint256 public constant TZ_OFFSET = 8 hours; // Beijing time

    address payable public immutable creator;
    ITimeCardsArt public immutable ART;
    uint256 public immutable freeStart;
    uint256 public immutable dripStart;
    uint256 public immutable dripEnd;

    // ---- state ----
    uint256 public freeMinted;
    uint256 public dripMinted;
    mapping(address => bool) public claimedFree;
    mapping(uint256 => uint256) private _freeTime; // genesis id => timestamp
    mapping(address => uint256) public genesisHeld;

    error NotAgent();
    error FreeClosed();
    error AlreadyClaimed();
    error FreeSoldOut();
    error NotASlot();
    error NotReleased();
    error Expired();
    error AlreadyMinted();
    error HoldersOnly();
    error WrongPayment();
    error PayFailed();

    event GenesisClaimed(address indexed to, uint256 indexed tokenId, uint256 time);
    event MomentMinted(address indexed to, uint256 indexed time, uint8 tier, uint256 paid);

    /// @param creator_ wallet that receives every payment and the 1% royalty
    /// @param start_ unix time the free phase opens (0 = at deploy)
    /// @param art_ the on-chain renderer (fixed forever)
    constructor(address payable creator_, uint256 start_, address art_) ERC721("TIME CARDS", "TIME") {
        require(creator_ != address(0), "creator");
        require(art_.code.length > 0, "art");
        ART = ITimeCardsArt(art_);
        creator = creator_;
        uint256 s = start_ == 0 ? block.timestamp : start_;
        require(s >= block.timestamp, "start in past");
        freeStart = s;
        // align the clock to a 160s grid so every slot lands on :00/:20/:40 and hits midnight
        uint256 ds = ((s + FREE_DURATION + 159) / 160) * 160;
        dripStart = ds;
        dripEnd = ds + QUARTER * QUARTERS;
        _setDefaultRoyalty(creator_, 100); // 1%
    }

    modifier onlyAgent() {
        if (AGENT_ID.balanceOf(msg.sender) == 0) revert NotAgent();
        _;
    }

    // ---------------- phase 1: free genesis ----------------

    function claimFree() external onlyAgent {
        if (block.timestamp < freeStart || block.timestamp >= freeStart + FREE_DURATION) revert FreeClosed();
        if (claimedFree[msg.sender]) revert AlreadyClaimed();
        if (freeMinted >= FREE_SUPPLY) revert FreeSoldOut();
        claimedFree[msg.sender] = true;
        uint256 id = ++freeMinted;
        _freeTime[id] = block.timestamp;
        _mint(msg.sender, id);
        emit GenesisClaimed(msg.sender, id, block.timestamp);
    }

    // ---------------- phase 2: the clock ----------------

    /// @notice interval (seconds) in force at time t, or 0 outside the drip year
    function intervalAt(uint256 t) public view returns (uint256) {
        if (t < dripStart || t >= dripEnd) return 0;
        return BASE_INTERVAL << ((t - dripStart) / QUARTER);
    }

    function isSlot(uint256 t) public view returns (bool) {
        uint256 iv = intervalAt(t);
        if (iv == 0) return false;
        uint256 q = (t - dripStart) / QUARTER;
        return (t - dripStart - q * QUARTER) % iv == 0;
    }

    /// @notice the newest released moment at or before now (0 if none yet / finished)
    function latestSlot() public view returns (uint256) {
        uint256 t = block.timestamp;
        if (t < dripStart) return 0;
        if (t >= dripEnd) t = dripEnd - 1;
        uint256 q = (t - dripStart) / QUARTER;
        uint256 qs = dripStart + q * QUARTER;
        uint256 iv = BASE_INTERVAL << q;
        return qs + ((t - qs) / iv) * iv;
    }

    /// @notice price this wallet pays for a moment right now
    function priceFor(address who) public view returns (uint256) {
        return genesisHeld[who] > 0 ? HOLDER_PRICE : PRICE;
    }

    /// @notice mint the moment `t` (a unix timestamp on the grid). tokenId == t.
    function mint(uint256 t) external payable onlyAgent {
        if (!isSlot(t)) revert NotASlot();
        if (block.timestamp < t) revert NotReleased();
        if (block.timestamp >= t + MINT_WINDOW) revert Expired();
        if (_ownerOf(t) != address(0)) revert AlreadyMinted();
        bool holder = genesisHeld[msg.sender] > 0;
        if (block.timestamp < t + HOLDER_WINDOW && !holder) revert HoldersOnly();
        uint256 price = holder ? HOLDER_PRICE : PRICE;
        if (msg.value != price) revert WrongPayment();
        unchecked { ++dripMinted; }
        _mint(msg.sender, t);
        emit MomentMinted(msg.sender, t, tierOf(t), price);
        (bool ok, ) = creator.call{value: msg.value}("");
        if (!ok) revert PayFailed();
    }

    // ---------------- views ----------------

    function totalSupply() external view returns (uint256) {
        return freeMinted + dripMinted;
    }

    function timeOf(uint256 tokenId) public view returns (uint256) {
        _requireOwned(tokenId);
        return tokenId <= FREE_SUPPLY ? _freeTime[tokenId] : tokenId;
    }

    /// @notice 0 Common, 1 Rare, 2 Epic, 3 Legendary — from the Beijing-time digits of t
    function tierOf(uint256 t) public pure returns (uint8) {
        uint256 sod = (t + TZ_OFFSET) % 86400;
        if (sod == 0) return 3;
        uint8[6] memory d = _digits(sod);
        uint256 run = 1;
        uint256 best = 1;
        for (uint256 i = 1; i < 6; i++) {
            run = d[i] == d[i - 1] ? run + 1 : 1;
            if (run > best) best = run;
        }
        bool pal = d[0] == d[5] && d[1] == d[4] && d[2] == d[3];
        if (best >= 4 || pal) return 2;
        if (best == 3) return 1;
        return 0;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        uint256 t = timeOf(tokenId);
        return ART.tokenURI(tokenId, t, tierOf(t), tokenId <= FREE_SUPPLY);
    }

    function supportsInterface(bytes4 id) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(id);
    }

    // ---------------- internals ----------------

    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = super._update(to, tokenId, auth);
        if (tokenId <= FREE_SUPPLY) {
            if (from != address(0)) genesisHeld[from] -= 1;
            if (to != address(0)) genesisHeld[to] += 1;
        }
    }

    function _digits(uint256 sod) private pure returns (uint8[6] memory d) {
        uint256 h = sod / 3600;
        uint256 m = (sod % 3600) / 60;
        uint256 s = sod % 60;
        d[0] = uint8(h / 10); d[1] = uint8(h % 10);
        d[2] = uint8(m / 10); d[3] = uint8(m % 10);
        d[4] = uint8(s / 10); d[5] = uint8(s % 10);
    }
}
