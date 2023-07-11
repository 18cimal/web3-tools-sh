#!/usr/bin/env bash

########################################
## Useful tools for Web3 / Ethereum:  ##
##  - resolve ENS name                ##
##  - balance of address              ##
##  - ERC-20 token info               ##
##  - Chainlink price oracle          ##
##  - Uniswap v3 quote                ##
##  - next block gas price            ##
##  - keccak 256 hash                 ##
##  - convert between ether and wei   ##
########################################

ETH_RPC_URL='http://localhost:8545'

# get ERC-20 token info
# usage: erc20 [address or symbol] [-l token_list] [-i token_index] [-n network] [-a] [-c] [-r RPC URL]
# default token list path and network name are set here
erc20() {
    local token_list=~/.config/tokens.json # default token list path
    local net='ethereum'                   # default network

    local rpc="$ETH_RPC_URL"
    local token_index='' # used when multiple tokens with same symbol in list 
    local compact=''     # only print symbol, address and decimals
    local symbol=''
    local all=''
    local decimals='null'
    local address="$1"
    shift
    local opt OPTIND OPTARG
    while getopts ":l:i:n:r:ac" opt; do
        case $opt in
            l) [ "$OPTARG" ] && token_list="$OPTARG" ;;
            i) token_index="$OPTARG" ;;
            n) [ "$OPTARG" ] && net="${OPTARG,,}" ;;
            r) [ "$OPTARG" ] && rpc="${OPTARG}" ;;
            a) all=1 ;;
            c) compact=1 ;;
            :)  { echo "Option -$OPTARG requires an argument." >&2; return 1; } ;;
            \?) { echo "Invalid option!: -$OPTARG" >&2 ; return 1; } ;;
        esac
    done

    # lookup token from list
    if [ "${address:0:2}" != 0x -o "${#address}" -ne 42 ]; then
        symbol="${address}"
        [ "$symbol" == "${symbol,,}" ] && symbol="${symbol^^}"
        if [ ! -f "$token_list" ]; then
            # auto set token list to file in same directory
            local token_list_name='tokens.json'
            if [[ "$0" == */* ]]; then
                token_list="${0%/*}/$token_list_name"
            elif [ "$BASH_SOURCE" = "$0" ]; then
                token_list="$token_list_name"
            fi
            [ -f "$token_list" ] || { >&2 echo "error: token list file '$token_list' doesn't exist"; return 1; }
        fi
        local list_type='{'
        read -n1 list_type < "$token_list" # read first char to find list type
        local filter='if has("symbol") then . else .symbol="" end'
        if [ "$list_type" = '{' ]; then
            filter=".\"${net}\".\"${symbol^^}\"|${filter}|"'"\(.address)\u0000\(.decimals)\u0000\(.symbol)"'
        else # coingecko list
            case "$net" in # network names for coingecko list
                optimism) net='optimistic-ethereum' ;;
                arbitrum) net='arbitrum-one' ;;
                polygon) net='polygon-pos' ;;
                bsc) net='binance-smart-chain' ;;
            esac
            filter='.[]|select(.symbol=="'"${symbol,,}"'" and .platforms."'$net'")|"\(.platforms."'$net'")\u0000null\u0000\u0000"'
        fi

        # all mode: return list of all tokens symbols
        if [ "$all" ]; then
            if [ "$list_type" = '{' ]; then
                filter='."'$net'" | keys |'
            else
                filter='[.[]|select(.platforms."'$net'" and .platforms."'$net'"!="")|.symbol]|sort|'
            fi
            if [ "$compact" ]; then
                jq -j "$filter"'join("\u0000")' "$token_list"
                printf '\0'
            else
                jq -r "$filter"'.[]' "$token_list"
            fi
            return 0
        fi

        local data
        readarray -t -d '' data < <(jq -j "$filter" "$token_list")
        if [ -z "$data" -o "$data" = null ]; then
            >&2 echo "error: token '$symbol' not found in tokens list $token_list for network $net"
            return 1
        elif [ "${data[3]}" -a -z "$token_index" ]; then
            >&2 echo "warning: multiple tokens with symbol $symbol in list ${token_list}, using first one."
        elif [ -z "${data[((${token_index:-0}*3+0))]}" ]; then
            >&2 echo "error: no token $symbol with index $token_index in $token_list"
            return 1
        fi
        token_index="${token_index:-0}"
        address=${data[((${token_index}*3+0))]}
        decimals=${data[((${token_index}*3+1))]}
        [ "${data[((${token_index}*3+2))]}" ] && symbol="${data[((${token_index}*3+2))]}"
    fi

    # get symbol and name
    local symbol_name=("$symbol" '')
    local i=0
    for method in 0x95d89b41 0x06fdde03; do # symbol and name methods
        # skip if symbol or name is not requested
        [ "$method" = 0x95d89b41 -a "$symbol" -a "$compact" ] || [ "$method" = 0x06fdde03 -a "$compact" ] && continue
        local params='{"id":1,"method":"eth_call","params":[{"to":"'${address}'","data":"'$method'"},"latest"]}'
        local data=$(curl -Ls "$rpc" --json "$params")
        [ -z "$data" ] && { >&2 echo -e "error: connecting to rpc url $rpc\nparams: $params"; return 1; }
        data=${data##*\"0x}
        data=${data:128:-2}
        local hexstr=''
        local j=0
        local c=${data:$((2*$j)):2}
        while [ "$c" -a "$c" != 00 ]; do
            hexstr=${hexstr}'\x'$c
            ((j++))
            c=${data:$((2*$j)):2}
        done
        symbol_name[$i]="$(printf $hexstr)"
        ((i++))
    done
    symbol="${symbol_name[0]//\\/\\\\}" # escape backslashes
    local name="${symbol_name[1]//\\/\\\\}"

    # get decimals
    if [ "$decimals" = null -o -z "$compact" ]; then
        local params='{"id":1,"method":"eth_call","params":[{"to":"'${address}'","data":"0x313ce567"},"latest"]}'
        local data=$(curl -Ls "$rpc" --json "$params")
        [ -z "$data" ] && { >&2 echo -e "error: connecting to rpc url $rpc\nparams: $params"; return 1; }
        decimals=$(fromWei "${data: -68:66}" 0)
    fi
    
    if [ "$compact" ]; then
        echo -ne "${symbol}\x00${address}\x00${decimals}"
    else
        echo -e "name: ${name}\nsymbol: ${symbol}\naddress: ${address}\ndecimals: ${decimals}"
    fi
}

# keccak 256 hash (web3 sha3)
# usage: keccak [data] [-x] [-r RPC URL]
keccak() {
    local data="$1"
    local rpc="$ETH_RPC_URL"
    local hex=''
    local hash=''
    local i
    for i in "$2" "$3" "$4"; do
        case "${i:0:2}" in
            -x) hex=1 ;;
            -r) [ "${i:2}" ] && rpc="${i:2}" ;;
            *) [ "$i" ] && rpc="$i" ;;
        esac
    done

    # try keccak-256sum command
    if [ "$hex" ]; then
        hash=$(echo -n "$data" | keccak-256sum -x 2>/dev/null)
    else
        hash=$(echo -n "$data" | keccak-256sum 2>/dev/null)
    fi
    if [ $? -ne 127 -a "$hash" ]; then
        echo ${hash%% *}
    else # fallback to web3_sha3 from rpc
        if [ -z "$hex" ]; then
            for (( i=0; i<${#data}; i++ )); do
                hex=${hex}$(printf %x "'${data:$i:1}")
            done
            data=$hex
        fi
        local params='{"id":1,"method":"web3_sha3","params":["0x'$data'"]}'
        hash=$(curl -Ls "$rpc" --json "$params")
        [ -z "$hash" ] && { >&2 echo -e "error: connecting to rpc url $rpc\nparams: $params"; return 1; }
        echo ${hash: -66:64}
    fi
}

# resolve ENS address or reverse resolve ETH address
# usage: ens [ENS name or address] [-C] [-r RPC URL]
ens() {
    local name="${1,,}"
    local rpc="$ETH_RPC_URL"
    local checksum=1
    local reverse=''
    local i
    for i in "$2" "$3" "$4"; do
        case "${i:0:2}" in
            -C) checksum='' ;;
            -r) [ "${i:2}" ] && rpc="${i:2}" ;;
            *) [ "$i" ] && rpc="$i" ;;
        esac
    done

    # get namehash
    local namehash='0000000000000000000000000000000000000000000000000000000000000000'
    if [[ "$name" != *.* ]]; then # reverse resolve, use pre hashed addr.reverse
        namehash='91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2'
        name="${name:2}"
        reverse=1
    elif [ "${name: -9}" = .data.eth ]; then # use pre hashed data.eth for chainlink oracles
        namehash='4a9dd6923a809a49d009b308182940df46ac3a45ee16c1133f90db66596dae1f'
        name="${name%.data.eth}"
    elif [ "${name: -4}" = .eth ]; then # use pre hashed keccak('0' * 32 + keccak('eth'))
        namehash='93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae'
        name="${name%.eth}"
    fi
    name=(${name//./ }) # put name in array
    for ((i=${#name[@]}-1; i>=0; i--)); do # go through array in reverse
        namehash=$(keccak ${namehash}$(keccak "${name[$i]}" -r "$rpc") -x -r "$rpc")
    done

    # get resolver
    local registry='0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e'
    local params='{"id":1,"method":"eth_call","params":[{"to":"'$registry'","data":"0x0178b8bf'$namehash'"},"latest"]}'
    local data=$(curl -Ls "$rpc" --json "$params")
    [ -z "$data" ] && { >&2 echo -e "error: connecting to rpc url $rpc\nparams: $params"; return 1; }
    local resolver=0x${data: -42:40}
    [ "$resolver" = 0x0000000000000000000000000000000000000000 ] && return 0

    if [ -z "$reverse" ]; then
        # eth_call to resolver with 'addr' method selector
        params='{"id":1,"method":"eth_call","params":[{"to":"'$resolver'","data":"0x3b3b57de'$namehash'"},"latest"]}'
        data=$(curl -Ls "$rpc" --json "$params")
        [ -z "$data" ] && { >&2 echo -e "error: connecting to rpc url $rpc\nparams: $params"; return 1; }
        [ "${data: -2:1}" = '}' ] && { >&2 echo -e "error: resolver contract\n$data"; return 1; } 
        data=${data: -42:40}
        [ "$data" = 0000000000000000000000000000000000000000 ] && return 0

        if [ "$checksum" ]; then
            # checksum address
            local h=$(keccak "$data" -r "$rpc")
            local address='0x'
            for i in {0..39}; do
                local c=${data:$i:1}
                if (( 0x${h:$i:1} > 7 )); then
                    address=${address}${c^}
                else
                    address=${address}${c}
                fi
            done
            echo $address
        else
            echo "0x$data"
        fi
    else # reverse resolve using 'name' method
        params='{"id":1,"method":"eth_call","params":[{"to":"'$resolver'","data":"0x691f3431'$namehash'"},"latest"]}'
        data=$(curl -Ls "$rpc" --json "$params")
        [ -z "$data" ] && { >&2 echo -e "error: connecting to rpc url $rpc\nparams: $params"; return 1; }
        data=${data##*\"0x}
        data=${data:128:-2}
        [ -z "$data" ] && return 0
        local ens_name=''
        i=0
        local c=${data:$((2*$i)):2}
        while [ "$c" -a "$c" != 00 ]; do
            ens_name=${ens_name}'\x'$c
            ((i++))
            c=${data:$((2*$i)):2}
        done
        ens_name=$(printf "$ens_name")
        [ "$(ens "$ens_name" -C -r "$rpc")" = "0x$name" ] && echo "$ens_name" # check forward resolution
    fi
}

# convert from ether to wei
# usage: toWei [number] [number of decimals] [-x]
# number of decimals can be set to support tokens with different number of decimals
# -x option converts to output to hexadecimal
toWei() {
    local num="$1"
    local d=18
    [ "$2" ] && [ "$2" != '-x' ] && { d="$2"; shift; }
    local h="$2"
    
    local dec=''
    [[ "$num" == *.* ]] && dec="${num#*.}"
    num=${num%.*}
    if [ $d -gt 0 ]; then
        while [ ${#dec} -lt $d ]; do
            dec=${dec}0
        done
        num=${num}${dec}
    fi
    while [ "${num:0:1}" = 0 ]; do # remove leading zeroes
        num="${num:1}"
    done
    if [ "$h" ]; then  # convert to hex
        if [ ${#num} -lt 20 ] || [ ${#num} -eq 20 -a ${num:0:10} -le 1844674407 -a ${num:10:10} -le 3709551615 ]; then
            printf '0x%x\n' "$num"
        else # use GNU awk for big numbers
            gawk -M 'BEGIN{printf "0x%x\n", '${num}'}'
        fi
    else
        echo "${num:-0}"
    fi
}

# convert from wei to ether
# usage: fromWei [number] [number of decimals]
# number of decimals can be set to support tokens with different number of decimals
# if input starts with 0x it is converted from hexadecimal
fromWei() {
    local num="$1"
    local d="${2:-18}"

    # convert from hex
    if [ "${num:0:2}" = 0x ]; then
        num="${num:2}"
        # try to trim the value of 48 leading zeroes
        num=${num#000000000000000000000000000000000000000000000000}
        if [ ${#num} -le 16 ]; then # result is under 64 bit, process directly
            num=$(printf %u 0x$num)
        else # use GNU awk for big numbers
            num=$(gawk -M 'BEGIN{printf "%d",0x'$num'}')
        fi
    fi

    [ "$num" = 0 -o "$d" = 0 ] && { echo "$num"; return 0; }

    local dec=''
    local i=1
    local trailing=''
    # build decimal part, skip trailing zeroes
    for ((i=1; i<=${d}; i++)); do
        local c="${num: -$i:1}"
        if [ -z "$c" ]; then
            dec="0$dec"
        elif [ "$trailing" -o "$c" != 0 ]; then
            dec="${c}$dec"
            trailing=1
        fi
    done
    [ "$dec" ] && dec=.$dec
    if [ ${#num} -le $d ]; then
        echo "0${dec}"
    else
        echo "${num:0:-$d}$dec"
    fi
}

# get ETH or ERC-20 token balance of address
# usage: bal [address or ENS name] [token address or symbol] [-l token_list] [-i token_index] [-n network] [-a] [-r RPC URL]
bal() {
    local address="$1"
    local t=''
    case "${2:0:2}" in # check is 2nd arg is the token or an option
        -l|-n|-r) : ;;
        -a) [ "${2:2}" ] && { t="$2"; shift; } ;; 
        -i) [ "${2:2}" -ge 0 ] 2>/dev/null || { t="$2"; shift; } ;;
        *) t="$2"; shift ;;
    esac
    shift
    local token_list=''
    local token_index=''
    local net=''
    local all=''
    local rpc="$ETH_RPC_URL"
    local opt OPTIND OPTARG
    while getopts ":l:i:n:r:a" opt; do
        case $opt in
            l) token_list="$OPTARG" ;;
            i) token_index="$OPTARG" ;;
            n) net="$OPTARG" ;;
            r) [ "$OPTARG" ] && rpc="$OPTARG" ;;
            a) all=1 ;;
            :)  { echo "Option -$OPTARG requires an argument." >&2; return 1; } ;;
            \?) { echo "Invalid option!: -$OPTARG" >&2 ; return 1; } ;;
        esac
    done

    [[ "$address" == *.* ]] && address=$(ens "$address" -C -r "$rpc")
    [ ${#address} -ne 42 ] && { >&2 echo "error: resolved address is invalid '$address'"; return 1; }
    local params='{"id":1,"method":"eth_getBalance","params":["'${address}'","latest"]}'
    local d=18
    local data
    local native_token=ETH
    case "$net" in
        polygon|polygon-pos) native_token=MATIC ;;
        bsc|binance-smart-chain) native_token=BNB ;;
    esac
    [ -z "$t" ] && t="$native_token"

    # all mode: print balance for all tokens
    if [ "$all" ]; then
        bal "$address" "$native_token" -n "$net" -r "$rpc"
        local prev=''
        while IFS= read -r -d $'\0' t; do
            [ "$t" != "$prev" ] && token_index=0 || ((token_index++))
            prev="$t"
            data=$(bal "$address" "$t" -i "$token_index" -l "$token_list" -n "$net" -r "$rpc")
            [ "$data" -a "${data:0:2}" != '0 ' ] && echo "$data"
        done < <(erc20 '' -a -l "$token_list" -n "$net" -c)
        return 0
    fi

    # ERC-20 get address, symbol and decimals
    if [ "${t^^}" != "${native_token^^}" ]; then
        readarray -t -d '' data < <(erc20 "$t" -i "$token_index" -l "$token_list" -n "$net" -c -r "$rpc")
        [ -z "$data" ] && return 1
        t="${data[0]}"
        d="${data[2]}"
        # eth call balanceOf
        address="000000000000000000000000${address:2}"
        params='{"id":1,"method":"eth_call","params":[{"to":"'${data[1]}'","data":"0x70a08231'${address}'"},"latest"]}'
    fi

    data=$(curl -Ls "$rpc" --json "$params")
    [ -z "$data" ] && { >&2 echo -e "error: connecting to rpc url $rpc\nparams: $params"; return 1; }
    data=${data##*\"0x}

    # check if result is too long
    if [ ${#data} -gt 66 ]; then
        >&2 echo -e "error: balance returned is more than 256 bit"
        return 1
    fi

    data=$(fromWei "0x${data:0:-2}" "$d")
    echo "$data $t"
}

# get prices from chainlink oracles
# usage: chainlink [pair, coin or address] [-r RPC URL]
chainlink() {
    local address="${1,,}"
    local rpc="$ETH_RPC_URL"
    [ "${2}${3}" ] && rpc="${2:2}${3}"
    local d=''

    if [ "${address:0:2}" != 0x -o "${#address}" -ne 42 ]; then
        address=${address////-}
        [[ "$address" != *-* ]] && address="${address}-usd"
        case "${address: -4}" in
            -usd|-btc) d=8 ;;
            -eth) d=18 ;;
        esac
        address=$(ens "${address}.data.eth" -C -r "$rpc")
    fi

    [ ${#address} -ne 42 ] && { >&2 echo -e "error: no chainlink oracle for $1"; return 1; }

    # get decimals
    if [ -z "$d" ]; then
        local params='{"id":1,"method":"eth_call","params":[{"to":"'${address}'","data":"0x313ce567"},"latest"]}'
        local data=$(curl -Ls "$rpc" --json "$params")
        [ -z "$data" ] && { >&2 echo -e "error: connecting to rpc url $rpc\nparams: $params"; return 1; }
        d=$(fromWei "${data: -68:66}" 0)
    fi

    # call 'latestAnswer' method
    local params='{"id":1,"method":"eth_call","params":[{"to":"'${address}'","data":"0x50d25bcd"},"latest"]}'
    local data=$(curl -Ls "$rpc" --json "$params")
    [ -z "$data" ] && { >&2 echo -e "error: connecting to rpc url $rpc\nparams: $params"; return 1; }
    [ "${data: -2:1}" = '}' ] && { >&2 echo -e "error: oracle contract\n$data"; return 1; } 

    fromWei "${data: -68:66}" "$d"
}

# get quote from Uniswap v3
# usage: uni [amount to sell] [sell token] [buy token] [-f fee] [-l token_list] [-i token_index] [-I token_index] [-n network] [-r RPC URL]
#   or   uni [sell token] [amount to buy] [buy token]  [-f fee] [-l token_list] [-i token_index] [-I token_index] [-n network] [-r RPC URL]
uni() {
    local rpc="$ETH_RPC_URL"
    local t=('' '')
    local amount=('' '')
    local token_index=('' '')
    local token_list=''
    local net=''
    local fee='0.3'
    local fee_set=''
    local opt OPTIND OPTARG
    for opt in "$1" "$2" "$3"; do
        if [[ "${opt/./}" =~ ^[0-9]+$ ]]; then
            [ "${t[0]}" ] && amount[1]="$opt" || amount[0]="$opt"
        else
            [ "${t[0]}" ] && t[1]="$opt" || t[0]="$opt"
        fi
    done
    shift 3
    while getopts ":l:i:I:n:f:r:" opt; do
        case $opt in
            l) token_list="$OPTARG" ;;
            i) token_index[0]="$OPTARG" ;;
            I) token_index[1]="$OPTARG" ;;
            n) net="$OPTARG" ;;
            f) [ "$OPTARG" ] && { fee="$OPTARG"; fee_set=1; } ;;
            r) [ "$OPTARG" ] && rpc="$OPTARG" ;;
            :)  { echo "Option -$OPTARG requires an argument." >&2; return 1; } ;;
            \?) { echo "Invalid option!: -$OPTARG" >&2 ; return 1; } ;;
        esac
    done

    local fee_hex='0bb8'
    case "${fee%\%}" in
        0.01|.01)   fee_hex='0064' ;;
        0.05|.05)   fee_hex='01f4' ;;
        1|1.0|1.00) fee_hex='2710' ;;
    esac
    local z='0000000000000000000000000000000000000000000000000000000000000000'
    local quoter='0x61fFE014bA17989E743c5F6cB21bF9697530B21e'
    local native_token=ETH
    case "$net" in
        polygon|polygon-pos) native_token=MATIC ;;
        bsc|binance-smart-chain) 
            native_token=BNB
            quoter='0x78D78E420Da98ad378D7799bE8f4AF69033EB077'
            ;;
    esac

    # get tokens info
    local data i
    local t_addr=('' '')
    local d=('' '')
    local t_og=('' '')
    for i in 0 1; do
        if [ "${t[$i]^^}" = "$native_token" ]; then
            t_og[$i]="$native_token"
            t[$i]="W$native_token" # use wrapped native token
        fi
        readarray -t -d '' data < <(erc20 "${t[$i]}" -i "${token_index[$i]}" -l "$token_list" -n "$net" -c -r "$rpc")
        [ -z "$data" ] && return 1
        t[$i]="${data[0]}"
        d[$i]="${data[2]}"
        data="${data[1]}"
        t_addr[$i]="${z:0:24}${data:2}"
        [ "${t_og[$i]}" ] && t[$i]="${t_og[$i]}" # restore original token symbol
    done

    # select ExactInput or ExactOutput mode
    if [ "${amount[0]}" ]; then # quoteExactInputSingle
        i=0
        local params='{"method":"eth_call","params":[{"to":"'${quoter}'","data":"0xc6a5026a'
    else  # quoteExactOutputSingle
        i=1
        local params='{"method":"eth_call","params":[{"to":"'${quoter}'","data":"0xbd21704a'
    fi

    local amount_hex=$(toWei "${amount[$i]}" "${d[$i]}" -x)
    amount_hex=${z:0:$((66-${#amount_hex}))}${amount_hex:2} # pad with zeroes
    params="${params}${t_addr[0]}${t_addr[1]}${amount_hex}${z:0:60}${fee_hex}${z}"'"},"latest"],"id":1}'
    data=$(curl -Ls "$rpc" --json "$params")
    [ -z "$data" ] && { >&2 echo -e "error: connecting to rpc url $rpc\nparams: $params"; return 1; }
    if [[ "$data" == *reverted* ]]; then
        if [ -z "$fee_set" ]; then # retry with 1% fee
            echo "warning: no pool available for ${t[0]}/${t[1]} with fee ${fee%\%}%, trying 1%" >&2
            fee=1
            fee_hex='2710'
            params="${params:0:292}${z:0:60}${fee_hex}${z}"'"},"latest"],"id":1}'
            data=$(curl -Ls "$rpc" --json "$params")
            [ -z "$data" ] && { >&2 echo -e "error: connecting to rpc url $rpc\nparams: $params"; return 1; }
        fi
        [[ "$data" == *reverted* ]] && { >&2 echo "error: no pool available for ${t[0]}/${t[1]} with fee ${fee%\%}%"; return 1; }
    fi
    data=${data#*\"result\":\"}
    amount[$((1-$i))]=$(fromWei "${data:0:66}" "${d[$((1-$i))]}")

    echo "${amount[0]} ${t[0]} -> ${amount[1]} ${t[1]}" 
}

# get next block gas price
# usage: gas [-d] [-w] [-p min priority fee] [-r RPC URL]
gas() {
    local rpc="$ETH_RPC_URL"
    local gwei=1000000000
    local details=''
    local wei_out=''
    local min_prio_fee_gwei=1
    local opt OPTIND OPTARG
    while getopts ":dwp:r:" opt; do
        case $opt in
            d) details=1 ;;
            w) wei_out=1 ;;
            p) min_prio_fee_gwei="$OPTARG" ;;
            r) [ "$OPTARG" ] && rpc="$OPTARG" ;;
            :)  { echo "Option -$OPTARG requires an argument." >&2; return 1; } ;;
            \?) { echo "Invalid option!: -$OPTARG" >&2 ; return 1; } ;;
        esac
    done

    # get lastest block data: base fee, gas target and gas used
    local params='{"id":1,"method":"eth_getBlockByNumber","params":["latest",true]}'
    local block=$(curl -Ls "$rpc" --json "$params")
    [ -z "$block" ] && { >&2 echo -e "error: connecting to rpc url $rpc\nparams: $params"; return 1; }
    local block_data=($(echo "$block" | jq -j '.result | "\(.baseFeePerGas) \(.gasLimit) \(.gasUsed)"'))
    local base_fee="${block_data[0]}"
    local gas_target=$(( ${block_data[1]} / 2 ))
    local gas_used_delta=$(( ${block_data[2]} - $gas_target ))

    # calculate next block base fee using latest block base fee, gas target and gas used
    local new_base_fee=$(printf %u $base_fee)
    if [ "$gas_used_delta" -ne 0 ]; then
        local x=$(( $base_fee * ${gas_used_delta#-} ))
        local y=$(( $x / $gas_target ))
        if [ "$gas_used_delta" -gt 0 ]; then
            new_base_fee=$(( $base_fee + $(( $y / 8 )) ))
        else
            new_base_fee=$(( $base_fee - $(( $y / 8 )) ))
        fi
    fi

    # get the minimum priority fee paid in latest block
    # which is the minimum total gas price minus the base fee
    # remove txs with 0 prio fee (gas price == base fee)
    # pad the value to the same length (16 chars)
    # then sort to get the lowest value
    local filter="[.result.transactions[] | select(.gasPrice != \"$base_fee\").gasPrice | \
        .[2:] | (length | if . >= 16 then \"\" else \"0\" * (16 - .) end) as \$padding | \
        \"\\(\$padding)\\(.)\"] | sort[0]"
    local prio_fee=$(( 0x$(echo "$block" | jq -j "$filter") - $base_fee ))
    # apply minimum priority fee
    [ "$prio_fee" -lt ${min_prio_fee_gwei}${gwei:1} ] && prio_fee=${min_prio_fee_gwei}${gwei:1}

    # print result
    if [ -z "$details" ] && [ -z "$wei_out" ]; then
        echo $(( $(( $new_base_fee + $prio_fee )) / $gwei ))
    elif [ "$details" ] && [ "$wei_out" ]; then
        echo "${new_base_fee},${prio_fee}"
    elif [ "$details" ]; then
        echo $(( $new_base_fee / $gwei )),$(( $prio_fee / $gwei ))
    else
        echo $(( $new_base_fee + $prio_fee ))
    fi
}


if [ "$BASH_SOURCE" = "$0" ]; then
    command="${1:0:3}"
    shift
    case "${command,,}" in
        bal) bal "$@" ;;
        ens) ens "$@" ;;
        gas) gas "$@" ;;
        uni) uni "$@" ;;
        erc) erc20 "$@" ;;
        kec) keccak "$@" ;;
        tow) toWei "$@" ;;
        fro) fromWei "$@" ;;
        cha) chainlink "$@" ;;
        *)
            echo -e \
'Useful tools for Web3 / Ethereum\n'\
'Usage:\n  ./web3-tools.sh [command] [args...] [-r RPC URL]\n\n'\
'Commands:\n'\
'bal\n  Get ETH or ERC-20 token balance of address\n'\
'  usage: bal [address or ENS name] [token address or symbol] [-l token_list] [-i token_index] [-n network] [-a] [-r RPC URL]\n\n'\
'ens\n  resolve ENS address or reverse resolve ETH address\n'\
'  usage: ens [ENS name or address] [-C] [-r RPC URL]\n\n'\
'gas\n  Get next block gas price\n'\
'  usage: gas [-d] [-w] [-p min priority fee] [-r RPC URL]\n\n'\
'erc20\n  Get ERC-20 token info\n'\
'  usage: erc20 [address or symbol] [-l token_list] [-i token_index] [-n network] [-a] [-r RPC URL]\n\n'\
'uni\n  Get quote from Uniswap v3\n'\
'  usage: uni [amount to sell] [sell token] [buy token] [-f fee] [-l token_list] [-i token_index] [-I token_index] [-n network] [-r RPC URL]\n'\
'    or   uni [sell token] [amount to buy] [buy token]  ...\n\n'\
'chainlink\n  Get prices from chainlink oracles\n'\
'  usage: chainlink [pair, coin or address] [-r RPC URL]\n'\
'  Input can be a pair like eth-usd or eth/btc (case insensitive)\n'\
'  or just a coin/asset to get usd price\n'\
'  or directly the address of the oracle contract\n\n'\
'keccak\n  keccak 256 hash (web3 sha3)\n'\
'  usage: keccak [data] [-x] [-r RPC URL]\n\n'\
'toWei\n  Convert from ether to wei\n'\
'  usage: toWei [number] [number of decimals] [-x]\n\n'\
'fromWei\n  Convert from wei to ether\n'\
'  usage: fromWei [number] [number of decimals]\n\n'\
'Requirements:\n'\
'  - bash 4.0+\n'\
'  - jq for token list parsing and gas price\n'\
'  - curl for rpc calls\n'\
'  - gawk (GNU awk with -M option) for hex numbers greater than 64 bit\n'\
'  - keccak-256sum from https://codeberg.org/maandree/sha3sum for ENS resolving,\n'\
'    fallback to using web3_sha3 rpc call if not installed\n\n'\
'Options:\n'\
"  -r <RPC URL>       RPC URL to get blockchain data (default: $ETH_RPC_URL)\n"\
'bal and erc20 commands:\n'\
'  -l <token_list>    Path to json token list (default: ~/.config/tokens.json or tokens.json in the same directory as the script)\n'\
'                     Use provided list or download from Coingecko using\n'\
"                     curl -Ls 'https://api.coingecko.com/api/v3/coins/list?include_platform=true' | jq > coingecko.json\n"\
'  -i <token_index>   Index in token list for tokens with same symbol (starting from zero)\n'\
'  -n <network>       Name of network in token list (default: ethereum)\n'\
'  -a                 Show all tokens or get all balances from token list\n'\
'gas command:\n'\
'  -d                 Output comma-separated Base Fee and Priority Fee\n'\
'  -w                 Output in wei\n'\
'  -p <min_prio_fee>  Minimum priority fee in gwei to apply to output (default: 1 gwei)\n'\
'ens command:\n'\
'  -C                 Disable checksumming of output address\n'\
'uni command:\n'\
'  -f <fee>           Pool fee in percent (default: 0.3)\n'\
'keccak command:\n'\
'  -x                 Convert input from hexadecimal\n'\
'toWei command:\n'\
'  -x                 Convert output to hexadecimal'
            # check dependencies
            [ "${BASH_VERSION%%.*}" -lt 4 ] && echo "error: bash version $BASH_VERSION lower than 4.0"
            command -v jq >/dev/null 2>&1 || echo "error: jq is not installed"
            command -v curl >/dev/null 2>&1 || echo "error: curl is not installed"
            command -v gawk >/dev/null 2>&1 || echo "error: gawk is not installed"
            command -v keccak-256sum >/dev/null 2>&1 || echo "warning: keccak-256sum is not installed," \
                                                             "will use web3_sha3 rpc call instead (slower)"
            ;;
    esac
fi

# limitations:
#   - token symbol starting with -l, -i, -n, -a or -r in bal command
#   - token symbol is the same as the native token in bal command
#   - gas price greater than signed 64 bit integer (9223372036 gwei)
#   - ens names with non ascii chars when using web3_sha3 from RPC
#   - non normalized ens names

