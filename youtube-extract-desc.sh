#!/usr/bin/bash

# RESULT_=`curl --location --request GET "$API_ENDPOINT" --header "$HEADER" --form "$DEST_GIF_FORM" | jq -r '.data.id'`
# # YouTube API Key and Playlist ID (you still need to set these manually or read them from another config)
# API_KEY="YOUR_YOUTUBE_API_KEY"  # Replace with your YouTube API key if not in your config file
# # The base URL for the YouTube Data API
# YOUTUBE_API_BASE_URL="https://www.googleapis.com/youtube/v3"


# youtube-extract-desc extracts the "Description" field of all videos in a YouTube playlist.
# It requires a Google API key and access to the YouTube Data API v3.
# You will need to authorize this script to access your Google account.

RESULT_FOLDER="./results"
CACHE_FOLDER="./cache"
CACHE_FILE=$CACHE_FOLDER/cached-result.json

# Help
printHelp() {
  echo -e "Usage : youtube-extract-desc.sh PLAYLIST_ID"
}

# Parameters
PLAYLIST_ID=${1:-"PLC8UWZPWDAiUFzH1jWz6zJpAiYxN1iJvP"}
if [ -z "$PLAYLIST_ID" ]; then
  echo "Error: Playlist ID is not set. Please set your PLAYLIST_ID in the script."
  printHelp
  exit 1
fi

# Extracting values from secret file
# like API key, required for further queries
SECRET_CONNFIG_FILE="./conf/secret.json"
if [ ! -f "$SECRET_CONNFIG_FILE" ]; then
  echo "Error: Some configuration files $SECRET_CONNFIG_FILE not found."
  exit 1
fi

API_KEY=$(jq -r '.api_key' "$SECRET_CONNFIG_FILE")
CLIENT_ID=$(jq -r '.oauth2.client_id' "$SECRET_CONNFIG_FILE")
CLIENT_SECRET=$(jq -r '.oauth2.client_secret' "$SECRET_CONNFIG_FILE")
REDIRECT_URI=$(jq -r '.oauth2.redirect_uris[0]' "$SECRET_CONNFIG_FILE")
TOKEN_URI=$(jq -r '.oauth2.token_uri' "$SECRET_CONNFIG_FILE")
if [[ -z "$API_KEY" ||  -z "$CLIENT_ID" || -z "$CLIENT_SECRET" || -z "$REDIRECT_URI" || -z "$TOKEN_URI" ]]; then
  echo -e "Error: One or more configuration values are missing in $SECRET_CONNFIG_FILE."
  echo -e "API_KEY : $API_KEY"
  echo -e "CLIENT_ID : $CLIENT_ID"
  echo -e "CLIENT_SECRET : please check the file"
  echo -e "REDIRECT_URI : $REDIRECT_URI"
  echo -e "TOKEN_URI : $TOKEN_URI"    
  exit 1
fi

# Extracting values from conf file
# used for queries (base url, endpoints, ...)
ENDPOINTS_CONFIG_FILE="./conf/endpoints.json"
YOUTUBE_API_BASE_URL=$(jq -r '.api_base_url' "$ENDPOINTS_CONFIG_FILE")
EXTRA_QUERY_PARAMS=$(jq -r '.extra_query_params' "$ENDPOINTS_CONFIG_FILE")
ENDPOINTS=$(jq -r '.endpoints' "$ENDPOINTS_CONFIG_FILE")
if [[ -z "$YOUTUBE_API_BASE_URL" ]]; then
  echo -e "Error: One or more configuration values are missing in $ENDPOINTS_CONFIG_FILE."
  exit 1
fi

# Helper function to get the access token
get_access_token() {
  echo "Visit the following URL to authorize this application:"
  echo "https://accounts.google.com/o/oauth2/auth?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=https://www.googleapis.com/auth/youtube.readonly&response_type=code"
  
  read -p "Enter the authorization code: " AUTH_CODE

  ACCESS_TOKEN=$(curl -s -X POST ${TOKEN_URI} \
    -d code=${AUTH_CODE} \
    -d client_id=${CLIENT_ID} \
    -d client_secret=${CLIENT_SECRET} \
    -d redirect_uri=${REDIRECT_URI} \
    -d grant_type=authorization_code | jq -r '.access_token')

  if [ "$ACCESS_TOKEN" == "null" ]; then
    echo "Failed to retrieve the access token"
    exit 1
  fi

  echo "Access token retrieved successfully."
}

