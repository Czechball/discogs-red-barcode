#!/bin/bash

# discogs-red-barcode

# Define user agent
USER_AGENT="discogs-red-barcode +https://github.com/Czechball/discogs-red-barcode"

# Check if config.txt exists
SCRIPTPATH="$( cd "$(dirname "$0")" || { echo -e "\e[91mERROR\e[0m: Script path cannot be found" ; exit 1; } >/dev/null 2>&1 ; pwd -P )"
CONFIGFILE="$SCRIPTPATH"/config.txt

# Load config
# shellcheck source=config.txt
source "$CONFIGFILE" || { echo -e "\e[91mERROR\e[0m: $CONFIGFILE doesn't exist in script path" ; exit 1; }

# Function for looking up given barcode on Discogs and retrieving its master ID
search_barcode()
{
	# Call Discogs API with /database/search?barcode= to lookup releases matching this barcode
	local DISCOGS_JSON
	DISCOGS_JSON=$(curl -s "https://api.discogs.com/database/search?barcode=$1" -H "Authorization: Discogs token=$DISCOGS_TOKEN" --user-agent "$USER_AGENT")

	# Parse json from Discogs and retrieve all master IDs (TODO: Doesn't handle errors, api usage limits etc..)
	local MASTER_IDS
	MASTER_IDS=$(echo "$DISCOGS_JSON" | jq '.results | .[] | .master_id' | xargs)

	if [[ "$MASTER_IDS" == "" ]]; then
		echo "Barcode not found on Discogs."
		return 1
	fi

	# Save list of master IDs in array
	MASTER_ID=($MASTER_IDS)

	# Compare every found master ID with the first found master ID so we can determine if all found master IDs are the same (we only found one release)
	for i in ${MASTER_ID[@]};
	do
		if [[ $i == ${MASTER_ID[0]} ]]; then
			LOOKUP_TYPE=master
		# If all master IDs are not the same, abort. TODO: List all found master IDs and let user choose which one to look for on RED
		else
			echo "Master IDs of all results are not the same, can't continue"
			return 1
		fi
	done

	# If there is no master release found (all values in MASTER_ID are 0), we check if we only got one result and if yes, search that on RED - TODO: List all found releases and let user choose which ones to look for on RED
	if [[ ${MASTER_ID[0]} == "0" ]]; then
		echo "Barcode has result with no master release"
	fi

	local NUM_RESULTS
	NUM_RESULTS=$(echo "$DISCOGS_JSON" | jq '.results | length')
	if [[ $NUM -lt 1 ]]; then
		# Extracting release info from release without master ID
		RESOURCE_URL=$(echo "$DISCOGS_JSON" | jq '.results[0].resource_url' | xargs)
		LOOKUP_TYPE=single
	else
		echo Error, no master ID and "$NUM_RESULTS" results
		return 1
	fi
}

# Function for retrieving info about release without master ID
lookup_release()
{
	local DISCOGS_JSON
	DISCOGS_JSON=$(curl -s "$1" -H "Authorization: Discogs token=$DISCOGS_TOKEN" --user-agent "$USER_AGENT")
	RELEASE_ARTIST=$(echo "$DISCOGS_JSON" | jq '.artists[0].name' | xargs)
	RELEASE_TITLE=$(echo "$DISCOGS_JSON" | jq '.title' | xargs)
	RELEASE_YEAR=$(echo "$DISCOGS_JSON" | jq '.year' | xargs)

}

# Function for retrieving info about found master ID and parse it so we can search for it on RED
lookup_master_release()
{
	# Call Discogs API with /masters/ to lookup master release
	local DISCOGS_JSON
	DISCOGS_JSON=$(curl -s "https://api.discogs.com/masters/$1" -H "Authorization: Discogs token=$DISCOGS_TOKEN" --user-agent "$USER_AGENT")

	# Parse artists (in an array), year and title of release
	RELEASE_ARTIST=$(echo "$DISCOGS_JSON" | jq '.artists | .[0] | .name' | xargs)
	RELEASE_YEAR=$(echo "$DISCOGS_JSON" | jq '.year' | xargs)
	RELEASE_TITLE=$(echo "$DISCOGS_JSON" | jq '.title' | xargs)
	
}

# Function for searching retrieved release on RED
red_query()
{

	# First, try to search with artist name, release name and year
	echo Trying to search red with artist "$RELEASE_ARTIST", group name "$RELEASE_TITLE" and year "$RELEASE_YEAR"
	RED_JSON=$(curl -s "https://redacted.ch/ajax.php?action=browse&artistname=$RELEASE_ARTIST&groupname=$RELEASE_TITLE&year=$RELEASE_YEAR" -H "Authorization: $RED_API_KEY")
	local NUM_RESULTS
	NUM_RESULTS=$(echo "$RED_JSON" | jq '.response.results[].groupId' | wc -l)
	GROUP_ID=$(echo "$RED_JSON" | jq '.response.results[0].groupId')
	if [[ $NUM_RESULTS -gt 0 ]]; then
		if [[ $NUM_RESULTS -gt 1 ]]; then

			# If there is more than one result (group IDs), link to manual search is returned
			echo -e "\e[92mFound $NUM_RESULTS matching torrents on RED, please check manually:\e[0m"
			echo "https://redacted.ch/torrents.php?action=browse&artistname=$RELEASE_ARTIST&groupname=$RELEASE_TITLE&year=$RELEASE_YEAR"
		else

			# If there is only one group ID, link to torrent group is returned
			echo -e "\e[92mRelease found on RED: https://redacted.ch/torrents.php?id=$GROUP_ID\e[0m"
		fi
	else

		# If no results are found, remove year from search parameters and continue...
		echo "Couldn't find any torrents with these parameters, trying to search without year..."
		sleep 2
		RED_JSON=$(curl -s "https://redacted.ch/ajax.php?action=browse&artistname=$RELEASE_ARTIST&groupname=$RELEASE_TITLE" -H "Authorization: $RED_API_KEY")
		NUM_RESULTS=$(echo "$RED_JSON" | jq '.response.results[].groupId' | wc -l)
		GROUP_ID=$(echo "$RED_JSON" | jq '.response.results[0].groupId')
		if [[ $NUM_RESULTS -gt 0 ]]; then
			if [[ $NUM_RESULTS -gt 1 ]]; then
				echo -e "\e[92mFound $NUM_RESULTS matching torrents on RED, please check manually:\e[0m"
				echo "https://redacted.ch/torrents.php?action=browse&artistname=$RELEASE_ARTIST&groupname=$RELEASE_TITLE"
			else
				echo -e "\e[92mRelease found on RED: https://redacted.ch/torrents.php?id=$GROUP_ID\e[0m"
			fi
		else

			# If no results are found, remove artist from search parameters and continue...
			echo "Couldn't find any torrents even without year, trying to only search the release name..."
			sleep 2
			RED_JSON=$(curl -s "https://redacted.ch/ajax.php?action=browse&searchstr=$RELEASE_TITLE" -H "Authorization: $RED_API_KEY")
			NUM_RESULTS=$(echo "$RED_JSON" | jq '.response.results[].groupId' | wc -l)
			GROUP_ID=$(echo "$RED_JSON" | jq '.response.results[0].groupId')
			if [[ $NUM_RESULTS -gt 0 ]]; then
				if [[ $NUM_RESULTS -gt 1 ]]; then
					echo -e "\e[92mFound $NUM_RESULTS matching torrents on RED, please check manually:\e[0m"
					echo "https://redacted.ch/ajax.php?action=browse&searchstr=$RELEASE_TITLE"
				else
					echo -e "\e[92mRelease found on RED: https://redacted.ch/torrents.php?id=$GROUP_ID\e[0m"
				fi

				# When only search result containing just the release name succeeds, also perform search for requests
				# (Search for requests is also performed when no results are found)
				echo "Release $RELEASE_TITLE is not on RED. Searching for requests..."
				sleep 2
				RED_JSON=$(curl -s "https://redacted.ch/ajax.php?action=requests&search=$RELEASE_ARTIST $RELEASE_TITLE" -H "Authorization: $RED_API_KEY")
				NUM_RESULTS=$(echo "$RED_JSON" | jq '.response.results[].requestId' | wc -l)
				if [[ $NUM_RESULTS -gt 0 ]]; then
					echo -e "\e[92mFound $NUM_RESULTS requests: https://redacted.ch/requests.php?&search=$RELEASE_ARTIST $RELEASE_TITLE\e[0m"
				else
					echo "Couldn't find any requests"
				fi
			fi
		fi
	fi
}

enter_barcode()
{
	echo still work to do...
}

# Define barcode as first positional argument
BARCODE="$1"

if [[ $BARCODE == "" ]]; then
	echo "Error, please enter a barcode"
	exit 1
fi

echo -e "Looking up barcode \e[1m""$BARCODE...""\e[0m"
search_barcode "$BARCODE" || { echo -e "\e[91mError when trying to search barcode on Discogs\e[0m"; exit 1; }
case "$LOOKUP_TYPE" in
	master )
		echo -e "\e[92mFound master ID \e[1m${MASTER_ID[0]}\e[0m\e[92m, looking up metadata...\e[0m"
		lookup_master_release "${MASTER_ID[0]}" || { echo -e "\e[91mError when looking up the master ID\e[0m"; exit 1; }
		;;
	single )
		echo -e "\e[92mFound single release \e[1m$RESOURCE_URL\e[0m\e[92m, looking up metadata...\e[0m"
		lookup_release "$RESOURCE_URL" || { echo -e "\e[91mError when looking up the release\e[0m"; exit 1; }
		;;
		* )
	echo "Unknown error"
	exit 1
		;;
esac
if [[ $RELEASE_YEAR == "0" ]]; then
	RELEASE_YEAR="Unknown"
fi
echo
echo Main artist:	"$RELEASE_ARTIST"
echo Release title:	"$RELEASE_TITLE"
echo Release year:	"$RELEASE_YEAR"
echo

red_query
