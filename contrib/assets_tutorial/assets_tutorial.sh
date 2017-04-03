
shopt -s expand_aliases

rm -r ~/elementsdir1
rm -r ~/elementsdir2
rm -r ~/bitcoindir
mkdir ~/elementsdir1
mkdir ~/elementsdir2
mkdir ~/bitcoindir

# First we need to set up our config files to walk through this demo

cat <<EOF > ~/elementsdir1/elements.conf
# Standard bitcoind stuff
rpcuser=user1
rpcpassword=password1
rpcport=18884
port=18886

# Over p2p we will only connect to local other elementsd
connect=localhost:18887

regtest=1
daemon=1
# Make sure you set listen after -connect, otherwise neither
# will accept incoming connections!
listen=1
# Just for looking at random txs
txindex=1

# This is the script that controls pegged in funds in Bitcoin network
# Users will be pegging into a P2SH of this, and the "watchmen"
# can then recover these funds and send them to users who desire to peg out.
# This template is 1-of-1 checkmultisig
#fedpegscript=5121<pubkey>51ae

# This is the script that controls how blocks are made
# We have to supply a signature that satisfies this to create
# a valid block.
#signblockscript=5121<pubkey2>51ae

# We want to validate pegins by checking with bitcoind if header exists
# in best known chain, and how deep. We combine this with pegin
# proof included in the pegin to get full security.
validatepegin=1

# If in the same datadir and using standard ports, these are unneeded
# thanks to cookie auth. If not, like in our situation, elementsd needs
# more info to connect to bitcoind:
mainchainrpcport=18888
mainchainrpcuser=user3
mainchainrpcpassword=password3
EOF

cat <<EOF > ~/elementsdir2/elements.conf
rpcuser=user2
rpcpassword=password2
rpcport=18885
port=18887
connect=localhost:18886

regtest=1
daemon=1
listen=1
txindex=1

#fedpegscript=51<pubkey>51ae
#signblockscript=51<pubkey2>51ae

mainchainrpcport=18888
mainchainrpcuser=user3
mainchainrpcpassword=password3
validatepegin=1
EOF

cat <<EOF > ~/bitcoindir/bitcoin.conf
rpcuser=user3
rpcpassword=password3
rpcport=18888
port=18889

regtest=1
testnet=0
daemon=1
txindex=1
EOF

ELEMENTSPATH="."
BITCOINPATH="."

alias e1-cli="$ELEMENTSPATH/elements-cli -datadir=$HOME/elementsdir1"
alias e1-dae="$ELEMENTSPATH/elementsd -datadir=$HOME/elementsdir1"
alias e2-cli="$ELEMENTSPATH/elements-cli -datadir=$HOME/elementsdir2"
alias e2-dae="$ELEMENTSPATH/elementsd -datadir=$HOME/elementsdir2"

alias b-cli="$BITCOINPATH/bitcoin-cli -datadir=$HOME/bitcoindir"
alias b-dae="$BITCOINPATH/bitcoind -datadir=$HOME/bitcoindir"

# Should throw an error, can't connect to bitcoin daemon to validate pegins
e1-dae

# Need to start bitcoind first, elementsd will wait until bitcoind gives warmup finished status
b-dae
e1-dae
e2-dae

# Prime the chain, see "immature balance" holds all funds until genesis is mature
e1-cli getwalletinfo

# Mining for now is OP_TRUE
e1-cli generate 101

# Now we have 21M OP_TRUE value
e1-cli getwalletinfo
e2-cli getwalletinfo

# Primed and ready

######## WALLET ###########


#Sample raw transaction RPC API

#   ~Core API

#* `getrawtransaction <txid> 1`
#* `gettransaction <txid> 1`
#* `listunspent`
#* `decoderawtransaction <hex>`
#* `sendrawtransaction <hex>`
#* `validateaddress <address>
#* `listreceivedbyaddress <minconf> <include_empty> <include_watchonly>`

#   Elements Only API

#* `blindrawtransaction <hex>`
#* `dumpblindingkey <address>`
#* `importblindingkey <addr> <blindingkey>`

# But let's start with a managed wallet example

# First, drain OP_TRUE
e1-cli sendtoaddress $(e1-cli getnewaddress) 10500000 "" "" true
e1-cli generate 101
e2-cli sendtoaddress $(e2-cli getnewaddress) 10500000 "" "" true
e2-cli generate 101

# Funds should be evenly split
e1-cli getwalletinfo
e2-cli getwalletinfo

# Have Bob send coins to himself using a blinded Elements address!
# Blinded addresses start with `CTE`, unblinded `2`
ADDR=$(e2-cli getnewaddress)

# How do we know it's blinded? Check for blinding key, unblinded address.
e2-cli validateaddress $ADDR

TXID=$(e2-cli sendtoaddress $ADDR 1)

e2-cli generate 1

# Now let's examine the transaction, both in wallet and without

# In-wallet, take a look at blinding information
e2-cli gettransaction $TXID
# e1 doesn't have in wallet
e1-cli gettransaction $TXID

# public info, see blinded ranges, etc
e1-cli getrawtransaction $TXID 1

