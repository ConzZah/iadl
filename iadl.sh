#!/usr/bin/env sh
  #==============================================
  # Project: iadl.sh v1.4
  # Author:  ConzZah / (c) 2026
  # Last Modification: 2/17/26 12:50 PM
  #==============================================

init () {
## check for missing deps
deps="mktemp paste curl grep fzf sed cat cut tr"
for dep in $deps; do
! command -v "$dep" >/dev/null && \
printf "%s" "\n--> MISSING DEPENDENCY: $dep\n\n" && exit 1
done

## if $1 is -fn, set flag and shift. useful in scripts
fn=""; [ "$1" = '-fn' ] && fn="y" && shift

url=""; base_url="https://archive.org"
[ -z "$1" ] && printf "\n--> PLS SUPPLY SOME ARCHIVE.ORG LINK\n\n" && exit 1

## get $url
[ -n "$1" ] && url="$1"

## make sure $url is valid
printf "%s" "$url"| grep -vq "$base_url.*" && printf "\n --> THIS ISN'T A VALID ARCHIVE.ORG LINK\n\n" && exit 1

## should $url contain 'details', replace it with 'download'
printf "%s" "$url"| grep -q "$base_url/details.*" && url="$(printf "%s" "$url"| sed 's#details#download#')"

## create $tmpdir if nonexistant.
[ ! -f '.tmpdir' ] || [ ! -d "$(cat '.tmpdir')" ] && \
tmpdir="$(mktemp -d)" && printf "%s" "$tmpdir" > '.tmpdir'

[ -f ".tmpdir" ] && [ -d "$(cat '.tmpdir')" ] && tmpdir="$(cat '.tmpdir')" || exit 1

## set $tmpdir paths
header="$tmpdir/header"
raw_html="$tmpdir/raw.html"
trun_html="$tmpdir/trun.html"
items="$tmpdir/items"
fsizes="$tmpdir/fsizes"
index="$tmpdir/index"

## clean up $tmpfiles in $tmpdir, should they exist
tmpfiles="$header $raw_html $trun_html $items $fsizes $index"
for tmpfile in $tmpfiles; do
[ -f "$tmpfile" ] && rm -f "$tmpfile"
done
}


browse () {
## count slashes in the url, if we have 4 slashes, we're missing the trailing slash, add it.
sc="$(printf "%s" "$url"| grep -o '/'| wc -l)" && [ "$sc" = "4" ] && sc="$((sc + 1))" && url="${url}/"

## get $header
curl -sLIo "$header" "$url"

## check $header for 404 and exit if we got one
grep -q '404' "$header" && printf "\n--> ERROR 404\n\n" && exit 1

## get $location to figure out what we're dealing with
location="$(grep -o 'location.*' "$header" | grep -v '.onion')"

## NOTE: $location will only contain anything if:
## - the input is a direct link to a file, OR
## - the user is accessing a subdir and forgot the trailing slash
## we can find this out by checking if the $last_char of location is equal to '/'

[ -n "$location" ] && {

last_char="$(printf "%s" "$location"| grep -o 'items.*'| tail -n1| rev| cut -c 2)"

[ "$last_char" = '/' ] && sc="$((sc + 1))" && url="${url}/"

## should $last_char NOT be equal to '/' then our input must be a direct link to a file
## in which case, we get rid of the filename in $url and assign it to $chosen_item
[ "$last_char" != '/' ] && {
chosen_item="$(printf "%s" "$url"| rev| cut -d '/' -f 1| rev)"
url="$(printf "%s" "$url"| rev| cut -d '/' -f 2-| rev)"
sc="$((sc - 1))"; url="${url}/" ;}
}

## fetch $raw_html
curl -sLo "$raw_html" "$url"

## truncate $raw_html to allow for faster processing
grep -A9999 '<tbody>' "$raw_html"| grep -B9999 '</tbody>' > "$trun_html"

## $items contains the array of filenames.
## delim = '^', f1=urlencoded-filenames f2=human-readable-filenames (we obviously need both..)
## EXAMPLE OUTPUT: 'The-Pigeons-Around-Here-Aren%27t-Real.mp3^The-Pigeons-Around-Here-Aren't-Real.mp3'
grep -o '<a href=".*</td>' "$trun_html"| tr '>' '^'| tr '<' '"'| cut -d '"' -f 3-4| sed -e 's#"^#^#g' -e 's#\&amp;#\&#g' > "$items"

## get $fsizes for $items
grep '<td>' "$raw_html"| tr '<' '>'| cut -d '>' -f 3| grep -v '................'| tr -s '\n'| sed 's#-#<DIR>#g' > "$fsizes"

## the first line of $items and $fsizes is always the '<UP>' button
sed -i -e '1 d' -e '/^$/ d' "$items" "$fsizes"

## if $sc is 5 (meaning we're @ the root dir), then don't show the '<UP>' button
## else, give user the option to jump up directories
[ "$sc" -gt "5" ] && sed -i '1 i \^<UP>' "$items" && sed -i '1 i \-' "$fsizes"

## create index
paste -d '^' "$items" "$fsizes" > "$index"

## let the user choose an item with fzf
[ -z "$chosen_item" ] && chosen_item="$(cut -d '^' -f 2- "$index"| sed 's#\^# ~ #g'| fzf| sed 's# ~ #\^#g'| cut -d '^' -f 1)"

## double check $chosen_item for existence if it's not '<UP>'
[ -n "$chosen_item" ] && [ "$chosen_item" != '<UP>' ] && {
chosen_item="$(grep -m1 "$chosen_item" "$index"| cut -d '^' -f 1)"
chosen_item_hr="$(grep -m1 "$chosen_item" "$index"| cut -d '^' -f 2)"
}

## exit if user didn't choose an item, or there was no match when double checking
[ -z "$chosen_item" ] && printf "\n--> NO ITEM CHOSEN.\n\n" && exit 1

## check if the item had a size of '-' <-- NOTE: this indicates a directory
chosen_item_fsize="$(grep -m1 "$chosen_item" "$index"| cut -d '^' -f 3)"

## if the $chosen_item is <UP>, decrease $sc by one, edit $url & run browse again
[ "$chosen_item" = '<UP>' ] && sc="$((sc - 1))" && \
url="$(printf "%s" "$url"| cut -d '/' -f 1-"${sc}")" && chosen_item="" && browse

## if the $chosen_item is a file, add it to $url and start the downloader
[ "$chosen_item_fsize" != '<DIR>' ] && url="${url}${chosen_item}" && download

## if the $chosen_item is a directory, add it to $url, increase $sc by 1, and run browse again
[ "$chosen_item_fsize" = '<DIR>' ] && {
sc="$((sc + 1))"; url="${url}${chosen_item}"
chosen_item=""; chosen_item_fsize=""; browse ;}
}


download () {
## if the '-fn' option was specified, only print the filename
[ -n "$fn" ] && printf "%s" "$chosen_item_hr"
## otherwise show everything
[ -z "$fn" ] && printf "%s" "\n--> DOWNLOADING: $chosen_item_hr ~ $chosen_item_fsize\n\n"
## download the file and exit
curl -#Lo "$chosen_item_hr" "$url" && exit 0 || exit 1
}

init "$@"; browse
