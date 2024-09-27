# youtube-extract-desc

## Overview
This script extracts the descriptions of videos from a specified YouTube playlist using the YouTube Data API.

## Setup
1. Copy `secret-example.json` and rename it to `secret.json`.
2. Fill `secret.json` with your API credentials.

## API Documentation
- Sample API Requests: [YouTube Data API v3](https://developers.google.com/youtube/v3/sample_requests)
- Google API Dashboard: [API Dashboard](https://console.cloud.google.com/apis/dashboard)
- Google API Keys: [API Credentials](https://console.cloud.google.com/apis/credentials)

## Configuration
- `conf/endpoints.json`: Currently not utilized, but designed to formally define some API endpoints.

## Usage
Run the script in your terminal. Ensure that you have the required permissions for the YouTube API.
`./youtube-extract-desc.sh PLAYLIST_ID`

## TODO
- Implement the usage of `conf/endpoints.json`.
- Add error handling for API requests.
