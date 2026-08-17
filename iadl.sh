#!/usr/bin/env sh

### /// iadl.sh v1.5 // ConzZah // 2026-08-17 02:28 ///

## NOTE: THE FUNCTION: 'exclude_from_index', EXCLUDES CERTAIN FILETYPES LIKE .*.afpk AND .*_spectrogram.png
## IF YOU NEED ANY OF THOSE, COMMENT THEM OUT!!

init () {
## check for $missing deps
missing_deps=""
deps="md5sum mktemp paste wget grep fzf sed cat cut rev tr 7z"
for dep in $deps; do
! command -v "$dep" >/dev/null && \
missing_deps="$missing_deps $dep"
done

## if $missing_deps is nonzero, tell the user which are missing and exit.
[ -n "$missing_deps" ] && \
printf "\n%s\n%s\n\n" "--> ERROR: MISSING DEPENDENCIES:" "$missing_deps" && exit 1

base_url="archive.org"
url=""

## run the case statement until there are no args left
## ('$#' = number of arguments passed)
until [ "$#" = "0" ]; do
case "$1" in

## $url processing
## if $1 contains $base_url, check if we already have $url set.
## if we don't have $url set, process $url.
*"$base_url"*) [ -z "$url" ] && url="$1" && {

## if $url does NOT contain 'https://', add it
printf '%s\n' "$url"| grep -q 'https://' || url="https://${url}"

## should $url contain 'details', replace it with 'download'
printf "%s" "$url"| grep -q "$base_url/details.*" && url="$(printf "%s" "$url"| sed 's#details#download#')"
}
;;

## custom output directory (-o)
## NOTE: by default we'd download to the dir from which iadl was launched.
## check if the custom output dir exists and is writeable, then cd to it.
'o'|'-o'|'--output-dir') [ ! -d "$2" ] || [ ! -w "$2" ] && \
printf '%s\n' "--> ERROR: '$2' IS EITHER NOT WRITEABLE, OR DOESN'T EXIST." && exit 1
{ cd "$2" || exit 1; shift ;} 
;;

## help page
'h'|'-h'|'help'|'-help') help ;;
esac
shift
done

## double check if $url is set
[ -z "$url" ] && printf "\n--> PLS SUPPLY SOME ARCHIVE.ORG LINK\n\n" && exit 1

## create $tmpdir
## if /run/user/1000 is available, use it instead of mktemp
## REASON: /run/user/1000 runs in RAM.
tmpdir=""
[ -d "/run/user/1000" ] && {
tmpdir="/run/user/1000/iadl-wd"

## if it should already exist, clean it up.
[ -d "$tmpdir" ] && rm -rf "$tmpdir"
mkdir -p "$tmpdir"
}

## if $tmpdir is zero, fall back to mktemp
[ -z "$tmpdir" ] && tmpdir="$(mktemp -d)"

## set $tmpdir paths
header="$tmpdir/header"
fnames="$tmpdir/fnames"
fsizes="$tmpdir/fsizes"
index="$tmpdir/index"
response="$tmpdir/response"
files_xml="$tmpdir/files.xml"
current_dir="$tmpdir/current_dir"

## count slashes in $url, if we have 4 slashes, we're missing the trailing slash, add it.
## wrong example: https://archive.org/download/example_identifier
count_slashes; [ "$sc" = "4" ] && sc="$((sc + 1))" && url="${url}/"

## get $header and extract the http response
wget -qS --spider "$url" 2> "$header"
sed -n '1 p' "$header" > "$response"

## if $response contains any http code other than 200 or 302, evac
## 200 = OK 
## 302 = REDIRECT
! grep -q 'HTTP.*200\|HTTP.*302' "$response" && printf '\n%s\n\n' "--> ERROR: $(cat "$response")" && exit 1

## get the item identifier
get_item_identifier

## get $location from $header
location="$(grep -o 'location.*' "$header" | grep -v '.onion'| grep -o 'https.*'| tail -n1)"

## NOTE: $location will only contain anything if:
## - the input is a direct link to a file, OR
## - the user is accessing a subdir and forgot the trailing slash

[ -n "$location" ] && {
## get the $last_char of $location
## if $location contains anything, and the $last_char is a slash, 
## we know it's a subdir with a forgotten trailing slash and can just add one to the $url
last_char="$(printf '%s\n' "$location"| rev| cut -c 2)"
[ "$last_char" = "/" ] && url="${url}/" && sc="$((sc + 1))"

## if the $last_char of $location is anything else than a slash, we definetly have a single file,
## in which case we strip the filename from $url and assign it to $chosen_item_hr.
## this however makes us lose the trailing slash of $url, so we gotta add it back.
[ "$last_char" != "/" ] && {
chosen_item_hr="$(printf "%s" "$url"| rev| cut -d '/' -f 1| rev)"
url="$(printf "%s" "$url"| rev| cut -d '/' -f 2-| rev)"
single_file="y"; url="${url}/"
}
}

