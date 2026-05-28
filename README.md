# Zero-Latency WebRTC Streaming Project

Dockerized streaming server: low-latency **SRT** ingest from OBS, automatic AAC→Opus transcoding, and a password-protected **WebRTC** multi-view grid in the browser.

## Architecture

- **Nginx** — HTTPS front-end, static UI, HTTP Basic Auth on `/live.html`
- **MediaMTX** — SRT ingest (`:8890`), WebRTC playback (`:8889`), Control API (`:9997`)
- **FFmpeg** — On-demand per-path transcode to `gameX-browser` streams for WebRTC

## Prerequisites

- Ubuntu server (or similar Linux host)
- **A domain name** pointed at the server (Let's Encrypt cannot issue certs for bare IPs). If using a raw IP, the script will automatically fallback to HTTP.
- Ports **80**, **443**, **8889**, **8890**, and **9997** reachable from clients

## Quick start

```bash
git clone [https://github.com/your-username/webrtc-project.git](https://github.com/your-username/webrtc-project.git)
cd webrtc-project
chmod +x deploy.sh
./deploy.sh
```

`deploy.sh` will:

1. Install Docker / Docker Compose if needed
2. Ask for your **domain** or **IP** (saved to `.env` as `DOMAIN=...`)
3. Generate `generated/default.conf` and `generated/mediamtx.yml` from templates
4. Obtain Let's Encrypt certificates via Certbot (standalone on port 80) or fallback to HTTP
5. Create `.htpasswd` for the VIP live room
6. Start containers with `docker-compose`

### Manual configuration

Copy `.env.example` to `.env` and set your domain before running deploy:

```bash
cp .env.example .env
# edit DOMAIN=your.domain.com
./deploy.sh
```

To change domains later, update `DOMAIN` in `.env` and run `./deploy.sh` again.

## Repository structure

```text
├── .env.example              # DOMAIN=your.domain.com
├── default.conf.template     # Nginx template (__DOMAIN__ placeholder)
├── mediamtx.yml              # MediaMTX config (__DOMAIN__ in cert paths)
├── deploy.sh                 # One-shot setup script
├── docker-compose.yml        # Mounts ./generated/*.yml configs
├── generated/                # Created by deploy (gitignored except .gitkeep)
└── web/
    ├── config.js             # Host-relative API/WebRTC/SRT URLs
    ├── index.html            # Public landing page
    ├── live.html             # Password-protected 4-up viewer
    ├── streamer-setup.html
    └── host-setup.html
```

## Stream paths

| Role | OBS server URL |
|------|----------------|
| Player 1–4 publish | `srt://YOUR_DOMAIN:8890?streamid=publish:game1` … `game4` |
| Host read (OBS) | `srt://YOUR_DOMAIN:8890?streamid=read:game1` … `game4` |
| Browser WebRTC | `https://YOUR_DOMAIN:8889/game1-browser/` … |

Guide pages under `web/` fill in `YOUR_DOMAIN` automatically from the hostname in the browser.

## Redeploy / restart

```bash
./deploy.sh          # full idempotent setup
# or, if .env and generated/ already exist:
docker-compose down && docker-compose up -d
```

## Author
* **[KingofTheBeez](https://gitlab.com/AlecBaldwin69):** Core development, UI layout, and infrastructure deployment

## Credits & Acknowledgments

* **[Carigs](https://gitlab.com/mcarigs):** Codebase portability optimization for public release, suggestions and ideas. The goat.
* **[MGSG Community](https://discord.gg/hhNAaSP8eN):** For testing and QA. This was built for them!

### Built With
This low latency streaming environment stands on the shoulders of giants. A massive thank you to the developers and maintainers of the incredibly powerful open-source tools and protocols that make this possible:

* **[Secure Reliable Transport (SRT)](https://www.srtalliance.org/):** Originally developed by Haivision. Used for the video ingestion.
* **[WebRTC](https://webrtc.org/):** Open-sourced by Google. Used for the peer-to-peer delivery.
* **[FFmpeg](https://ffmpeg.org/):** Created by Fabrice Bellard. Used for converting the audio from AAC to Opus.
* **[Nginx](https://nginx.org/):** Created by Igor Sysoev. Used for routing, reverse proxying, and clean URLs.
* **[Docker](https://www.docker.com/):** Created by Solomon Hykes. Used for containerizing the entire environment.
* **[Let's Encrypt & Certbot](https://letsencrypt.org/):** Provided by the ISRG and EFF. Used for automated SSL integration.