# NomadAI 🏕️

AI-powered campsite discovery. Find BLM, National Forest, Recreation.gov and more — all in one place.

## Setup

1. Deploy to Vercel
2. Add environment variables:
   - `ANTHROPIC_KEY` — your Anthropic API key
   - `GOOGLE_PLACES_KEY` — your Google Places API key

## Structure

- `index.html` — landing page
- `app.html` — main app
- `spot.html` — shared campsite page
- `api/claude.js` — Claude API proxy
- `api/places.js` — Google Places proxy
- `vercel.json` — routing config

## Live

https://nomadai.us
