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
MAX_RESULTS=50

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
  echo "<link rel="stylesheet" href="tuiles.css">" >> "$HTML_RESULT_FILE"
  echo "<body><h1>$DOCUMENT_TITLE</h1>" >> "$HTML_RESULT_FILE"
  echo "<div class=\"course-tile-container\">" >> "$HTML_RESULT_FILE"
  cp ./css/tuiles.css $RESULT_FOLDER
  
  NEXT_PAGE_TOKEN=""
  VIDEO_NUM=0 # While counter. Easier to find in code than plain old "i". Yeah, bash is great, but not that great. Well, it's pretty old...
  while true; do
    QUERY="${YOUTUBE_API_BASE_URL}/playlistItems?playlistId=${PLAYLIST_ID}&pageToken=${NEXT_PAGE_TOKEN}&key=${API_KEY}&maxResults=${MAX_RESULTS}&${EXTRA_QUERY_PARAMS}"
    echo -e "\nQuerying API on"
    echo -e "$QUERY"
    RESPONSE=$(curl -s "$QUERY")
    
    echo -e "CACHE_FOLDER : $CACHE_FOLDER"
    if [ ! -z "$CACHE_FOLDER" ]; then
      CACHE_FILE="$CACHE_FOLDER/cache-$(date +'%Y%m%d-%H%M%S').json"
      echo -e "CACHE_FILE : $CACHE_FILE"
      echo "$RESPONSE" | jq '.' > "$CACHE_FILE"
    fi
    
    # Tentative de lecture de la réponse avec "while read -r item"
    # echo "$RESPONSE" | jq -c '.items[] | {title: .snippet.title, description: .snippet.description, videoId: .snippet.resourceId.videoId, thumbnail: .snippet.thumbnails.default}' | while read -r item; do
    #
    # Explication du problème :
    # VIDEO_NUM est défini à l'extérieur de la boucle interne while read -r item.
    # En Bash, chaque while read ou for qui lit son entrée à partir d'une commande crée un sous-shell distinct.
    # Les variables modifiées dans ce sous-shell (comme VIDEO_NUM) ne persistent pas dans le shell parent.
    
    # Tentative d'itération sur les items avec un "for" normal
    # for item in $items; do
    #
    # Explication du problème :
    # Le problème provient probablement de la manière dont jq formate la sortie des items
    # et comment ils sont lus par for item in $items. jq génère les éléments sous forme de chaîne JSON, mais le for en Bash divise les entrées par défaut en utilisant l'espace comme séparateur, ce qui entraîne des erreurs de parsing

    items=$(echo "$RESPONSE" | jq -c '.items[] | {title: .snippet.title, description: .snippet.description, videoId: .snippet.resourceId.videoId, thumbnail: .snippet.thumbnails.default}')

    IFS=$'\n' read -rd '' -a item_array <<< "$items"
    # IFS=$'\n' permet de définir le séparateur comme le caractère de nouvelle ligne.
    # read -rd '' -a item_array permet de lire les éléments de manière sûre et correcte dans un tableau.

    for item in "${item_array[@]}"; do
      # Extract video infos
      VIDEO_TITLE=$(echo "$item" | jq -r '.title')
      VIDEO_ID=$(echo "$item" | jq -r '.videoId')
      VIDEO_LINK="https://www.youtube.com/watch?v=${VIDEO_ID}"
      VIDEO_THUMBNAIL=$(echo "$item" | jq -r '.thumbnail.url')
      VIDEO_DESCRIPTION=$(echo "$item" | jq -r '.description')
      
      # Extract custom urls from description
      PLAN_DES_COURS=$(echo "$VIDEO_DESCRIPTION" | grep "^Plan des cours" | sed -n 's/.*\(https.*\)/\1/p') # Not used
      VOCABULAIRE=$(echo "$VIDEO_DESCRIPTION" | grep "^Fiche de vocabulaire" | sed -n 's/.*\(https.*\)/\1/p')
      EXERCICES=$(echo "$VIDEO_DESCRIPTION" | grep "^Exercices de japonais" | sed -n 's/.*\(https.*\)/\1/p')
      CORRECTION_EXERCICES=$(echo "$VIDEO_DESCRIPTION" | grep "^Correction des exercices" | sed -n 's/.*\(https.*\)/\1/p')
      TABLEAU=$(echo "$VIDEO_DESCRIPTION" | grep "^Imprimer le tableau" | sed -n 's/.*\(https.*\)/\1/p')
      SOLUTION_TABLEAU=$(echo "$VIDEO_DESCRIPTION" | grep "^Solution du tableau" | sed -n 's/.*\(https.*\)/\1/p')
      TRACE_HIRAGANA=$(echo "$VIDEO_DESCRIPTION" | grep "^Tracé des hiragana" | sed -n 's/.*\(https.*\)/\1/p')
      TRACE_KATAKANA=$(echo "$VIDEO_DESCRIPTION" | grep "^Tracé des katakana" | sed -n 's/.*\(https.*\)/\1/p')
      TABLEAU_HIRAGANA=$(echo "$VIDEO_DESCRIPTION" | grep "^Tableau des hiragana" | sed -n 's/.*\(https.*\)/\1/p')
      TABLEAU_KATAKANA=$(echo "$VIDEO_DESCRIPTION" | grep "^Tableau des katakana" | sed -n 's/.*\(https.*\)/\1/p')
      
      # Print info to console and HTML file (video title, clickable thumbnail and exercises urls)
      echo -e "\n$VIDEO_TITLE"
      # echo "<h2>${VIDEO_NUM}. $VIDEO_TITLE</h2>" >> "$HTML_RESULT_FILE"
      # echo "<a href = \"$VIDEO_LINK\" title=\"$VIDEO_DESCRIPTION\">" >> "$HTML_RESULT_FILE"
      # echo "  <img src = \"$VIDEO_THUMBNAIL\" />" >> "$HTML_RESULT_FILE"
      # echo "</a>" >> "$HTML_RESULT_FILE"
      
      echo "    <div class=\"course-tile\">" >> "$HTML_RESULT_FILE"
      echo "        <a href = \"$VIDEO_LINK\" title=\"$VIDEO_DESCRIPTION\">" >> "$HTML_RESULT_FILE"
      echo "          <img src=\"$VIDEO_THUMBNAIL\" alt=\"$VIDEO_DESCRIPTION\" class=\"course-thumbnail\" />" >> "$HTML_RESULT_FILE"
      echo "        </a>" >> "$HTML_RESULT_FILE"
      echo "        <div class=\"course-details\">" >> "$HTML_RESULT_FILE"
      echo "            <h2>${VIDEO_NUM}. $VIDEO_TITLE</h3>" >> "$HTML_RESULT_FILE"
      echo "            <div class=\"course-links\">" >> "$HTML_RESULT_FILE"
      # echo "" >> "$HTML_RESULT_FILE"

      # Add vocabulaire link
      if [[ ! -z "$VOCABULAIRE" ]]; then
        echo -e "Vocabulaire : $VOCABULAIRE"      
        echo "  <a href=\"$VOCABULAIRE\" title=\"Vocabulaire\">Vocabulaire</a>" >> "$HTML_RESULT_FILE"
      fi
      
      # Add tableau link
      if [[ ! -z "$TABLEAU" ]]; then
        echo -e "Tableau : $TABLEAU"
        echo "  <a href=\"$TABLEAU\" title=\"Tableau\">Tableau</a>" >> "$HTML_RESULT_FILE"
      fi
      
      # Add tableau_solution link
      if [[ ! -z "$SOLUTION_TABLEAU" ]]; then
        echo -e "Solution du tableau : $SOLUTION_TABLEAU"
        echo "  <a href=\"$SOLUTION_TABLEAU\" title=\"Solution du tableau\">Solution du tableau</a>" >> "$HTML_RESULT_FILE"
      fi
      
      # Add trace_hiragana link
      if [[ ! -z "$TRACE_HIRAGANA" ]]; then
        echo -e "Tracé des Hiragana : $TRACE_HIRAGANA"
        echo "  <a href=\"$TRACE_HIRAGANA\" title=\"Tracé des Hiragana\">Tracé des Hiragana</a>" >> "$HTML_RESULT_FILE"
      fi

      # Add trace_katakana link
      if [[ ! -z "$TRACE_KATAKANA" ]]; then
        echo -e "Tracé des Katakana : $TRACE_KATAKANA"
        echo "  <a href=\"$TRACE_KATAKANA\" title=\"Tracé des Katakana\">Tracé des Katakana</a>" >> "$HTML_RESULT_FILE"
      fi
      
      # Add tableau_hiragana link
      if [[ ! -z "$TABLEAU_HIRAGANA" ]]; then
        echo -e "Tableau des Hiragana : $TABLEAU_HIRAGANA"
        echo "  <a href=\"$TABLEAU_HIRAGANA\" title=\"Tableau des Hiragana\">Tableau des Hiragana</a>" >> "$HTML_RESULT_FILE"
      fi

      # Add tableau_katakana link
      if [[ ! -z "$TABLEAU_KATAKANA" ]]; then
        echo -e "Tableau des Katakana : $TABLEAU_KATAKANA"
        echo "  <a href=\"$TABLEAU_KATAKANA\" title=\"Tableau des Katakana\">Tableau des Katakana</a>" >> "$HTML_RESULT_FILE"
      fi

      
      # Add exercises link, and correction if available
      if [[ ! -z "$EXERCICES" ]]; then
        echo -e "Exercices : $EXERCICES"      
        echo "  <a href=\"$EXERCICES\" title=\"Exercices\">Exercices</a>" >> "$HTML_RESULT_FILE"

        if [[ ! -z "$CORRECTION_EXERCICES" ]]; then
          echo -e "Correction exercices : $EXERCICES"
          echo "  <a href=\"$CORRECTION_EXERCICES\" title=\"Correction des exercices\">Correction des exercices</a>" >> "$HTML_RESULT_FILE"
        fi
      fi
      echo "            </div>" >> "$HTML_RESULT_FILE"
      echo "        </div>" >> "$HTML_RESULT_FILE"
      echo "    </div>" >> "$HTML_RESULT_FILE"
      
      VIDEO_NUM=$((VIDEO_NUM+1))
      
      # Garde-fou
      # if [ "$VIDEO_NUM" -gt 3 ]; then
      #   break
      # fi
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
  echo "</div>" >> "$HTML_RESULT_FILE"
  echo "</body></html>" >> "$HTML_RESULT_FILE"
}

## Main program

# Create result folder where generated HTML files will be located
mkdir -p "$RESULT_FOLDER"
if [ ! -z "$CACHE_FOLDER" ]; then
  mkdir -p "$CACHE_FOLDER"
fi

fetch_playlist_descriptions

echo "Completed fetching descriptions."
