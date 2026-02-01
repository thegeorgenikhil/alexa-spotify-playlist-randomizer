import express from 'express';
import querystring from 'querystring';
import dotenv from 'dotenv';
dotenv.config();

var client_id = process.env.SPOTIFY_CLIENT_ID;
var client_secret = process.env.SPOTIFY_CLIENT_SECRET;
var redirect_uri = 'http://127.0.0.1:8888/callback';

var app = express();

function generateRandomString(length: number) {
  return Math.random().toString(36).substring(2, 2 + length);
}

app.get('/login', function (req, res) {

  var state = generateRandomString(16);
  var scope = 'playlist-modify-private playlist-modify-public';

  res.redirect('https://accounts.spotify.com/authorize?' +
    querystring.stringify({
      response_type: 'code',
      client_id: client_id,
      scope: scope,
      redirect_uri: redirect_uri,
      state: state
    }));
});

app.get('/callback', async function(req, res) {
  var code = req.query.code || null;
  var state = req.query.state || null;

  if (state === null) {
    res.redirect('/#' +
      querystring.stringify({
        error: 'state_mismatch'
      }));
  } else {
    const response = await fetch('https://accounts.spotify.com/api/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': 'Basic ' + Buffer.from(client_id + ':' + client_secret).toString('base64')
      },
      body: new URLSearchParams({
        code: code as string,
        redirect_uri: redirect_uri,
        grant_type: 'authorization_code'
      }).toString()
    });

    if (response.ok) {
      const data = await response.json();
      return res.json(data);
    } else {
      res.redirect('/#' +
        querystring.stringify({
          error: 'invalid_token'
        }));
    }
  }
});

app.listen(8888, () => {
  console.log('Server running on http://127.0.0.1:8888');
});