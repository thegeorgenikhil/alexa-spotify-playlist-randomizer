#!/bin/bash

error() {
  RED='\033[0;31m'
  NC='\033[0m'
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}Error:${NC} $1"
}

CONFIG_PATH="${CONFIG_FILE:-$HOME/.spotify-config}"
if [ ! -f "$CONFIG_PATH" ]; then
  error "Spotify config file not found at $CONFIG_PATH"
  exit 1
fi

source "$CONFIG_PATH"


if [ -z "$REFRESH_TOKEN" ]; then
  error "REFRESH_TOKEN is not set in the script"
  exit 1
fi

if [[ -z "$SPOTIFY_CLIENT_ID" || -z "$SPOTIFY_CLIENT_SECRET" ]]; then
  error "SPOTIFY_CLIENT_ID or SPOTIFY_CLIENT_SECRET is not set in the script"
  exit 1
fi

if [ -z "$SOURCE_PLAYLIST_ID" ]; then
  error "SOURCE_PLAYLIST_ID is not set in the script"
  exit 1
fi

if [ -z "$DESTINATION_PLAYLIST_ID" ]; then
  error "DESTINATION_PLAYLIST_ID is not set in the script"
  exit 1
fi

if [ "$SOURCE_PLAYLIST_ID" = "$DESTINATION_PLAYLIST_ID" ]; then
  error "SOURCE_PLAYLIST_ID and DESTINATION_PLAYLIST_ID are the same"
  exit 1
fi

auth_header="Basic $(echo -n "${SPOTIFY_CLIENT_ID}:${SPOTIFY_CLIENT_SECRET}" | base64 | tr -d '\n')"

# https://developer.spotify.com/documentation/web-api/tutorials/refreshing-tokens
response=$(curl -s -X POST "https://accounts.spotify.com/api/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Authorization: $auth_header" \
  -d "grant_type=refresh_token" \
  -d "refresh_token=${REFRESH_TOKEN}")

access_token=$(echo "$response" | jq -r '.access_token // empty')

if [ -z "$access_token" ]; then
  error "Access token not found in the response"
  exit 1
fi

# https://developer.spotify.com/documentation/web-api/reference/get-playlist
response=$(curl -s --request GET \
  "https://api.spotify.com/v1/playlists/${SOURCE_PLAYLIST_ID}?fields=tracks.total" \
  --header "Authorization: Bearer ${access_token}")

total_tracks=$(echo "$response" | jq -r '.tracks.total')

if [ -z "$total_tracks" ] || [ "$total_tracks" = "null" ]; then
  error "Failed to fetch the total number of songs from the playlist"
  exit 1
fi

if [ "$total_tracks" -lt "$NUM_RECENT_TRACKS" ]; then
  error "The playlist contains less than $NUM_RECENT_TRACKS tracks"
  exit 1
fi

lower_bound=$((total_tracks-NUM_RECENT_TRACKS))
upper_bound=$total_tracks

response=$(curl -s --request GET \
  "https://api.spotify.com/v1/playlists/${DESTINATION_PLAYLIST_ID}?fields=tracks.total" \
  --header "Authorization: Bearer ${access_token}")

dest_total_tracks=$(echo "$response" | jq -r '.tracks.total')

if [ -z "$dest_total_tracks" ] || [ "$dest_total_tracks" = "null" ]; then
  error "Failed to fetch the total number of songs from the destination playlist"
  exit 1
fi

# FAILSAFE: Ensure the destination playlist only has 1 song in total,
# so that even if the source and destination playlist IDs are accidentally swapped or mismatched,
# we don't risk deleting songs from the wrong playlist.
if [ $dest_total_tracks -gt 1 ]; then
  error "Destination playlist contains more than 1 track. Verify that you've selected the correct playlist and that it is empty or has only 1 track, as tracks will be removed before adding the new track."
  exit 1
fi

dest_track_uri=""
if [ $dest_total_tracks -gt 0 ]; then
  # https://developer.spotify.com/documentation/web-api/reference/get-playlists-tracks
  resp=$(curl -s --request GET \
    "https://api.spotify.com/v1/playlists/${DESTINATION_PLAYLIST_ID}/tracks?fields=items(track(uri))&limit=1&offset=0" \
    --header "Authorization: Bearer ${access_token}")

  dest_track_uri=$(echo "$resp" | jq -r '.items[0].track.uri')