## get files.xml of the item
get_files_xml

## get all filenames in $files_xml (creates $fnames)
get_filenames

## get filesizes and convert them (creates $fsizes)
get_filesizes

## create index
paste -d '^' "$fnames" "$fsizes" > "$index"

## excludes certain filetypes from index  (like .afpk) 
exclude_from_index

## run browse (self explanatory, lets the user choose files and traverse dirs).
browse
}


browse () {
count_slashes
## create the index for the current dir (creates $current_dir)
create_current_dir_index

## let the user choose an item
chosen_item="$(sed 's#\^# ~ #g' "$current_dir"| fzf| sed 's# ~ #\^#g')"

## get $chosen_item_hr
chosen_item_hr="$(printf '%s\n' "$chosen_item"| cut -d '^' -f 1)"

## get the filesize of $chosen_item_hr
chosen_item_fsize="$(printf '%s\n' "$chosen_item"| cut -d '^' -f 2)"

## exit if user didn't choose an item
[ -z "$chosen_item" ] && printf "\n--> NO ITEM CHOSEN.\n\n" && exit 1

## if the user did choose an item that is NEITHER:
## <UP> NOR <DOWNLOAD ENTIRE DIRECTORY> / <DOWNLOAD ENTIRE ITEM IN ZIP FORMAT>,
## AND $chosen_item_fsize is NOT <DIR>, we set $single_file
[ "$chosen_item_fsize" != '<UP>' ] && [ "$chosen_item_fsize" != '<DIR>' ] && \
[ "$chosen_item_fsize" !=  '<DOWNLOAD ENTIRE ITEM IN ZIP FORMAT>' ] && \
[ "$chosen_item_fsize" != '<DOWNLOAD ENTIRE DIRECTORY>' ] && \
single_file="y"

## if $single_file is set, invoke download_single_file
[ -n "$single_file" ] && download_single_file

## if the $chosen_item_fsize is <UP>,
## decrease $sc by one, edit $url & run browse again
[ "$chosen_item_fsize" = '<UP>' ] && sc="$((sc - 1))" && {
url="$(printf "%s" "$url"| cut -d '/' -f 1-"${sc}")"
url="${url}/"
browse
}

## if the $chosen_item_fsize is <DIR>, 
## add  $chosen_item_hr to $url, increase $sc by 1, and run browse again
[ "$chosen_item_fsize" = '<DIR>' ] && {
sc="$((sc + 1))"; url="${url}${chosen_item_hr}"
browse
}

## if the $chosen_item_fsize is '<DOWNLOAD ENTIRE DIRECTORY>', invoke download_entire_dir
[ "$chosen_item_fsize" = '<DOWNLOAD ENTIRE DIRECTORY>' ] && download_entire_dir

## if the $chosen_item_fsize is '<DOWNLOAD ENTIRE ITEM IN ZIP FORMAT>', invoke download_as_zip
[ "$chosen_item_fsize" = '<DOWNLOAD ENTIRE ITEM IN ZIP FORMAT>' ] && download_as_zip
}


create_current_dir_index () {
## create the index for the current dir (creates $current_dir)
## (this function basically contains the logic to jump up & down and list directories)
## get the 6th field onwards from $url
tree="$(printf '%s\n' "$url"| cut -d '/' -f 6-)"
sct="" ## <-- $sct = slash-count for $tree

## if $sc is 5, we're @ root and $tree is gonna be empty, set $sct to 1 if that's the case.
[ "$sc" = "5" ] && sct="1"

## get the slash-count of $tree
## if $sct is empty. count slashes and add 1
[ -z "$sct" ] && sct="$(($(printf '%s\n' "$tree"| grep -o '/'| wc -l) + 1))"

## get subdirs of current dir and mark them as <DIR>
grep -o "^${tree}.*" "$index"| cut -d '/' -f "${sct}"| sort| uniq| grep -v '\^.*'| sed -e 's#$#/#g' -e '/^$/ d' -e 's#$#\^<DIR>#g' > "$current_dir"

## get files in the current dir
grep -o "^${tree}.*" "$index"| sort| uniq| cut -d '/' -f "${sct}"| grep '\^' >> "$current_dir"

## if $sc is greater than 5, show the '<UP>' button
[ "$sc" -gt "5" ] && sed -i '1 i \^<UP>' "$current_dir"

## give the user the option to download the current directory (including subdirs).
printf '%s\n' "^<DOWNLOAD ENTIRE DIRECTORY>" >> "$current_dir"

## give the user the option to download the whole item in zip format
## NOTE: (only if we're @ root / if we have a slash count of 5)
[ "$sc" = "5" ] && printf '%s\n' "^<DOWNLOAD ENTIRE ITEM IN ZIP FORMAT>" >> "$current_dir"
}


