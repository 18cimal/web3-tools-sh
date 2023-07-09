# web3-tools.sh

Bash script with some useful tools for Web3 / Ethereum.

## Features
- Get the ETH or ERC-20 token balance of an address
- Resolve and reverse resolve ENS address
- Get the next block gas price
- Get info about an ERC-20 token
- Get a quote for a Uniswap swap
- Get the price of an asset from Chainlink oracle
- keccak-256 (web3 sha3) hash
- Convert between ether and wei

## Requirements  
- `bash 4.0+`
- `jq` for token list parsing and gas price
- `curl` for rpc calls
- `gawk` (GNU awk with -M option) for hex numbers greater than 64 bit
- `keccak-256sum` from https://codeberg.org/maandree/sha3sum for ENS resolving, fallback to using web3_sha3 rpc call if not installed

## Usage
The script is made to be sourced, then the commands can be called directly in the terminal:

```
$ source web3-tools.sh
$ [command] [args...] [-r RPC URL]
```
Or it can also be used directly:
```
./web3-tools.sh [command] [args...] [-r RPC URL]

options:
  -r <RPC URL>       RPC URL to get blockchain data (default: http://localhost:8545)
```
The default RPC URL is set to `http://localhost:8545` and can be edited by changing `ETH_RPC_URL` at the top of the script.

Positional arguments need to be specified *before* optional arguments. Unless indicated otherwise, the positional arguments are mandatory.

