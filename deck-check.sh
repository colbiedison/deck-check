#!/bin/sh

cat <<LICENSE > /dev/null

    deck-check, a simple script to estimate when your steam deck order will be confirmed
    Copyright (C) 2022  ColbiesTheName

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

LICENSE

region=
model=
rtResTime=
gmd=
### Get options
while getopts r:m:t:u: name; do
	case $name in
		r)	region="$OPTARG"
		 ;;
		m)	model="$OPTARG"
		 ;;
		t)	rtResTime="$OPTARG"
		 ;;
		u)	gmd=$(echo "$OPTARG" | sed -E 's/.*s\///')
		 ;;
		?)	printf "Usage:\n"
			printf "\t%s -u<getmydeck URL>\n" $(basename "$0")
			printf "\t%s -r{US|UK|EU} -m{64|256|512} -t<rtReserveTime>\n" $(basename "$0")
			printf "\nRequirements: jq curl bc\n"
			exit 2
		 ;;
	esac
done

### Check options
badArgs=0

if [ -z "$gmd" ]; then
	if [ -z "$region" ]; then
		printf "You must specify region with -r.\n"
		badArgs=1
	fi

	if [ -z "$model" ]; then
		printf "You must specify model with -m.\n"
		badArgs=1
	fi

	if [ -z "$rtResTime" ]; then
		printf "You must specify your reservation time with -t.\n"
		badArgs=1
	fi
elif echo -n "$gmd" | grep -q -E "^(US|UK|EU)/(64|256|512)/[0-9]{10}"; then
	region=$(echo "$gmd" | cut -d '/' -f 1)
	model=$(echo "$gmd" | cut -d '/' -f 2)
	rtResTime=$(echo "$gmd" | cut -d '/' -f 3)
else
	printf 'Invalid URL "%s", enter the full getmydeck URL, or just "region/model/timestamp"\n' "$gmd"
	badArgs=1
fi


if ! echo -n "$region" | grep -q -E "^US\$|^us\$|^UK\$|^uk\$|^EU\$|^eu\$"; then
	printf 'Invalid region "%s", valid regions are US, UK, EU\n' "$region"
	badArgs=1
fi

if ! echo -n "$model" | grep -q -E "^64\$|^256\$|^512\$"; then
	printf 'Invalid model "%s", valid models are 64, 256, 512\n' "$model"
	badArgs=1
fi

if ! echo -n "$rtResTime" | grep -q -E "^[0-9]{10}\$"; then
	printf 'Invalid reservation time "%s", it should be 10 digits (seconds since the epoch)\n' "$rtResTime"
	badArgs=1
fi

if [ $badArgs -ne 0 ]; then
	exit 2
fi


printf '%s %sGB reserved at %s (%s)\n' "$region" "$model" "$rtResTime" "$(date -d @$rtResTime)"

### Talk to getmydeck
res=$(curl -s "https://getmydeck.ingenhaag.dev/api/v2/regions/$region/versions/$model/infos/$rtResTime")

### Cache response (for develpment purposes)
#res=$(cat res.json)
#echo "$res" > res.json

### Parse our values
currentPercentage=$(echo "$res" | sed -z -E "s/.*<li>You're | \% of the way there.*//g")
increasedPercentage=$(echo "$res" | jq '.personalInfo.historicData[0].increasedPercentage')
d0=$(echo "$res" | jq '.personalInfo.historicData[0].date' | xargs -I{} date -d "{}" -u +%s )
d1=$(echo "$res" | jq '.personalInfo.historicData[1].date' | xargs -I{} date -d "{}" -u +%s )

### Math
## Old and incorrect method, assuming the time delta is a week
#estimatedConfirmTime=$( \
# echo "scale=20;(100 - $currentPercentage) / $increasedPercentage * 7 * 24 * 60 * 60" \
# | bc \
# | cut -d '.' -f 1 \
# | xargs -iS date -d "S seconds" +%s \
#)
#
#estimatedConfirmTimeHuman=$(date -d "@$estimatedConfirmTime")

## New and hopefully more correct method
timeDelta=$((d0 - d1))
estimatedConfirmTime=$( \
 echo "scale=20;(100 - $currentPercentage) / $increasedPercentage * $timeDelta + $d0" \
 | bc \
 | cut -d '.' -f 1 \
)

estimatedConfirmTimeHuman=$(date -d "@$estimatedConfirmTime")

echo -e "time frame\t\t: $(($timeDelta / 3600)) hours"
echo -e "current percentage\t: $currentPercentage%"
echo -e "increase\t\t: $increasedPercentage%"
echo -e "estimated confirm time\t: $estimatedConfirmTime ($estimatedConfirmTimeHuman)"