# Function to fetch and display video descriptions from the playlist
fetch_playlist_descriptions() {
  echo "Fetching video descriptions from the playlist ID: $PLAYLIST_ID"
  
  # Create HTML result file and set HTML headers
  DOCUMENT_TITLE="Exercices de japonais par Julien Fontanier"
  HTML_RESULT_FILE=$RESULT_FOLDER"/liste-des-cours-fontanier.html"
  echo "<html>" > "$HTML_RESULT_FILE"
  echo "<head><meta charset=\"UTF-8\"><title>$DOCUMENT_TITLE</title></head>" >> "$HTML_RESULT_FILE"
  echo "<body><h1>$DOCUMENT_TITLE</h1>" >> "$HTML_RESULT_FILE"

  NEXT_PAGE_TOKEN=""
  VIDEO_NUM=0 # While counter. Easier to find in code than plain old "i". Yeah, bash is great, but not that great. Well, it's pretty old...
  while true; do
    echo -e "\nQuerying API on"
    echo -e "${YOUTUBE_API_BASE_URL}/playlistItems?playlistId=${PLAYLIST_ID}&pageToken=${NEXT_PAGE_TOKEN}&key=${API_KEY}&${EXTRA_QUERY_PARAMS}"
    RESPONSE=$(curl -s "${YOUTUBE_API_BASE_URL}/playlistItems?playlistId=${PLAYLIST_ID}&pageToken=${NEXT_PAGE_TOKEN}&key=${API_KEY}&${EXTRA_QUERY_PARAMS}")
    
    echo "$RESPONSE" | jq -c '.items[] | {title: .snippet.title, description: .snippet.description, videoId: .snippet.resourceId.videoId, thumbnail: .snippet.thumbnails.default}' | while read -r item; do
      VIDEO_TITLE=$(echo "$item" | jq -r '.title')
      VIDEO_DESCRIPTION=$(echo "$item" | jq -r '.description')
      VIDEO_ID=$(echo "$item" | jq -r '.videoId')
      VIDEO_LINK="https://www.youtube.com/watch?v=${VIDEO_ID}"
      VIDEO_THUMBNAIL=$(echo "$item" | jq -r '.thumbnail.url')
      PLAN_DES_COURS=$(echo "$VIDEO_DESCRIPTION" | grep "^Plan des cours" | sed -n 's/.*\(https.*\)/\1/p')
      EXERCICES=$(echo "$VIDEO_DESCRIPTION" | grep "^Exercices de japonais" | sed -n 's/.*\(https.*\)/\1/p')
      CORRECTION_EXERCICES=$(echo "$VIDEO_DESCRIPTION" | grep "^Correction des exercices" | sed -n 's/.*\(https.*\)/\1/p')
      
      echo -e "\n$VIDEO_TITLE"
      echo "<h2>${VIDEO_NUM}. $VIDEO_TITLE</h2>" >> "$HTML_RESULT_FILE"
      echo "<a href = \"$VIDEO_LINK\" title=\"$VIDEO_DESCRIPTION\">" >> "$HTML_RESULT_FILE"
      echo "  <img src = \"$VIDEO_THUMBNAIL\" />" >> "$HTML_RESULT_FILE"
      echo "</a>" >> "$HTML_RESULT_FILE"
      
      # if [[ ! -z "$PLAN_DES_COURS" ]]; then
      #   echo "[$VIDEO_NUM] $VIDEO_TITLE : $PLAN_DES_COURS"
      
      #   echo "<ul>" >> "$HTML_RESULT_FILE"
      #   echo "<li><a href=\"$PLAN_DES_COURS\" title=\"$VIDEO_DESCRIPTION\">Plan des cours</a></li>" >> "$HTML_RESULT_FILE"
      #   echo "</ul>" >> "$HTML_RESULT_FILE"
      # fi

      # Add exercice link, and correction if available
      if [[ ! -z "$EXERCICES" ]]; then
        echo -e "Exercices : $EXERCICES"      
        echo "<h3>Exercices</h3>" >> "$HTML_RESULT_FILE"
        echo "<ul>" >> "$HTML_RESULT_FILE"
        echo "  <li><a href=\"$EXERCICES\" title=\"Exercices\">Exercices</a></li>" >> "$HTML_RESULT_FILE"

        if [[ ! -z "$CORRECTION_EXERCICES" ]]; then
          echo -e "Correction exercices : $EXERCICES"
          echo "  <li><a href=\"$CORRECTION_EXERCICES\" title=\"Correction des exercices\">Correction des exercices</a></li>" >> "$HTML_RESULT_FILE"
        fi

        echo "</ul>" >> "$HTML_RESULT_FILE"
      fi
      
      VIDEO_NUM=$((VIDEO_NUM+1))
    done
    
    # Check if there is another page of results
    NEXT_PAGE_TOKEN=$(echo "$RESPONSE" | grep 'nextPageToken')
    if [ -z "$NEXT_PAGE_TOKEN"  ]; then
      echo -e "No more results"
      break
    fi

    # echo -e "\n-----------------\nNEXT_PAGE_TOKEN_TEST: $NEXT_PAGE_TOKEN_TEST"
    NEXT_PAGE_TOKEN=$(echo "$RESPONSE" | jq -r '.nextPageToken') # Fails if nextPageToken isn't set. How to avoid properly ?
    echo -e "\nNew page of results : $NEXT_PAGE_TOKEN"
  done
  
  # Generate HTML footers
  echo -e "HTML file generated: $HTML_RESULT_FILE"
  echo "</body></html>" >> "$HTML_RESULT_FILE"
}

## Main program

# Create result folder where generated HTML files will be located
mkdir -p "$RESULT_FOLDER"
mkdir -p "$CACHE_FOLDER"

fetch_playlist_descriptions

echo "Completed fetching descriptions."

# EXAMPLES de résultat
# Title: Le négatif des verbes japonais
# Description: Mon manuel de japonais (idéal pour accompagner les vidéos YouTube) ▶ https://www.fnac.com/a18086039/Julien-Fontanier-Cours-de-japonais-par-Julien-Fontanier
# Mes cartes pour apprendre hiragana et katakana ▶ https://www.fnac.com/a18777020/Julien-Fontanier-Cours-de-japonais-par-Julien-Fontanier-BOITE-KANA
# Plan des cours ▶ https://docs.google.com/document/d/1Cvcu0qEbA8Ae4i28gBdyf5Mx0M5xC9cc6ViRhqpZDxY/edit?pref=2&pli=1
# Exercices de japonais ▶ https://docs.google.com/document/d/1__0TlszCRQyeW7VwUHGGl-I__U2cP0ixSmxIsVyhax8/edit?usp=share_link
# Correction des exercices ▶ https://docs.google.com/document/d/1OC0Ywfst6ffD-zhptmUAJZwJ-G85RVeKnl3ZLLmanrI/edit?usp=share_link