## get the item identifier
get_item_identifier () { identifier="$(printf '%s\n' "$url"| cut -d '/' -f 5)" ;}


get_files_xml () {
## get files.xml so we are able to compare checksums
## download it only if it doesn't exist yet.
[ ! -f "$files_xml" ] && {
wget -qO "$files_xml" "https://archive.org/download/${identifier}/${identifier}_files.xml" || exit 1

## delete ${identifier}_files.xml from $files_xml, because of multiple reasons:
## for one: the md5sum is ALWAYS WRONG.
## for two: there is no filesize, which would mess up our list.
## (check any files.xml, if you don't believe me, i don't care lol).
sed -i "s#<file name.*${identifier}_files.xml.*##g" "$files_xml"
}
}


get_filenames () {
## get all filenames in $files_xml and create $fnames
grep -o "file name=.*" "$files_xml"| cut -d '"' -f 2 > "$fnames"
}


get_filesizes () {
## gets filesizes and converts them
## NOTE: this starts with MB and goes down to 
## the filesizes in $files_xml are ALWAYS	in bytes.
printf '%s\n' "" > "$fsizes"
fsize_bytes="$(grep -o '<size>.*' "$files_xml"| tr '<' '>'| cut -d '>' -f 3)"

for fb in $fsize_bytes; do

## convert bytes to mb
hr="MB"
test="$((fb / 1048576))"

## if $test is greater than 0, lock in & continue
[ "$test" -gt "0" ] && \
printf '%s\n' "${test} ${hr}" >> "$fsizes" && continue

## if $test = 0, convert mb to kb
[ "$test" = "0" ] && test="$((fb / 1024))" && hr="KB"

## if $test is greater than 0, lock in & continue
[ "$test" -gt "0" ] && \
printf '%s\n' "${test} ${hr}" >> "$fsizes" && continue

## if $test = is STILL 0, use the byte value ($fb)
[ "$test" = "0" ] && test="$fb" && hr="B"

## if $test is greater than 0, lock in & continue
[ "$test" -gt "0" ] && \
printf '%s\n' "${test} ${hr}" >> "$fsizes" && continue
done

## delete any empty lines from $fsizes with sed
sed -i '/^$/ d' "$fsizes"
}


exclude_from_index () {
## excludes certain filetypes from index 
## NOTE: IF YOU NEED ANY OF THOSE, COMMENT OUT THE RESPECTIVE LINES!!

## exclude all .afpk files
sed -i 's#.*.afpk.*##g' "$index"

## exclude all .*_spectrogram.png files
sed -i 's#.*_spectrogram.png.*##g' "$index"
}


count_slashes () {
## count slashes in $url
sc="$(printf "%s" "$url"| grep -o '/'| wc -l)"
}


check_md5 () {
## check md5sum with the downloaded file and delete it if they shouldn't match
## only run this function if $chosen_item_hr is not ${identifier}_files.xml
## (${identifier}_files.xml is the ONLY file that ALWAYS fails)
[ "${chosen_item_hr}" = "${identifier}_files.xml" ] && return 0

printf '\n%s\n' "--> CHECKING MD5SUM FOR: $chosen_item_hr"

[ -z "$zip" ] && {
## get md5 of local file
md5_local=""
md5_local="$(md5sum "${chosen_item_hr}"| cut -d ' ' -f 1)"
}

[ -n "$zip" ] && {
## check md5sums inside the zip file with 7zip, if $zip is set, so we don't have to extract it just to compare them
md5_local="$(7z t "${identifier}/${identifier}.zip" "$chosen_item_hr" -scrcmd5| grep 'MD5'| rev| cut -d ' ' -f 1| rev)"
}

## if $md5local is still empty, md5sum couldn't find the file.
[ -z "$md5_local" ] && printf '\n%s\n' "--> ERROR: MD5SUM FAILED." && exit 1

## check if $md5_local can be found in $files_xml
md5="$(grep -m1 -o "$md5_local" "$files_xml")"
[ "$md5" != "$md5_local" ] && {
printf '%s\n' "--> ERROR: MD5SUMS DON'T MATCH, $chosen_item_hr CORRUPTED."
[ -f "${chosen_item_hr}" ] && rm -f "${chosen_item_hr}"
return 1
}

printf '%s\n' "--> MD5SUMS FOR: $chosen_item_hr MATCH!"
return 0
}