# Now let's import the key to spend
e1-cli importprivkey $(e2-cli dumpprivkey $ADDR)

# We can't see output value info though
e1-cli gettransaction $TXID
# And it won't show in balance or known outputs
e1-cli getwalletinfo
# Amount for transaction is unknown, so it is not shown.
e1-cli listunspent 1 1

# Solution: Import blinding key
e1-cli importblindingkey $ADDR $(e2-cli dumpblindingkey $ADDR)

# Check again, funds should show
e1-cli getwalletinfo
e1-cli listunspent 1 1
e1-cli gettransaction $TXID

#Exercises
#===
# Resources: https://bitcoin.org/en/developer-documentation
#1. Find the change output in one of your transactions.
#2. Use both methods to get the total input value of the transaction.
#3. Find your UTXO with the most confirmations.
#4. Create a raw transaction that pays 0.1 coins in fees and has two change addresses.
#5. Build blinded multisig p2sh

###### ASSETS #######

# Many of the RPC calls have added asset type or label 
# arguments and reveal alternative asset information. With no argument all are listed:
e1-cli getwalletinfo

# Notice we now see "bitcoin" as an asset. This is the asset label for the hex for "bitcoin" which can be discovered:
e1-cli dumpassetlabels

# You can also filter calls using specific asset hex or labels:
e1-cli getwalletinfo bitcoin
# bitcoin's hex asset type
e1-cli getwalletinfo 09f663de96be771f50cab5ded00256ffe63773e2eaa9a604092951cc3d7c6621

# We can also issue our own assets, 1 asset and 1 reissuance token in this case
ISSUE=$(e1-cli issueasset 1 1)
echo $ISSUE
ASSET=$(echo $ISSUE | jq '.asset' | tr -d '"')
echo $ASSET

# From there you can look at the issuances you have in your wallet
e1-cli listissuances

# If you gave `issueasset` a 2nd argument greater than 0, you can also reissue the base asset
e1-cli reissueasset $ASSET 1

# or make another unblinded asset issuance, with only reissuance tokens initially
e1-cli issueasset 0 1 false

# Then two issuances for that particular asset will show
e1-cli listissuances $ASSET

# To label the asset add this to your elements.conf file then restart your daemon:
# assetdir=$ASSET:yourlabelhere
# It really doesn't matter what you call it, labels are local things only.

# To send issued assets, add an additional argument to sendtoaddress using the hex or label
e1-cli sendtoaddress $(e2-cli getnewaddress) 1 "" "" false $ASSET
e2-cli getwalletinfo $ASSET
e2-cli generate 1

# e2 doesn't know about the issuance for the transaction sending him the new asset
e2-cli listissuances

# let's import an associated address and rescan
TXID=$(echo $ISSUE | jq '.txid' | tr -d '"')
ADDR=$(e1-cli gettransaction $TXID | jq '.details[0].address' | tr -d '"')

e2-cli importaddress $ADDR

# e2 now sees issuance, but doesn't know amounts as they are blinded
e2-cli listissuances

# We need to import the issuance blinding key. We refer to issuances by their txid/vin pair
# as there is only one per input
VIN=$(echo $ISSUE | jq '.vin' | tr -d '"')
ISSUEKEY=$(e1-cli dumpissuanceblindingkey $TXID $VIN)
echo $ISSUEKEY

e2-cli importissuanceblindingkey $TXID $VIN $ISSUEKEY

# Now e2 can see issuance amounts and blinds
e2-cli listissuances

###### BLOCKSIGNING #######

# Recall blocksigning is OP_TRUE
e1-cli generate 1

# Let's set it to something more interesting... 2-of-2 multisig

# First lets get some keys from both clients to make our block "challenge"
ADDR1=$(e1-cli getnewaddress)
ADDR2=$(e2-cli getnewaddress)
VALID1=$(e1-cli validateaddress $ADDR1)
PUBKEY1=$(echo $VALID1 | python3 -c "import sys, json; print(json.load(sys.stdin)['pubkey'])")
VALID2=$(e2-cli validateaddress $ADDR2)
PUBKEY2=$(echo $VALID2 | python3 -c "import sys, json; print(json.load(sys.stdin)['pubkey'])")

KEY1=$(e1-cli dumpprivkey $ADDR1)
KEY2=$(e2-cli dumpprivkey $ADDR2)

e1-cli stop
e2-cli stop

# Now filled with the pubkeys as 2-of-2 checkmultisig
SIGNBLOCKARG="-signblockscript=5221$(echo $PUBKEY1)21$(echo $PUBKEY2)52ae"

# Wipe out the chain and wallet to get funds with new genesis block
# You can not swap out blocksigner sets as of now for security reasons,
# so we start fresh on a new chain.
rm -r ~/elementsdir1/elementsregtest/blocks
rm -r ~/elementsdir1/elementsregtest/chainstate
rm ~/elementsdir1/elementsregtest/wallet.dat
rm -r ~/elementsdir2/elementsregtest/blocks
rm -r ~/elementsdir2/elementsregtest/chainstate
rm ~/elementsdir2/elementsregtest/wallet.dat

e1-dae $SIGNBLOCKARG
e2-dae $SIGNBLOCKARG

