/**
 * Resolves stream/API URLs from the page hostname so the UI works on any deployment.
 */
const StreamConfig = {
  get host() {
    return window.location.hostname;
  },

  apiUrl(path) {
    return `https://${this.host}:9997${path}`;
  },

  webrtcPlayerUrl(streamName) {
    return `https://${this.host}:8889/${streamName}/`;
  },

  srtUrl(game, mode) {
    return `srt://${this.host}:8890?streamid=${mode}:${game}`;
  },

  siteUrl() {
    return `${window.location.protocol}//${this.host}`;
  },
};

function applyHostTemplates() {
  document.querySelectorAll('[data-tmpl]').forEach((el) => {
    el.textContent = el.dataset.tmpl.replace(/\{\{HOST\}\}/g, StreamConfig.host);
  });
}

document.addEventListener('DOMContentLoaded', applyHostTemplates);