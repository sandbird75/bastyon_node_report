#!/bin/bash

# This script sends report from Bastyon Node to Telegram.
# Script require jq for parsing JSON output of pocketcoin-cli tool
# and curl for sending message to Telegram
# Usage:
# for sending only when problem or change state occurs:
# bastyon_node_report.sh -alerts
# for unconditional sending:
# bastyon_node_report.sh

# Telegram
TOKEN=1234567890:ABCdefGhijKLMnOpqRsTuvwXyzabc-1deFG
CHAT_ID=987654321
URL=https://api.telegram.org/bot$TOKEN/sendMessage

#header of the message to send
TEXT_MESSAGE=$(echo "$HOSTNAME BASTYON NODE REPORT%0A%0A" | sed 's/[a-z]/\U&/g')

# file to save variables for next run
TEMP_FILE=$(readlink -f $0).tmp

# log
LOG_FILE=$(readlink -f $0).log
echo >> "$LOG_FILE"
echo $(date -R) >> "$LOG_FILE"

# check parameter
if [[ $# -gt 1 || ($# -eq 1 && $1 != "-alerts") ]]; then
	echo "Usage: $(basename $0) [-alerts]" | tee -a "$LOG_FILE"
	exit 1
fi

# check for required programs
if [ ! $(which pocketcoin-cli) ]; then MISSING_PROGRAMS="\tpocketcoin-cli\n"; fi
if [ ! $(which jq) ]; then MISSING_PROGRAMS="$MISSING_PROGRAMS\tjq\n"; fi
if [ ! $(which curl) ]; then MISSING_PROGRAMS="$MISSING_PROGRAMS\tcurl\n"; fi
if [ "$MISSING_PROGRAMS" ]; then
	echo -e "You must install this programs into \$PATH:\n$MISSING_PROGRAMS" | tee -a "$LOG_FILE"
	exit 1
fi

# read variables from previous run
if [ -r "$TEMP_FILE" ]; then
	source "$TEMP_FILE"
else  # or initialize some of them on first run to avoid errors
	BLOCKS_0="0"
	HEADERS_0="0"
	WALLET_BALANCE_0="0"
fi

# check the node is running, then goes on all next checking
if pidof pocketcoind; then

	# staking balance
	read ENABLED STAKING STAKING_BALANCE < <(echo $(pocketcoin-cli getstakinginfo | jq -r '.enabled, .staking, .balance'))

	# connections - if less then 8 then there is a problem
	CONNECTION_COUNT=$(pocketcoin-cli getconnectioncount)

	# blockchain
	read BLOCKS HEADERS < <(echo $(pocketcoin-cli getblockchaininfo | jq -r '.blocks, .headers'))

	# full wallet balance (summ all addresses by awk)
	WALLET_BALANCE=$(pocketcoin-cli listaddresses | jq '.[].balance' | awk '{n += $1}; END{printf "%.0f", n}')

	# stuck transactions: has been created more then 1800 seconds ago and still without confirmations
	i=0
	STUCK_TRANSACTION="false"
	while true; do
		CONFIRMATIONS=$(pocketcoin-cli listtransactions | jq -r --argjson i $i '.[$i].confirmations')
		if [[ "$CONFIRMATIONS" == "null" ]]; then
			break
		elif [[ "$CONFIRMATIONS" -eq 0 ]]; then
			TIME=$(pocketcoin-cli listtransactions | jq -r --argjson i $i '.[$i].time')
			ABANDONED=$(pocketcoin-cli listtransactions | jq -r --argjson i $i '.[$i].abandoned')
			if [[ $(( $(date +%s) - $TIME )) -gt 1800 && "$ABANDONED" == "false" ]]; then
				STUCK_TRANSACTION="true"
				# comment out next 3 strings if you want stuck transactions not to be removed automatically
				TXID=$(pocketcoin-cli listtransactions | jq -r --argjson i $i '.[$i].txid')
				pocketcoin-cli abandontransaction "$TXID" >> "$LOG_FILE"
				echo "TX \"$TXID\" has been abandoned"  >> "$LOG_FILE"
			fi
		fi
		i=$(($i+1))
	done

	# current version of pocketnet.core
	NODE_VERSION=`pocketcoind -version | awk 'match($0, /v*[0-9]+\.[0-9]+\.[0-9]+/){print substr($0,RSTART,RLENGTH)}'`

	# latest version of pocketnet.core
	NODE_VERSION_LATEST=$(curl https://api.github.com/repos/pocketnetteam/pocketnet.core/releases/latest | jq -r '.tag_name')

	# external IP
	EXTERNAL_IP=$(curl eth0.me)

	# last os boot time
	LAST_BOOT=`who -b | awk 'match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]/){print substr($0,RSTART,RLENGTH)}'`

	# last app start time
	LAST_START=$(tac ~/.pocketcoin/debug.log | grep -m 1 "Pocketnet Core version" | awk -F" " '{print $1}' | date +"%Y-%m-%d %H:%M" -f -)

	# save current vars for the next run to compare
	echo "export ENABLED_0=\"$ENABLED\"" > $TEMP_FILE
	echo "export STAKING_0=\"$STAKING\"" >> $TEMP_FILE
	echo "export CONNECTION_COUNT_0=\"$CONNECTION_COUNT\"" >> $TEMP_FILE
	echo "export BLOCKS_0=\"$BLOCKS\"" >> $TEMP_FILE
	echo "export HEADERS_0=\"$HEADERS\"" >> $TEMP_FILE
	echo "export WALLET_BALANCE_0=\"$WALLET_BALANCE\"" >> $TEMP_FILE
	echo "export STAKING_BALANCE_0=\"$STAKING_BALANCE\"" >> $TEMP_FILE
	echo "export STUCK_TRANSACTION_0=\"$STUCK_TRANSACTION\"" >> $TEMP_FILE
	echo "export NODE_VERSION_LATEST_0=\"$NODE_VERSION_LATEST\"" >> $TEMP_FILE
	echo "export EXTERNAL_IP_0=\"$EXTERNAL_IP\"" >> $TEMP_FILE
	echo "export LAST_BOOT_0=\"$LAST_BOOT\"" >> $TEMP_FILE
	echo "export LAST_START_0=\"$LAST_START\"" >> $TEMP_FILE

	#checks for changes and problems

	# does the staking enabled?
	if [[ "$ENABLED" != "true" ]]; then
		ENABLED_COMMENT="STAKING DISABLED"
		if [[ "$ENABLED" != "$ENABLED_0" ]]; then  # alerts only when switching
			SEND_TO_TELEGRAM="true"
		fi
	fi

	# does the staking work?
	if [[ "$STAKING" != "true" ]]; then
		STAKING_COMMENT="STAKING NOT WORK"
		if [[ "$STAKING" != "$STAKING_0" ]]; then  # alerts only when switching
			SEND_TO_TELEGRAM="true"
		fi
	fi

	# too few connections
	if [[ "$CONNECTION_COUNT" -lt 8 ]]; then
		CONNECTION_COUNT_COMMENT="TOO FEW"
		if [[ "$CONNECTION_COUNT_0" -ge 8 ]]; then  # alerts only once
			SEND_TO_TELEGRAM="true"
		fi
	elif [[ "$CONNECTION_COUNT_0" -lt 8 ]]; then    # alerts restoring
		SEND_TO_TELEGRAM="true"
	fi

	# no new blocks since previous run
	if [[ "$BLOCKS" -eq "$BLOCKS_0" ]]; then
		BLOCKS_COMMENT="NOT CHANGED"
		echo "export BLOCKS_NOT_CHANGED=\"true\"" >> "$TEMP_FILE"
		if [[ "$BLOCKS_NOT_CHANGED" != "true" ]]; then          # alerts only once
			SEND_TO_TELEGRAM="true"
		fi
	else
		echo "export BLOCKS_NOT_CHANGED=\"false\"" >> $TEMP_FILE
		if [[ "$BLOCKS_NOT_CHANGED" == "true" ]]; then          # alerts restoring
			SEND_TO_TELEGRAM="true"
		fi
	fi

	# node is lagging
	if [[ $(( $HEADERS - $BLOCKS )) -gt 1 ]]; then
		BLOCKS_COMMENT="LAGGING"
		if [[ $(( $HEADERS_0 - $BLOCKS_0 )) -le 1 ]]; then  # alerts only once
			SEND_TO_TELEGRAM="true"
		fi
	elif [[ $(( $HEADERS_0 - $BLOCKS_0 )) -gt 1 ]]; then    # alerts restoring
		SEND_TO_TELEGRAM="true"
	fi

	# wallet balance is changed
	if [[ "$WALLET_BALANCE" != "$WALLET_BALANCE_0" ]]; then
		SEND_TO_TELEGRAM="true"
		WALLET_BALANCE_COMMENT="$( echo $(( $WALLET_BALANCE - $WALLET_BALANCE_0 )) | xargs printf "%+09d" | sed 's/........$/.&/' | sed 's/+/%2B/')"
	fi

	# staking balance does not match wallet balance (it's normal only for 2 hours after wallet balance change)
	if [[ "$WALLET_BALANCE" != "$STAKING_BALANCE" ]]; then
		STAKING_BALANCE_COMMENT="DIFFERS"
		if [[ "$WALLET_BALANCE_0" == "$STAKING_BALANCE_0" ]]; then  # alerts only once
			SEND_TO_TELEGRAM="true"
		fi
	elif [[ "$WALLET_BALANCE_0" != "$STAKING_BALANCE_0" ]]; then    # alerts restoring
		SEND_TO_TELEGRAM="true"
	fi

	# insert decimal point
	WALLET_BALANCE="$( echo $WALLET_BALANCE | sed 's/........$/.&/')"
	STAKING_BALANCE="$( echo $STAKING_BALANCE | sed 's/........$/.&/')"

	# stuck transaction found
	if [[ "$STUCK_TRANSACTION" == "true" ]]; then
		STUCK_TRANSACTION_COMMENT="TRYING TO REMOVE"
		if [[ "$STUCK_TRANSACTION_0" == "false" ]]; then  # alerts only once
			SEND_TO_TELEGRAM="true"
		fi
	elif [[ "$STUCK_TRANSACTION_0" == "true" ]]; then    # alerts restoring
		SEND_TO_TELEGRAM="true"
		STUCK_TRANSACTION_COMMENT="REMOVED"
	fi

	# new pocketner.core release published on Github
	if [[ "$NODE_VERSION_LATEST" != "$NODE_VERSION" && "$NODE_VERSION_LATEST" != "" ]]; then
		NODE_VERSION_COMMENT="NEW $NODE_VERSION_LATEST"
		if [[ "$NODE_VERSION_LATEST" != "$NODE_VERSION_LATEST_0" ]]; then # alerts only once
			SEND_TO_TELEGRAM="true"
		fi
	fi

	# external IP changed
	if [[ "$EXTERNAL_IP" != "$EXTERNAL_IP_0" && "$EXTERNAL_IP" != "" && "$EXTERNAL_IP_0" != "" ]]; then
		SEND_TO_TELEGRAM="true"
		EXTERNAL_IP_COMMENT="CHANGED"
	fi

	# last os boot changed
	if [[ "$LAST_BOOT" != "$LAST_BOOT_0"  ]]; then
		LAST_BOOT_COMMENT="OS REBOOTED"
		SEND_TO_TELEGRAM="true"
	fi

	# last app start changed
	if [[ "$LAST_START" != "$LAST_START_0"  ]]; then
		LAST_START_COMMENT="APP RESTARTED"
		SEND_TO_TELEGRAM="true"
	fi

	# node was not running but now it's back
	if [[ "$NODE_IS_NOT_RUNNING_0" == "true" ]]; then  # alerts restoring
		SEND_TO_TELEGRAM="true"
	fi

	# message to send
	TEXT_MESSAGE="$TEXT_MESSAGE\
	Staking enabled: $ENABLED   <b>$ENABLED_COMMENT</b>%0A\
	Staking working: $STAKING   <b>$STAKING_COMMENT</b>%0A\
	Connections count: $CONNECTION_COUNT   <b>$CONNECTION_COUNT_COMMENT</b>%0A\
	Validated blocks: $BLOCKS   <b>$BLOCKS_COMMENT</b>%0A\
	Validated headers: $HEADERS%0A\
	Wallet balance: $WALLET_BALANCE   <b>$WALLET_BALANCE_COMMENT</b>%0A\
	Staking balance: $STAKING_BALANCE   <b>$STAKING_BALANCE_COMMENT</b>%0A\
	Stuck transaction: $STUCK_TRANSACTION   <b>$STUCK_TRANSACTION_COMMENT</b>%0A\
	Current version: $NODE_VERSION   <b>$NODE_VERSION_COMMENT</b>%0A\
	External IP: $EXTERNAL_IP   <b>$EXTERNAL_IP_COMMENT</b>%0A\
	Last boot: $LAST_BOOT   <b>$LAST_BOOT_COMMENT</b>%0A\
	Last start: $LAST_START   <b>$LAST_START_COMMENT</b>"

else # if node is not running
	echo "export NODE_IS_NOT_RUNNING_0=\"true\"" >> $TEMP_FILE
	TEXT_MESSAGE="$TEXT_MESSAGE\
	NODE IS NOT RUNNING"
	if [[ "$NODE_IS_NOT_RUNNING_0" != "true" ]]; then  # alerts only once
		SEND_TO_TELEGRAM="true"
	fi
fi

# write to log
cat "$TEMP_FILE" >> "$LOG_FILE"

# send to Telegram
if [[ $# -eq 0 || "$SEND_TO_TELEGRAM" == "true" ]]; then
	curl -s -X POST "$URL" -d chat_id="$CHAT_ID" -d parse_mode=HTML -d text="$TEXT_MESSAGE"
	echo $TEXT_MESSAGE >> "$LOG_FILE"
fi