fi

# Attempt to select a random track (up to 10 tries) that satisfies:
#   - "IN"(India) is included within the track's available_markets, AND
#   - is_local is false(ie. Track is not a local file).
#   - the random track is not the same as the currently present track in the destination playlist
# Tracks that don't meet these requirements cannot be added to the destination playlist(ie. Song is not playable through Alexa).
MAX_PICK_ATTEMPTS=10
attempt=0
track_uri=""

while [ $attempt -lt $MAX_PICK_ATTEMPTS ]; do
  attempt=$((attempt + 1))

  if command -v shuf >/dev/null 2>&1; then
    selected_track_index=$(shuf -i "$((lower_bound + 1))"-"$upper_bound" -n 1)
  else
    selected_track_index=$(( $(od -An -N2 -tu2 < /dev/urandom | tr -d ' ') % (upper_bound - lower_bound) + lower_bound + 1 ))
  fi
  offset=$((selected_track_index - 1))

  if [ $attempt -gt 1 ]; then
    echo "Attempt $attempt/$MAX_PICK_ATTEMPTS: Total tracks: $total_tracks, Selected index: $selected_track_index, Offset: $offset"
  fi

  # https://developer.spotify.com/documentation/web-api/reference/get-playlists-tracks
  response=$(curl -s --request GET \
    "https://api.spotify.com/v1/playlists/${SOURCE_PLAYLIST_ID}/tracks?fields=items(track(available_markets,is_local,uri))&limit=1&offset=${offset}" \
    --header "Authorization: Bearer ${access_token}")

  has_in_market=$(echo "$response" | jq -r '((.items[0].track.available_markets // []) | index("IN")) != null')
  is_local=$(echo "$response" | jq -r 'if .items[0].track.is_local == null then true else .items[0].track.is_local end')

  candidate_track_uri=$(echo "$response" | jq -r '.items[0].track.uri')

  if [ "$has_in_market" = "true" ] && [ "$is_local" = "false" ] && [ -n "$candidate_track_uri" ] && [ "$candidate_track_uri" != "null" ]; then
    if [ -z "$dest_track_uri" ] || [ "$candidate_track_uri" != "$dest_track_uri" ]; then
      track_uri="$candidate_track_uri"
      break
    fi
  fi
done

if [ -z "$track_uri" ] || [ "$track_uri" = "null" ]; then
  error "Could not find a valid (and different) track (IN in available_markets, is_local=false, and != current dest track) after $MAX_PICK_ATTEMPTS attempts"
  exit 1
fi

if [ -n "$dest_track_uri" ] && [ "$dest_track_uri" != "null" ]; then
  # https://developer.spotify.com/documentation/web-api/reference/remove-tracks-playlist
  delete_payload="{\"tracks\": [{\"uri\": \"${dest_track_uri}\"}]}"
  delete_response=$(curl -s -w "\n%{http_code}" --request DELETE \
    --url "https://api.spotify.com/v1/playlists/${DESTINATION_PLAYLIST_ID}/tracks" \
    --header "Authorization: Bearer ${access_token}" \
    --header "Content-Type: application/json" \
    --data "$delete_payload")

  delete_http_code=$(echo "$delete_response" | tail -n1)
  if [ "$delete_http_code" != "200" ]; then
    error "Failed to delete existing track from destination playlist (HTTP $delete_http_code)"
    exit 1
  fi
fi

# https://developer.spotify.com/documentation/web-api/reference/add-tracks-to-playlist
add_payload="{\"uris\": [\"${track_uri}\"]}"
add_response=$(curl -s -w "\n%{http_code}" --request POST \
  --url "https://api.spotify.com/v1/playlists/${DESTINATION_PLAYLIST_ID}/tracks" \
  --header "Authorization: Bearer ${access_token}" \
  --header "Content-Type: application/json" \
  --data "$add_payload")

http_code=$(echo "$add_response" | tail -n1)
if [ "$http_code" != "201" ]; then
  error "Failed to add track to destination playlist (HTTP $http_code)"
  exit 1
fi