## bastyon_node_report.sh
This script sends report from Bastyon Node to Telegram. It was tested on Debian 11, on other distros surprises are possible.

Script requires programs installed into $PATH:
* **pocketcoin-cli** command line tool;
* **jq** - for parsing JSON output of pocketcoin-cli tool;
* **curl** - for sending message to Telegram.
## Usage:
First, write in this script your personal values for the TOKEN and CHAT_ID variables to send to Telegram.

For sending report only when problem or change state occurs specify the parameter -alerts
```
bastyon_node_report.sh -alerts
```
For unconditional sending do not specify any parameter:
```
bastyon_node_report.sh
```
For exampe, you may run script with -alerts parameter every 15 minutes and run it without parameters one or more times a day. Please note that several (5 or more) minutes must pass between script runs, otherwise there will be a false alert if the current blockchain height does not change.

if you want stuck transactions not to be removed automatically, comment this lines:
```
pocketcoin-cli abandontransaction "$TXID" >> "$LOG_FILE"
echo "TX \"$TXID\" has been abandoned"  >> "$LOG_FILE"
```

When runing, the script creates the files `bastyon_node_report.sh.log` (script log) and `bastyon_node_report.sh.tmp` (save variable values for the next run) in the same directory.

## Example of report

NODE01 BASTYON NODE REPORT  

Staking enabled: true  
Staking working: true  
Connections count: 24  
Validated blocks: 1904912  
Validated headers: 1904912  
Wallet balance: 1234.56789012   **+5.00000042**  
Staking balance: 1123.45678901   **DIFFERS**  
Stuck transaction: false  
Current version: 0.20.27  
External IP: 123.45.67.89  
Last boot: 2022-08-29 17:06  
Last start: 2022-09-21 12:34  