download_single_file () {
mkdir -p "$identifier"
cd "$identifier" || exit 1
printf "\n%s\n" "--> DOWNLOADING: $chosen_item_hr ~ $chosen_item_fsize"

## download the file, check_md5 and exit
wget --show-progress -qO "${chosen_item_hr}" "${url}${chosen_item_hr}"
check_md5 || exit 1
exit
}


download_entire_dir () {
## downloads the current directory and its subdirs
## if $tree is nonzero, it means we're in a subdir.
## in this case, limit $index to the current dir + subdirs
[ -n "$tree" ] && {
grep -o "^${tree}.*" "$index" > "/tmp/tmp_index"
mv "/tmp/tmp_index" "$index"
}

## strip filesizes from $index
cut -d '^' -f 1 "$index" > "/tmp/tmp_index"
mv "/tmp/tmp_index" "$index"

## prepend 'https://archive.org/download/${identifier}/' to $index
sed -i "s#^#https://archive.org/download/${identifier}/#g" "$index"


## get filetypes
ftypes="$(rev < "$index"| cut -d '.' -f 1| rev| sort| uniq)"

## ask the user which filetypes they'd like to exclude
excluded_ftypes="$(printf '%s\n%s\n' "<DON'T EXCLUDE ANYTHING>" "$ftypes"| \
fzf --multi --header="EXCLUDE FILETYPES (USE TAB TO SELECT MULTIPLE)")"

## if $excluded_filetypes is empty, tell the user to make a selection & exit
[ -z "$excluded_ftypes" ] && printf '%s\n' "--> PLEASE MAKE A SELECTION" && exit 1

## if $index is empty, the user tried to exclude everything
[ "$(wc -l < "$index")" = "0" ] && printf '%s\n' "--> INDEX IS EMPTY, NOTHING TO DOWNLOAD." && exit 1

## exclude selected filetypes
[ -n "$excluded_ftypes" ] && {
printf '%s\n' "$excluded_ftypes"| while read -r ftype; do
sed -i -e "s#.*${ftype}.*##g" -e '/^$/ d' "$index"
done
}

## download recursively
## (-l 0 = infinite recursion, we (should) get every subdir)
## (-nc = no clobber (don't download already existing files))
## (--no-host-directories & --cut-dirs=1 = ensure that the top dir which will be created, is actually the $identifier)
wget -r -l 0 -nc -i "$index" --no-host-directories --cut-dirs=1

## overwrite $index with the files you just downloaded
find "${identifier}/${tree}" -type f > "$index"

## check md5sums
while read -r chosen_item_hr; do
check_md5 || exit 1
done < "$index"
exit
}


download_as_zip () {
## downloads entrie item in zip format
mkdir	-p "${identifier}"
printf '%s\n' "--> DOWNLOADING: ${identifier}.zip"
wget --show-progress -qO "${identifier}/${identifier}.zip" "https://archive.org/compress/${identifier}"

## get list of files inside the zip archive, and overwrite $index
7z l "${identifier}/${identifier}.zip"| tr -s ' '| rev| cut -d ' ' -f 1| rev| \
grep -A 9999 '\-\-\-\-\-\-\-'| sed -e 's#-------*##g' -e '1 d' -e '$ d' -e '/^$/ d' > "$index"

## set $zip (this tells check_md5 to compare from within zip archives, instead of from files)
zip="y"

## check md5sums
while read -r chosen_item_hr; do
check_md5 || exit 1
done < "$index"
exit
}

## help page
_help='
 $$\                 $$\ $$\ 
 \__|                $$ |$$ |
 $$\  $$$$$$\   $$$$$$$ |$$ |
 $$ | \____$$\ $$  __$$ |$$ |
 $$ | $$$$$$$ |$$ /  $$ |$$ |
 $$ |$$  __$$ |$$ |  $$ |$$ |
 $$ |\$$$$$$$ |\$$$$$$$ |$$ |
 \__| \_______| \_______|\__|

   /// ConzZah // 2026 ///

 ARCHIVE.ORG ITEM BROWSER/DOWNLOADER.
 
 YOU CAN DOWNLOAD:
 - INDIVIDUAL FILES
 - THE ENTIRE ITEM IN ZIP FORMAT
 - ENTIRE DIRECTORIES (RECURSIVELY)
 
 OPTIONS:

 -o     set custom output dir

 USAGE:
 
 sh iadl [archive.org url] [option]
'
help () { printf '%s\n' "$_help"; exit ;}

[ -z "$1" ] && help

init "$@"; browse
