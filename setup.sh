#!/bin/bash
set -eu

check_command() {
	command -v "$1" >/dev/null 2>&1
}

if ! check_command jq; then
	echo "jq not found. Install it from https://stedolan.github.io/jq"
	exit 1
fi

OS_NAME=$(echo "$RUNNER_OS" | awk '{print tolower($0)}')
ARCH_NAME=$(echo "$RUNNER_ARCH" | awk '{print tolower($0)}')
MANIFEST_BASE_URL="https://storage.googleapis.com/flutter_infra_release/releases"
MANIFEST_JSON_PATH="releases_$OS_NAME.json"
MANIFEST_URL="$MANIFEST_BASE_URL/$MANIFEST_JSON_PATH"

filter_by_channel() {
	jq --arg channel "$1" '[.releases[] | select($channel == "any" or .channel == $channel)]'
}

filter_by_arch() {
	jq --arg arch "$1" '[.[] | select(.dart_sdk_arch == $arch or ($arch == "x64" and (has("dart_sdk_arch") | not)))]'
}

filter_by_version() {
	jq --arg version "$1" '.[].version |= gsub("^v"; "") | (if $version == "any" then .[0] else (map(select(.version == $version or (.version | startswith(($version | sub("\\.x$"; "")) + ".")) and .version != $version)) | .[0]) end)'
}

not_found_error() {
	echo "Unable to determine Flutter version for channel: $1 version: $2 architecture: $3"
}

transform_path() {
	if [ "$OS_NAME" = windows ]; then
		echo "$1" | sed -e 's/^\///' -e 's/\//\\/g'
	else
		echo "$1"
	fi
}

download_archive() {
	archive_url="$MANIFEST_BASE_URL/$1"
	archive_name=$(basename "$1")
	archive_local="$RUNNER_TEMP/$archive_name"

	curl --connect-timeout 15 --retry 5 "$archive_url" >"$archive_local"

	mkdir -p "$2"

	case "$archive_name" in
	*.zip)
		EXTRACT_PATH="$RUNNER_TEMP/_unzip_temp"
		unzip -q -o "$archive_local" -d "$EXTRACT_PATH"
		# Remove the folder again so that the move command can do a simple rename
		# instead of moving the content into the target folder.
		# This is a little bit of a hack since the "mv --no-target-directory"
		# linux option is not available here
		rm -r "$2"
		mv "$EXTRACT_PATH"/flutter "$2"
		rm -r "$EXTRACT_PATH"
		;;
	*)
		tar xf "$archive_local" -C "$2" --strip-components=1
		;;
	esac

	rm "$archive_local"
}

flutter_cache_key=""
flutter_cache_key=""
flutter_pub_cache_key=""
flutter_pub_cache_key=""
PRINT_ONLY=""
TEST_MODE=false
ARCH=""
flutter_version=""
flutter_version_file=""
flutter_git_url=""

while getopts 'tc:k:d:l:pa:n:f:g:' flag; do
	case "$flag" in
	c) flutter_cache_key="$OPTARG" ;;
	k) flutter_cache_key="$OPTARG" ;;
	d) flutter_pub_cache_key="$OPTARG" ;;
	l) flutter_pub_cache_key="$OPTARG" ;;
	p) PRINT_ONLY=true ;;
	t) TEST_MODE=true ;;
	a) ARCH="$(echo "$OPTARG" | awk '{print tolower($0)}')" ;;
	n) flutter_version="$OPTARG" ;;
	f)
		flutter_version_file="$OPTARG"
		if [ -n "$flutter_version_file" ] && ! check_command yq; then
			echo "yq not found. Install it from https://mikefarah.gitbook.io/yq"
			exit 1
		fi
		;;
    g) flutter_git_url="$OPTARG" ;;
	?) exit 2 ;;
	esac
done

[ -z "$ARCH" ] && ARCH="$ARCH_NAME"

if [ -n "$flutter_version_file" ]; then
	if [ -n "$flutter_version" ]; then
		echo "Cannot specify both a version and a version file"
		exit 1
	fi

	flutter_version="$(yq eval '.environment.flutter' "$flutter_version_file")"
fi

ARR_CHANNEL=("${@:$OPTIND:1}")
flutter_channel="${ARR_CHANNEL[0]:-}"

[ -z "$flutter_channel" ] && flutter_channel=stable
[ -z "$flutter_version" ] && flutter_version=any
[ -z "$ARCH" ] && ARCH=x64
[ -z "$flutter_cache_key" ] && flutter_cache_key="$RUNNER_TOOL_CACHE/flutter/:channel:-:version:-:arch:"
[ -z "$flutter_cache_key" ] && flutter_cache_key="flutter-:os:-:channel:-:version:-:arch:-:hash:"
[ -z "$flutter_pub_cache_key" ] && flutter_pub_cache_key="flutter-pub-:os:-:channel:-:version:-:arch:-:hash:"
[ -z "$flutter_pub_cache_key" ] && flutter_pub_cache_key="default"
[ -z "$flutter_git_url" ] && flutter_git_url="https://github.com/flutter/flutter.git"