For the commands using ERC-20 tokens a token list is needed to map the token symbol to their address. See the [Token list](#token-list) section.

## Commands
### **bal**
Get ETH or ERC-20 token balance of an address.

The token address/symbol argument is optional and when not set it will get the native token balance.

Uses [Token list](#token-list) for ERC-20 token symbols.

The `-a` option will get the balances for all tokens from the token list (only non-zero balances are printed). Not recommended to use with the Coingecko list as it will take a long time (~4000 tokens).
```
usage: bal [address or ENS name] [token address or symbol] [-l token_list] [-i token_index] [-n network] [-a] [-r RPC URL]

options:
  -l, -i, -n         Same as erc20 command
  -a                 Get balances from all tokens from token list
```

### **ens**
Resolve ENS address or reverse resolve ETH address.

Only works on mainnet.

This command is using keccak to hash the name and convert the address to the checksummed version. If the `keccak-256sum` command is not installed it will fall back to using the `web3_sha3` rpc call which is slower (especially when using a remote RPC). See [keccak](#keccak) section.

There is no normalization done on the name except for putting it in lowercase, so it might not work with names containing special characters.

The `-C` option disables the checksumming of the output address. It's used internally when the ens command is called to save time.
```
usage: ens [ENS name or address] [-r RPC URL]

options:
  -C                 Disable checksumming of output address
```

### **gas**
Get the next block gas price.
  
Makes one RPC call `eth_getBlockByNumber` to get the latest block information and use the base fee and gas usage to calculate the next block base fee.

The priority fee is estimated by taking the lowest priority fee paid in the latest block. This could be inaccurate if there are transactions paying too low fees. By default, a minimum of 1 gwei is applied to the returned value.
```
usage: gas [-d] [-w] [-p min priority fee] [-r RPC URL]

options:
  -d                 Output comma-separated Base Fee and Priority Fee
  -w                 Output in wei
  -p <min_prio_fee>  Minimum priority fee in gwei to apply to output (default: 1 gwei)
```

### **erc20**
Get ERC-20 token info: name, token symbol, address and number of decimals.

Uses [Token list](#token-list) for ERC-20 token symbols.

The `-a` option prints all token symbols from the token list. When used the first positional argument still need to be set (can be empty string).
```
usage: erc20 [address or symbol] [-l token_list] [-i token_index] [-n network] [-a] [-r RPC URL]

options:
  -l <token_list>    Path to json token list (default: ~/.config/tokens.json or tokens.json in the same directory as the script)
  -i <token_index>   Index in token list for tokens with same symbol (starting from zero)
  -n <network>       Name of network in token list (default: ethereum)
  -a                 Show all tokens in token list
  -c                 Compact output, null separated (used internally by bal and uni command)
```

### **uni**
Get a swap quote from Uniswap v3.

Uses [Token list](#token-list) for ERC-20 token symbols.

Supports both "sell exact" and "buy exact" by using the order of the arguments. No multi-hop routing is done so it only works with token pairs where a direct pool exists.
By default, it will use the 0.3% fee pool. To get a quote from other fee tier pools use the `-f` option with `0.01`, `0.05` or `1` value.

Additional supported networks are `arbitrum`, `optimism`, `polygon` and `bsc` (addresses of quoter contract are set for those networks).
```
usage: uni [amount to sell] [sell token] [buy token] [-f fee] [-l token_list] [-i token_index] [-I token_index] [-n network] [-r RPC URL]
  or   uni [sell token] [amount to buy] [buy token]  ...

options:
  -l, -i, -n         Same as erc20 command
  -I <token_index>   Same as -i but for buy token
  -f <fee>           Pool fee in percent (default: 0.3)
```

### **chainlink**
Get prices from chainlink oracles. See https://data.chain.link for the available oracle price feeds.

Input can be a pair like `eth-usd` or `eth/btc` (case insensitive). It works for oracles with an ENS name in the format `xxx-yyy.data.eth`. When only one asset is specified the other is set to USD.

The input can also be the address of the oracle contract for feeds without an ENS name (non mainnet).
```
usage: chainlink [pair, coin or address] [-r RPC URL]
```

### **keccak**
keccak 256 hash (web3 sha3)

Using the `keccak-256sum` command from https://codeberg.org/maandree/sha3sum. If it's not installed it will fall back to using the `web3_sha3` RPC call which is slower (especially when using a remote RPC).

This command is used multiple times in the ENS resolution command for name hashing and address checksumming.
```
usage: keccak [data] [-x] [-r RPC URL]

options:
  -x                 Convert input from hexadecimal
```

### **toWei** and **fromWei**
Convert between ether and wei.

The number of decimals argument is optional. The default is 18. It needs to be set for tokens with a different number of decimals (like USDC or WBTC) to convert between base unit and decimal unit.

If the input is a hexadecimal number starting with 0x it will be converted to decimal. For the `toWei` command the `-x` option is used to convert the output to hexadecimal.
The hexadecimal/decimal conversion is using bash built-in `printf` when the number is less than 64 bit and `gawk` with `-M` option when the number is bigger.
The functions can be used just for hexadecimal/decimal conversion by using 0 for the number of decimals.
```
usage: toWei   [number] [number of decimals] [-x]
       fromWei [number] [number of decimals]
  
options:
  -x                 Convert output to hexadecimal
```

## Token list
To be able to use token symbols for `erc20`, `bal` and `uni` commands a token list is needed to map the token symbols to their address.

The default is to look for the file `~/.config/tokens.json` then for the file `tokens.json` in the same directory as the script. The default file path can be edited at the top of the `erc20` function in the script.

An example token list is provided with some common tokens (WETH, USDC, USDT, DAI, WBTC). The token addresses were sourced from Coingecko.

The file is in json with the format:
```
{
  "ethereum": {
    "WETH": {
      "address": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
      "decimals": 18,
      "symbol": "WETH"
    },
    ...
  }
}
```
The top level key is the name of the network. The key for the token symbol needs to be in uppercase. Only the `address` field is mandatory. If the `decimals` field is not present it will be looked up onchain. The `symbol` field can be used for tokens that are not all uppercase so they're displayed correctly.

### Coingecko token list
The token list from Coingecko is also supported. You can download it using:

`curl -Ls 'https://api.coingecko.com/api/v3/coins/list?include_platform=true' | jq > coingecko.json`

The Coingecko list has some tokens which are using the same symbol so for those you need to specify which one to select using the `-i` option (starting with 0).

## Support for other networks
The script supports other networks by using the `-r RPC_URL` option argument or editing the default RPC URL.

The commands which need token symbol to address mapping also need to use the `-n` option to specify the name of the network to lookup in the token list.

`arbitrum`, `optimism`, `polygon` and `bsc` are supported but other networks can be used as long as the name is the same as the one in the token list.

The `ens` command only works on mainnet.

The `uni` command supports `arbitrum`, `optimism`, `polygon` and `bsc` (addresses of quoter contract are set for those networks).

The `bal` command will correctly display the native token for `polygon` and `bsc`. For other networks with native token different than ETH it will still work but the native token with be shown as ETH.

For the `chainlink` command using the asset name only works on mainnet because it's using ENS resolution. For other networks, the address of the oracle contract needs to be used.

## Limitations
- token symbol starting with -l, -i, -n, -a or -r in bal command
- token symbol is the same as the native token in bal command
- gas price greater than signed 64 bit integer (9223372036 gwei)
- ens names with non ascii chars when using web3_sha3 from RPC
- non normalized ens names
