#!/usr/bin/env bash
  #==============================================
  # Project: iadl.sh v1.1
  # Author:  ConzZah / (c) 2026
  # Last Modification: 2/8/26 4:30 AM
  #==============================================

init () {
## check for missing deps
deps="fzf curl grep cut tr"
for dep in $deps; do 
! command -v "$dep" >/dev/null && \
echo -e "\n--> MISSING DEPENDENCY: $dep\n" && exit 1
done

## if $1 is -fn, set flag and shift. useful in scripts
fn=""; [ "$1" = '-fn' ] && fn="y" && shift

url=""; base_url="https://archive.org"
[ -z "$1" ] && echo -e "\n--> PLS SUPPLY SOME ARCHIVE.ORG LINK\n" && exit 1

## get url 
[ -n "$1" ] && url="$1"

## make sure url is valid
! grep -q "$base_url.*" <<< "$url" && echo -e "\n--> THIS ISN'T A VALID ARCHIVE.ORG LINK\n" && exit 1

## should url contain 'details', replace it with 'download'
grep -q "$base_url/details.*" <<< "$url" && url="${url/details/download}"
}


browse () {
html=""; items=""; header=""; location=""; last_char=""

## count slashes in the url, if we have 4 slashes, we're missing the trailing slash, add it.
sc="$(grep -o '/' <<< "$url"| wc -l)" && [ "$sc" = "4" ] && sc="$((sc + 1))" && url="${url}/"

## get header
header="$(curl -sLI "$url")"

## get $location to figure out what we're dealing with
location="$(grep -o 'location.*' <<< "$header"| grep -v '.onion')"

## NOTE: $location will only contain anything if:
## - the input is a direct link to a file, OR
## - the user is accessing a subdir and forgot the trailing slash
## we can find this out by checking if the $last_char of location is equal to '/'
[ -n "$location" ] && {

last_char="$(grep -o 'items.*'  <<< "$location"| tail -n1| rev| cut -c 2)"

[ "$last_char" = '/' ] && sc="$((sc + 1))" && url="${url}/"

## should $last_char NOT be equal to '/' then our input must be a direct link to a file 
## in which case, we get rid of the filename in $url and assign it to $chosen_item 
[ "$last_char" != '/' ] && {
chosen_item="$(echo "$url"| rev| cut -d '/' -f 1| rev)"
url="$(echo "$url"| rev| cut -d '/' -f 2-| rev)"
sc="$((sc - 1))"; url="${url}/"
}
}


## fetch $html
html="$(curl -sL "$url")"

## check for 404 and exit if we got one
grep -q '404 Not Found' <<< "$html" && echo -e "--> ERROR: 404" && exit 1

## truncate $html to allow for faster processing
html="$(grep -A9999 '<tbody>' <<< "$html"| grep -B9999 '</tbody>')"

## $items is the array of filenames. 
## delim = '^', f1=urlencoded-filenames f2=human-readable-filenames (we obviously need both..)
## EXAMPLE OUTPUT: 'The-Pigeons-Around-Here-Aren%27t-Real.mp3^The-Pigeons-Around-Here-Aren't-Real.mp3'
items="$(echo "$html"| grep -o '<a href=".*</td>'| tr '>' '^'| tr '<' '"'| cut -d '"' -f 3-4| sed 's#"^#^#g')"

## the first line of $items is always the '<UP>' button
items="$(sed -e '1 d' -e '/^$/ d' <<< "$items")"

## if $sc is 5 (meaning we're @ the root dir), then don't show the '<UP>' button
## else, give user the option to jump up directories
[ "$sc" -gt "5" ] && items="$(sed '1 i \^<UP>' <<< "$items")"

## get filesizes and build index
index=""
while read -r fname; do
fsize="$(grep -A2 "$(echo "$fname"| cut -d '^' -f 1)" <<< "$html"| tail -n1| tr '<' '>'| cut -d '>' -f 3)"
## check for '-' <-- NOTE: '-' indicates a directory, so we label it as such
[ "$fsize" = "-" ] && fsize="<DIR>"

index="$fname^$fsize\n$index" ### <--- NOTE: '^' <-- SEPERATES: fn-urlencoded,fn-human-readable,fsize //// '\n' <--- SEPERATES ENTRIES
fname=""; fsize=""
done <<< "$items"

## realize newlines with echo -e, and delete any empty lines
index="$(echo -e "$index"| sed '/^$/d')"

## let the user choose an item with fzf
[ -z "$chosen_item" ] && chosen_item="$(cut -d '^' -f 2- <<< "$index"| sed 's#\^# ~ #g'| fzf --tac| sed 's# ~ #\^#g'| cut -d '^' -f 1)"

## double check $chosen_item for existence if it's not '<UP>'
[ -n "$chosen_item" ] && [ "$chosen_item" != '<UP>' ] && {
chosen_item="$(grep -m1 "$chosen_item" <<< "$index"| cut -d '^' -f 1)"
chosen_item_hr="$(grep -m1 "$chosen_item" <<< "$index"| cut -d '^' -f 2)"
}


## exit if user didn't choose an item, or there was no match when double checking
[ -z "$chosen_item" ] && echo -e "--> ERROR: NO ITEM CHOSEN." && exit 1

## check if the item had a size of '-' <-- NOTE: this indicates a directory
chosen_item_fsize="$(grep -m1 "$chosen_item" <<< "$index"| cut -d '^' -f 3)"

## if the $chosen_item is <UP>, decrease $sc by one, edit $url & run browse again
[ "$chosen_item" = '<UP>' ] && sc="$((sc - 1))" && \
url="$(echo "$url"| cut -d '/' -f 1-"${sc}")" && chosen_item="" && browse

## if the $chosen_item is a file, add it to $url and start the downloader
[ "$chosen_item_fsize" != '<DIR>' ] && url="${url}${chosen_item}" && download

## if the $chosen_item is a directory, add it to $url, increase $sc by 1, and run browse again
[ "$chosen_item_fsize" = '<DIR>' ] && \
sc="$((sc + 1))" && url="${url}${chosen_item}" && \
chosen_item="" && chosen_item_fsize="" && browse
}

download () {
## if the '-fn' option was specified, only echo the filename
[ -n "$fn" ] && echo "$chosen_item_hr"
## otherwise show everything
[ -z "$fn" ] && echo -e "\n--> DOWNLOADING: $chosen_item_hr ~ $chosen_item_fsize\n"
## download the file and exit
curl -#Lo "$chosen_item_hr" "$url" && exit 0 || exit 1
}


init "$@"; browse