# `PUB_CACHE` is what Dart and Flutter looks for in the environment, while
# `flutter_pub_cache_key` is passed in from the action.
#
# If `PUB_CACHE` is set already, then it should continue to be used. Otherwise, satisfy it
# if the action requests a custom path, or set to the Dart default values depending
# on the operating system.
if [ -z "${PUB_CACHE:-}" ]; then
	if [ "$flutter_pub_cache_key" != "default" ]; then
		PUB_CACHE="$flutter_pub_cache_key"
	elif [ "$OS_NAME" = "windows" ]; then
		PUB_CACHE="$LOCALAPPDATA\\Pub\\Cache"
	else
		PUB_CACHE="$HOME/.pub-cache"
	fi
fi

if [ "$TEST_MODE" = true ]; then
	RELEASE_MANIFEST=$(cat "$(dirname -- "${BASH_SOURCE[0]}")/test/$MANIFEST_JSON_PATH")
else
	RELEASE_MANIFEST=$(curl --silent --connect-timeout 15 --retry 5 "$MANIFEST_URL")
fi

if [ "$flutter_channel" = "master" ] || [ "$flutter_channel" = "main" ]; then
	VERSION_MANIFEST="{\"channel\":\"$flutter_channel\",\"version\":\"$flutter_version\",\"dart_sdk_arch\":\"$ARCH\",\"hash\":\"$flutter_channel\",\"sha256\":\"$flutter_channel\"}"
else
	VERSION_MANIFEST=$(echo "$RELEASE_MANIFEST" | filter_by_channel "$flutter_channel" | filter_by_arch "$ARCH" | filter_by_version "$flutter_version")
fi

case "$VERSION_MANIFEST" in
*null*)
	not_found_error "$flutter_channel" "$flutter_version" "$ARCH"
	exit 1
	;;
esac

expand_key() {
	version_channel=$(echo "$VERSION_MANIFEST" | jq -r '.channel')
	version_version=$(echo "$VERSION_MANIFEST" | jq -r '.version')
	version_arch=$(echo "$VERSION_MANIFEST" | jq -r '.dart_sdk_arch // "x64"')
	version_hash=$(echo "$VERSION_MANIFEST" | jq -r '.hash')
	version_sha_256=$(echo "$VERSION_MANIFEST" | jq -r '.sha256')

	expanded_key="${1/:channel:/$version_channel}"
	expanded_key="${expanded_key/:version:/$version_version}"
	expanded_key="${expanded_key/:arch:/$version_arch}"
	expanded_key="${expanded_key/:hash:/$version_hash}"
	expanded_key="${expanded_key/:sha256:/$version_sha_256}"
	expanded_key="${expanded_key/:os:/$OS_NAME}"

	echo "$expanded_key"
}

flutter_cache_key=$(expand_key "$flutter_cache_key")
flutter_pub_cache_key=$(expand_key "$flutter_pub_cache_key")
flutter_cache_key=$(expand_key "$(transform_path "$flutter_cache_key")")

if [ "$PRINT_ONLY" = true ]; then
	version_info=$(echo "$VERSION_MANIFEST" | jq -j '.channel,":",.version,":",.dart_sdk_arch // "x64"')

	info_channel=$(echo "$version_info" | awk -F ':' '{print $1}')
	info_version=$(echo "$version_info" | awk -F ':' '{print $2}')
	info_architecture=$(echo "$version_info" | awk -F ':' '{print $3}')

	if [ "$TEST_MODE" = true ]; then
		echo "flutter_channel=$info_channel"
		echo "flutter_version=$info_version"
		# flutter_version_file is not printed, because it is essentially same as flutter_version
		echo "ARCHITECTURE=$info_architecture"
		echo "flutter_cache_key=$flutter_cache_key"
		echo "flutter_cache_key=$flutter_cache_key"
		echo "flutter_pub_cache_key=$flutter_pub_cache_key"
		echo "flutter_pub_cache_key=$PUB_CACHE"
		exit 0
	fi

	{
		echo "flutter_channel=$info_channel"
		echo "flutter_version=$info_version"
		# flutter_version_file is not printed, because it is essentially same as flutter_version
		echo "ARCHITECTURE=$info_architecture"
		echo "flutter_cache_key=$flutter_cache_key"
		echo "flutter_cache_key=$flutter_cache_key"
		echo "flutter_pub_cache_key=$flutter_pub_cache_key"
		echo "flutter_pub_cache_key=$PUB_CACHE"
	} >>"${GITHUB_OUTPUT:-/dev/null}"

	exit 0
fi

if [ ! -x "$flutter_cache_key/bin/flutter" ]; then
	if [ "$flutter_channel" = "master" ] || [ "$flutter_channel" = "main" ]; then
		git clone -b "$flutter_channel" "$flutter_git_url" "$flutter_cache_key"
		if [ "$flutter_version" != "any" ]; then
			git config --global --add safe.directory "$flutter_cache_key"
			(cd "$flutter_cache_key" && git checkout "$flutter_version")
		fi
	else
		archive_url=$(echo "$VERSION_MANIFEST" | jq -r '.archive')
		download_archive "$archive_url" "$flutter_cache_key"
	fi
fi

{
	echo "FLUTTER_ROOT=$flutter_cache_key"
	echo "PUB_CACHE=$PUB_CACHE"
} >>"${GITHUB_ENV:-/dev/null}"

{
	echo "$flutter_cache_key/bin"
	echo "$flutter_cache_key/bin/cache/dart-sdk/bin"
	echo "$PUB_CACHE/bin"
} >>"${GITHUB_PATH:-/dev/null}"
