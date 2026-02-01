# Alexa Spotify Playlist Randomizer

A script to randomly select a song from a source playlist and add it to a destination playlist.

Built this because I had an Alexa routine that acted as an alarm and had asked Alexa to play a particular playlist through Spotify as one of the actions. The problem was that each time, the playlist played from the start. In Spotify's case, tracks are ordered by date added (earliest to latest), so the same song kept coming up every morning. I fixed it by giving Alexa a dedicated Spotify playlist and running this script on a schedule (e.g. via cron). The script picks a random song from a source playlist (from the most recently added tracks) and puts it into that dedicated playlist, so when the alarm runs, Alexa plays a different song each day.

## How to Setup

1. **Copy the example config:**

    ```bash
    cp .spotify-config.example .spotify-config
    ```

2. **Fill out your `.spotify-config`:**
   - Set `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET` (from [Spotify Developer Dashboard](https://developer.spotify.com/dashboard))
   - Get your `REFRESH_TOKEN` (see [server/README.md](server/README.md) for instructions using the helper server)
   - Add `SOURCE_PLAYLIST_ID` (the playlist you want to take songs from)
   - Add `DESTINATION_PLAYLIST_ID` (the playlist Alexa will play, e.g. "Alarm playlist")
   - You can optionally set `NUM_RECENT_TRACKS` (defaults to 50)

3. **Link your Spotify config to your home directory:**  

   The script uses the path specified by the `CONFIG_FILE` environment variable to find your config file. If `CONFIG_FILE` isn't set, it looks for the config at `$HOME/.spotify-config`.

   ```bash
   ln -s .spotify-config ~/.spotify-config
   ```

4. **Use the following command to run it automatically with cron:**
    ```bash
    crontab -e
    ```

    Add the following line to your crontab:
    ```bash
    # 12:00 AM IST
    30 18 * * * /path/to/alexa-spotify-playlist-randomizer/random.sh
    ```

    Replace `/path/to/alexa-spotify-playlist-randomizer` with the actual path to the script.

## How it works

The `random.sh` script automates picking a song for Alexa to play using the Spotify Web API:

1. Gets an access token using your refresh token.
2. Reads your **source** playlist and picks a random track from the last `NUM_RECENT_TRACKS` added.
3. Replaces the single track in your **destination** playlist with that track (the playlist you tell Alexa to play, e.g. "Alexa, play my Alarm playlist on Spotify").

Each run refreshes your Alexa playlist with one random recent song from your source playlist.

### Useful Documentation

- [Spotify Web API Documentation](https://developer.spotify.com/documentation/web-api)
- [Spotify Web API - Authorization](https://developer.spotify.com/documentation/web-api/concepts/authorization)
- [Spotify Web API - Access Token](https://developer.spotify.com/documentation/web-api/concepts/access-token)
- [Spotify Web API - Scopes](https://developer.spotify.com/documentation/web-api/concepts/scopes)
- [Spotify Web API - Authorization Code Flow](https://developer.spotify.com/documentation/web-api/tutorials/code-flow)

