# discogs-red-barcode

A small (?) bash script that takes a barcode, searches it on Discogs, parses the results and searches them on RED to find groups or requests.

# Requirements

* jq

* Discogs and RED API keys
You can retrieve a Discogs personal access token here: https://www.discogs.com/settings/developers

# Usage

* Copy config.txt.example to config.txt

`cp config.txt.example config.txt`

* Fill in needed API keys

`nano config.txt` (...)

* Search for a barcode (without spaces)

`./dsrb.sh <barcode>`

# Examples

* This will find a single group: 
`./dsrb.sh 743218978821`

* This will result in multiple groups and requests:
`./dsrb.sh 4540399051123`

* This will result in a single request:
`./dsrb.sh 01704-61731-24`

Note: Examples might stop working due to the nature of their sources
