# Zero-Latency SRT / WebRTC Streaming Project

Dockerized restreaming server: low-latency **SRT** ingest from OBS, automatic AAC→Opus transcoding, direct SRT playback for hosts, and a password-protected **WebRTC** multi-view grid in the browser.

Designed to be portable for races, tournaments, events, commentary, remote production, or any other situation where multiple incoming streams need to be monitored or restreamed.

## Architecture

- **Nginx** — HTTPS front-end, static UI, HTTP Basic Auth for the private portal, and reverse proxying for WebRTC and the MediaMTX API
- **MediaMTX** — SRT ingest/playback (`UDP :8890`), WebRTC media (`UDP :8189`), internal WebRTC HTTP service (`127.0.0.1:8889`), and internal Control API (`127.0.0.1:9997`)
- **FFmpeg** — On-demand per-path transcode to `gameX-browser`, copying the original H.264 video while converting AAC audio to Opus for WebRTC

### Stream flow

```text
OBS / SRT Source
      │
      ▼
   MediaMTX
      │
      ├──────────────► Host / Restream OBS
      │                  Original SRT feed
      │
      ▼
    FFmpeg
 H.264 copy
 AAC → Opus
      │
      ▼
   MediaMTX
      │
      ▼
 WebRTC Browser Viewer
```

## Prerequisites

- Ubuntu server or similar Linux host
- Root access or an account with `sudo`
- **A domain name** pointed at the server is recommended for HTTPS
  - If a raw IP address is used, the deployment script automatically falls back to HTTP-only mode
- Required public ports:
  - **TCP 80** — HTTP / Let's Encrypt validation
  - **TCP 443** — HTTPS website and proxied WebRTC/API traffic
  - **UDP 8890** — SRT ingest/playback
  - **UDP 8189** — WebRTC media transport

Ports `8889` and `9997` are bound to localhost and should not be exposed publicly.

## Quick start

```bash
git clone https://gitlab.com/AlecBaldwin69/srt-webrtc-template.git
cd srt-webrtc-template
chmod +x deploy.sh
./deploy.sh
```

`deploy.sh` will:

1. Install Docker / Docker Compose if needed
2. Ask for your **domain** or **IP**
3. Generate persistent SRT publish/read credentials
4. Generate the Nginx and MediaMTX configuration files
5. Obtain Let's Encrypt certificates when using a domain
6. Configure automatic certificate renewal
7. Create `.htpasswd` for the private portal
8. Start the Docker containers

The generated domain and SRT credentials are stored in `.env` and reused during normal restarts and redeployments.

## Stream paths

The protected setup pages automatically generate the correct URLs for the current server.

| Role | URL |
|------|-----|
| Stream publish | `srt://YOUR_DOMAIN:8890?streamid=publish:game1:publisher:PUBLISH_KEY&pkt_size=1316` |
| Host / restream read | `srt://YOUR_DOMAIN:8890?streamid=read:game1:host:HOST_KEY&pkt_size=1316` |
| Browser WebRTC | `https://YOUR_DOMAIN/webrtc/game1-browser/` |

The same format is used for:

```text
game1
game2
game3
game4
```

When using a raw IP deployment, browser URLs use `http://` instead of `https://`.

The SRT publish and read keys are generated automatically during the first deployment and remain persistent until manually rotated.

## Rotate SRT keys

If an SRT URL or credential is ever leaked, both access keys can be rotated with a single command:

```bash
bash rotate-keys.sh
```

This will:

- Generate a new publisher key
- Generate a new host/read key
- Update `.env`
- Regenerate the MediaMTX and portal configuration
- Restart **only MediaMTX**

Nginx and the website remain online during the rotation.

All previous SRT publish/read URLs immediately become invalid and users must retrieve the new URLs from the protected setup pages.

## Restart / redeploy

Restart the running containers:

```bash
docker-compose restart
```

Perform a full redeploy:

```bash
./deploy.sh
```

A normal redeploy keeps the existing domain, SRT keys, portal password, and certificates.

## Repository structure

```text
├── .env.example
├── default.conf.template
├── mediamtx.yml
├── deploy.sh
├── rotate-keys.sh
├── docker-compose.yml
├── certbot/
│   └── renewal-hooks/
├── generated/
└── web/
    ├── config.js
    ├── index.html
    ├── live.html
    ├── streamer-setup.html
    └── host-setup.html
```

- `deploy.sh` — Initial setup and full redeployment
- `rotate-keys.sh` — Emergency SRT credential rotation
- `default.conf.template` — Nginx HTTPS configuration template
- `mediamtx.yml` — MediaMTX configuration template
- `generated/` — Deployment-specific generated configuration
- `web/` — Public site, private viewer, and setup guides

## Author

* **[KingofTheBeez](https://gitlab.com/AlecBaldwin69):** Core development, UI layout, and infrastructure deployment

## Credits & Acknowledgments

* **[Carigs](https://gitlab.com/mcarigs):** Codebase portability optimization for public release, suggestions and ideas. The goat.
* **[MGSG Community](https://discord.gg/hhNAaSP8eN):** For testing and QA. This was built for them!

### Built With

This low latency streaming environment stands on the shoulders of giants. A massive thank you to the developers and maintainers of the incredibly powerful open-source tools and protocols that make this possible:

* **[Secure Reliable Transport (SRT)](https://www.srtalliance.org/):** Originally developed by Haivision. Used for low-latency video ingest and playback.
* **[WebRTC](https://webrtc.org/):** Used for low-latency browser playback.
* **[FFmpeg](https://ffmpeg.org/):** Created by Fabrice Bellard. Used for converting audio from AAC to Opus while preserving the original H.264 video.
* **[Nginx](https://nginx.org/):** Created by Igor Sysoev. Used for the web front-end, authentication, reverse proxying, and HTTPS.
* **[Docker](https://www.docker.com/):** Created by Solomon Hykes. Used for containerizing the streaming environment.
* **[Let's Encrypt & Certbot](https://letsencrypt.org/):** Used for automated HTTPS certificate issuance and renewal.