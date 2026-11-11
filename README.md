# TIME CARDS

**Every second is a card.** TIME CARDS is a fully on-chain NFT collection deployed on **BNB Chain — BNB Smart Chain (BSC) mainnet, chainId 56**. Each token ID is a real Unix timestamp, and the SVG art is generated on-chain from that moment.

- Website: https://timecards-21h.pages.dev/
- X: https://x.com/PipAgentWorld

## Deployment (BNB Smart Chain mainnet)

| Contract | Address |
|---|---|
| TimeCards (ERC-721, main) | [`0xc5624B61beE1971E6Aa3AB5f403236Ab32C2B6cd`](https://bscscan.com/address/0xc5624B61beE1971E6Aa3AB5f403236Ab32C2B6cd) |
| TimeCardsArt (on-chain SVG renderer) | [`0xFcBF55830175589Ecba014f75BE507E7835cF585`](https://bscscan.com/address/0xFcBF55830175589Ecba014f75BE507E7835cF585) |
| Art data | [`0x03666Aa06FC991904991E9C73C71816E3b8B2983`](https://bscscan.com/address/0x03666Aa06FC991904991E9C73C71816E3b8B2983) |

Network config: [`bnbconfig.json`](bnbconfig.json), [`hardhat.config.js`](hardhat.config.js), [`deployments/bsc-mainnet.json`](deployments/bsc-mainnet.json).
Source is verified on BscScan and Sourcify.

## How it works

- Each card is one second; its token ID is that timestamp.
- The zodiac animal, accessories and tier come from the moment itself, in Beijing time: `00:00:00` is Legendary, repeating or palindrome times like `11:11:11` are Epic, three matching digits are Rare.
- **Genesis:** all 2,000 free cards were claimed after opening on Nov 9, 2026.
- **Moments:** from Nov 12, 2026 13:09:20 UTC a new moment is released every 20 seconds, and the gap doubles each quarter for one year.
- Each moment can be minted for only 10 minutes after release, paid in BNB on BSC. Holders get the first 5 minutes at 0.0005 BNB, then 0.001 BNB for everyone.
- 100% on-chain SVG art. No owner, no pause, no admin keys. 1% royalty.

## Contracts

- `contracts/TimeCards.sol` — ERC-721 collection, mint windows and pricing in BNB.
- `contracts/TimeCardsArt.sol` — on-chain SVG / metadata renderer.

Compiler: Solidity 0.8.24, optimizer 200 runs, viaIR, EVM `paris`.

```bash
npm install
npx hardhat compile
```

## License

MIT
