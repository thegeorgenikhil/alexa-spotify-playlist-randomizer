# Spotify OAuth helper server

This server is a **one-time helper** to obtain the initial **refresh token** that `random.sh` needs. The playlist randomizer script uses the refresh token (from your `.spotify-config`) to get short-lived access tokens without you logging in each time. Spotify only issues a refresh token when a user completes the Authorization Code flow in a browser, so this small server runs that flow for you.

Refere to [Spotify Web API - Authorization Code Flow](https://developer.spotify.com/documentation/web-api/tutorials/code-flow) for more information.

## How to run

1. Copy `.env.example` to `.env` and set `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET` (from your [Spotify app](https://developer.spotify.com/dashboard)).
2. In the Spotify app settings, add `http://127.0.0.1:8888/callback` to **Redirect URIs**.
3. Install and start:

   ```bash
   pnpm install
   pnpm start
   ```

   Server runs at **http://127.0.0.1:8888**.

## What to do in the browser

1. Open **http://127.0.0.1:8888/login** in your browser.
2. You are redirected to Spotify to log in and approve access (playlist-modify scopes).
3. After you approve, Spotify sends you back to `/callback`. The server exchanges the authorization code for tokens and responds with JSON containing `access_token`, `refresh_token`, `expires_in`, etc.
4. Copy the **`refresh_token`** value from that JSON and put it in your `.spotify-config` as `REFRESH_TOKEN`. You only need to do this once; `random.sh` will use it to get new access tokens every time it runs.
