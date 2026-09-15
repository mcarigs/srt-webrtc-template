/**
 * Resolves stream/API URLs from the page hostname so the UI works on any deployment.
 */
const StreamConfig = {
  get host() {
    return window.location.hostname;
  },

  get origin() {
    return window.location.origin;
  },

  apiUrl(path) {
    return `${this.origin}/api${path}`;
  },

  webrtcPlayerUrl(streamName) {
    return `${this.origin}/webrtc/${streamName}/`;
  },

  srtUrl(game, mode) {
    const portal = window.PortalConfig || {};

    if (mode === 'publish') {
      return (
        `srt://${this.host}:8890` +
        `?streamid=publish:${game}:${portal.publishUser}:${portal.publishKey}` +
        `&pkt_size=1316`
      );
    }

    if (mode === 'read') {
      return (
        `srt://${this.host}:8890` +
        `?streamid=read:${game}:${portal.hostUser}:${portal.hostKey}` +
        `&pkt_size=1316`
      );
    }

    throw new Error(`Unsupported SRT mode: ${mode}`);
  },

  siteUrl() {
    return this.origin;
  },
};

function applyHostTemplates() {
  const portal = window.PortalConfig || {};

  document.querySelectorAll('[data-tmpl]').forEach((el) => {
    el.textContent = el.dataset.tmpl
      .replace(/\{\{HOST\}\}/g, StreamConfig.host)
      .replace(/\{\{ORIGIN\}\}/g, StreamConfig.origin)
      .replace(/\{\{PUBLISH_USER\}\}/g, portal.publishUser || '')
      .replace(/\{\{PUBLISH_KEY\}\}/g, portal.publishKey || '')
      .replace(/\{\{HOST_USER\}\}/g, portal.hostUser || '')
      .replace(/\{\{HOST_KEY\}\}/g, portal.hostKey || '');
  });
}

document.addEventListener('DOMContentLoaded', applyHostTemplates);