# Now import signing keys
e1-cli importprivkey $KEY1
e2-cli importprivkey $KEY2

# Generate no longer works, even if keys are in wallet
e1-cli generate 1
e2-cli generate 1

# Let's propose and accept some blocks, e1 is master!
HEX=$(e1-cli getnewblockhex)

# Unsigned is no good
# 0 before, 0 after
e1-cli getblockcount
 
e1-cli submitblock $HEX

# Still 0
e1-cli getblockcount

####
# Signblock tests validity except block signatures
# This signing step can be outsourced to a HSM signing to enforce business logic of any sort
# See Strong Federations paper
SIGN1=$(e1-cli signblock $HEX)
SIGN2=$(e2-cli signblock $HEX)
####

# We now can gather signatures any way you want, combine them into a fully signed block
BLOCKRESULT=$(e1-cli combineblocksigs $HEX '''["'''$SIGN1'''", "'''$SIGN2'''"]''')

COMPLETE=$(echo $BLOCKRESULT | python3 -c "import sys, json; print(json.load(sys.stdin)['complete'])")
SIGNBLOCK=$(echo $BLOCKRESULT | python3 -c "import sys, json; print(json.load(sys.stdin)['hex'])")

# Should get True here as we have signatures from each key
echo $COMPLETE

# Now submit the block, doesn't matter who
e2-cli submitblock $SIGNBLOCK

# We now have moved forward one block!
e1-cli getblockcount
e2-cli getblockcount

e1-cli stop
e2-cli stop

# Further Exercises:
# 1.Make funny/different block block challenge? modify generate to allow arbitrary proof, instead of from wallet only
# 2.Arbitrary consensus change?
# 3.Make a python script that does round-robin consensus

######## Pegging #######

# Everything pegging related can be done inside the Elements daemon directly, except for
# pegging out. This is due to the multisig pool aka Watchmen that controls the bitcoin
# on the Bitcoin blockchain. That is the easiest part to get wrong, and by far the most
# important as there is no going back if you lose the funds.

# Wipe out the chain and wallet to get funds with new genesis block
rm -r ~/elementsdir1/elementsregtest/blocks
rm -r ~/elementsdir1/elementsregtest/chainstate
rm ~/elementsdir1/elementsregtest/wallet.dat
rm -r ~/elementsdir2/elementsregtest/blocks
rm -r ~/elementsdir2/elementsregtest/chainstate
rm ~/elementsdir2/elementsregtest/wallet.dat

FEDPEGARG="-fedpegscript=5221$(echo $PUBKEY1)21$(echo $PUBKEY2)52ae"

# Back to OP_TRUE blocks, re-using pubkeys for pegin pool instead
# Keys can be the same or different, doesn't matter
e1-dae $FEDPEGARG
e2-dae $FEDPEGARG

# Mature some outputs on each side
e1-cli generate 101
b-cli generate 101

# We have to lock up some of the funds first. Regtest(what we're running) has all funds as OP_TRUE
# but this is not the case in testnet/production. Doesn't matter where we send it
# inside Bitcoin, this is just a hack to lock some funds up.
e1-cli sendtomainchain $(b-cli getnewaddress) 50

# Mature the pegout
e1-cli generate 101

# Now we can actually start pegging in. Examine the pegin address fields
e1-cli getpeginaddress
# Changes each time as it's a new sidechain address as well as new "tweak" for the watchmen keys
# mainchain_address : where you send your bitcoin from Bitcoin network
# sidechain_address : where the bitcoin will end up on the sidechain after pegging in

# Each call of this takes the pubkeys defined in the config file, adds a random number to them
# that is essetially the hash of the sidechain_address and other information,
# then creates a new P2SH Bitcoin address from that. We reveal that "tweak" to the functionaries
# during `claimpegin`, then they are able to calculate the necessary private key and control
# funds. 
e1-cli getpeginaddress

ADDRS=$(e1-cli getpeginaddress)

MAINCHAIN=$(echo $ADDRS | python3 -c "import sys, json; print(json.load(sys.stdin)['mainchain_address'])")
SIDECHAIN=$(echo $ADDRS | python3 -c "import sys, json; print(json.load(sys.stdin)['sidechain_address'])")

#Send funds to unique watchmen P2SH address
TXID=$(b-cli sendtoaddress $MAINCHAIN 1)

# Mature pegin funds to avoid reorg -> fractional reserve
b-cli generate 101
PROOF=$(b-cli gettxoutproof '''["'''$TXID'''"]''')
RAW=$(b-cli getrawtransaction $TXID)

# Attempt claim!
CLAIMTXID=$(e1-cli claimpegin $SIDECHAIN $RAW $PROOF)

# Other node should accept to mempool and mine
e2-cli generate 1

# Should see confirmations
e1-cli getrawtransaction $CLAIMTXID 1

#### Pegging Out ####

#sendtomainaddress <addr> <amount>

#Exercises
#1. Implement really dumb/unsafe watchmen to allow pegouts for learning purposes
# Recover tweak from pegin, add to privkey, combined tweaked pubkeys into a redeemscript, add to Core wallet