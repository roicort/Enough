const MINIMUM_NATURAL_DIMENSION = 64;
const MINIMUM_RENDERED_DIMENSION = 160;
const blurredClass = "enough-ai-blurred";
const overlays = new Map();
const overlayHosts = new Map();
const extensionLocale = "en";
const localizedMessages = {
  en: {
    aiConfidence: "AI: $1",
    realConfidence: "Real: $1",
    real: "Real",
    uncertain: "Uncertain",
    ai: "AI",
    aiThreshold: "AI threshold: $1",
    c2paAIDeclared: "C2PA: AI declared",
    c2paDigitalCapture: "C2PA: digital capture",
    c2paUnknownType: "C2PA: source type not declared",
    c2paUnverified: "C2PA: absent or unverifiable",
    revealImage: "View",
    revealImageAccessibility: "Show image without blur",
    analyzingImage: "Analyzing image",
    analysisUnavailable: "Image analysis unavailable"
  },
  es: {
    aiConfidence: "IA: $1",
    realConfidence: "Real: $1",
    real: "Real",
    uncertain: "Incierto",
    ai: "IA",
    aiThreshold: "Umbral de IA: $1",
    c2paAIDeclared: "C2PA: IA declarada",
    c2paDigitalCapture: "C2PA: captura digital",
    c2paUnknownType: "C2PA: tipo no declarado",
    c2paUnverified: "C2PA: ausente o no verificable",
    revealImage: "Ver",
    revealImageAccessibility: "Mostrar imagen sin desenfoque",
    analyzingImage: "Analizando imagen",
    analysisUnavailable: "Análisis de imagen no disponible"
  }
};

const style = document.createElement("style");
style.textContent = `
  img.${blurredClass} {
    filter: blur(18px) !important;
    transition: filter 160ms ease;
  }

  .enough-image-overlay {
    position: absolute;
    pointer-events: none;
    z-index: 2;
  }

  .enough-image-info {
    left: 8px;
    max-width: min(calc(100% - 16px), calc(100vw - 16px));
    position: absolute;
    top: 8px;
  }

  .enough-image-score-trigger {
    align-items: center;
    -webkit-backdrop-filter: blur(14px) saturate(160%);
    backdrop-filter: blur(14px) saturate(160%);
    background: rgb(255 255 255 / 20%);
    border: 1px solid rgb(255 255 255 / 38%);
    border-radius: 999px;
    box-shadow: 0 2px 10px rgb(0 0 0 / 25%);
    color: white;
    cursor: help;
    display: inline-flex;
    font: 600 12px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    height: 30px;
    justify-content: center;
    padding: 0;
    pointer-events: auto;
    position: relative;
    width: 30px;
  }

  .enough-image-score-trigger--loading {
    cursor: progress;
  }

  .enough-image-score-spinner {
    animation: enough-image-score-spin 700ms linear infinite;
    border: 2px solid rgb(255 255 255 / 35%);
    border-radius: 50%;
    border-top-color: white;
    box-sizing: border-box;
    height: 14px;
    width: 14px;
  }

  .enough-image-warning-icon {
    color: #facc15;
    height: 15px;
    width: 15px;
  }

  @keyframes enough-image-score-spin {
    to {
      transform: rotate(360deg);
    }
  }

  .enough-image-score-tooltip {
    background: rgb(24 24 27 / 88%);
    border: 1px solid rgb(255 255 255 / 25%);
    border-radius: 10px;
    box-shadow: 0 2px 10px rgb(0 0 0 / 25%);
    display: none;
    left: 0;
    padding: 7px 9px;
    position: absolute;
    top: calc(100% + 6px);
    width: 180px;
    z-index: 1;
  }

  .enough-image-score-trigger:hover .enough-image-score-tooltip,
  .enough-image-score-trigger:focus .enough-image-score-tooltip,
  .enough-image-score-trigger--open .enough-image-score-tooltip {
    display: block;
  }

  .enough-image-score__bar {
    background: linear-gradient(90deg, #22c55e, #eab308, #f97316);
    border-radius: 999px;
    height: 8px;
    position: relative;
  }

  .enough-image-score__threshold,
  .enough-image-score__value {
    position: absolute;
    top: -2px;
  }

  .enough-image-score__threshold {
    border-left: 1px dashed rgb(24 24 27 / 85%);
    height: 12px;
    left: var(--threshold);
  }

  .enough-image-score__value {
    background: white;
    border-radius: 999px;
    box-shadow: 0 1px 3px rgb(0 0 0 / 55%);
    height: 12px;
    left: calc(var(--confidence) - 6px);
    width: 12px;
  }

  .enough-image-score__labels,
  .enough-image-score__threshold-label {
    display: flex;
    justify-content: space-between;
  }

  .enough-image-score__labels {
    font-size: 9px;
    margin-top: 4px;
  }

  .enough-image-score__threshold-label {
    color: rgb(255 255 255 / 75%);
    font-size: 9px;
    margin-top: 4px;
  }

  .enough-image-chip,
  .enough-image-reveal {
    backdrop-filter: blur(12px) saturate(140%);
    -webkit-backdrop-filter: blur(12px) saturate(140%);
    border: 1px solid rgb(255 255 255 / 25%);
    border-radius: 999px;
    box-shadow: 0 2px 10px rgb(0 0 0 / 25%);
    color: white;
    font: 600 12px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    line-height: 1;
    padding: 7px 9px;
  }

  .enough-image-chip {
    background: rgb(24 24 27 / 68%);
    display: inline-block;
    margin-left: 6px;
  }

  .enough-image-chip--real {
    background: rgb(24 24 27 / 17%);
  }

  .enough-image-reveal {
    align-items: center;
    background: rgb(255 255 255 / 20%);
    border-color: rgb(255 255 255 / 38%);
    cursor: pointer;
    display: inline-flex;
    gap: 5px;
    left: 50%;
    pointer-events: auto;
    position: absolute;
    top: 50%;
    transform: translate(-50%, -50%);
  }

  .enough-image-reveal:hover {
    background: rgb(255 255 255 / 30%);
  }

  .enough-image-reveal__icon {
    height: 14px;
    width: 14px;
  }
`;
document.documentElement.append(style);

function inspectImages(root = document) {
  root.querySelectorAll?.("img").forEach(inspectImage);
}

function addOverlay(image, result) {
  removeOverlay(image);

  const host = overlayHostFor(image);
  if (!host) {
    return;
  }
  acquireOverlayHost(host);

  const overlay = document.createElement("div");
  overlay.className = "enough-image-overlay";
  const info = document.createElement("div");
  info.className = "enough-image-info";
  const languageCode = "en";
  const showsVerifiedAIC2PA = result.showVerifiedAIC2PA !== false;
  if (typeof result.confidence === "number") {
    info.append(score(result.confidence, result.threshold, languageCode));
    if (
      result.c2paStatus === "digitalCapture"
      || (result.c2paStatus === "aiDeclared" && showsVerifiedAIC2PA)
    ) {
      info.append(chip(c2paMessage(result.c2paStatus, languageCode)));
    }
  } else if (result.source === "c2pa-real") {
    info.append(chip(message("c2paDigitalCapture", [], languageCode), true));
  }
  overlay.append(info);

  if (result.shouldBlur) {
    const revealButton = document.createElement("button");
    revealButton.className = "enough-image-reveal";
    revealButton.type = "button";
    revealButton.append(
      eyeIcon(),
      document.createTextNode(message("revealImage", [], languageCode))
    );
    revealButton.setAttribute(
      "aria-label",
      message("revealImageAccessibility", [], languageCode)
    );
    revealButton.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      image.classList.remove(blurredClass);
      image.dataset.enoughStatus = "revealed";
      image.dataset.enoughRevealed = "true";
      revealButton.remove();
    });
    overlay.append(revealButton);
  }
  host.append(overlay);

  const resizeObserver = new ResizeObserver(() => positionOverlay(image));
  resizeObserver.observe(image);
  overlays.set(image, { host, overlay, resizeObserver });
  positionOverlay(image);
}

function addLoadingOverlay(image) {
  removeOverlay(image);

  const host = overlayHostFor(image);
  if (!host) {
    return;
  }
  acquireOverlayHost(host);

  const overlay = document.createElement("div");
  overlay.className = "enough-image-overlay";
  const info = document.createElement("div");
  info.className = "enough-image-info";
  const trigger = document.createElement("div");
  trigger.className = "enough-image-score-trigger enough-image-score-trigger--loading";
  trigger.setAttribute(
    "aria-label",
    message("analyzingImage")
  );
  trigger.setAttribute("role", "status");
  const spinner = document.createElement("span");
  spinner.className = "enough-image-score-spinner";
  spinner.setAttribute("aria-hidden", "true");
  trigger.append(spinner);
  info.append(trigger);
  overlay.append(info);
  host.append(overlay);

  const resizeObserver = new ResizeObserver(() => positionOverlay(image));
  resizeObserver.observe(image);
  overlays.set(image, { host, overlay, resizeObserver });
  positionOverlay(image);
}

function addUnavailableOverlay(image) {
  removeOverlay(image);

  const host = overlayHostFor(image);
  if (!host) {
    return;
  }
  acquireOverlayHost(host);

  const overlay = document.createElement("div");
  overlay.className = "enough-image-overlay";
  const info = document.createElement("div");
  info.className = "enough-image-info";
  const trigger = document.createElement("div");
  trigger.className = "enough-image-score-trigger";
  trigger.setAttribute("aria-label", message("analysisUnavailable"));
  trigger.setAttribute("role", "status");
  trigger.append(warningIcon());
  info.append(trigger);
  overlay.append(info);
  host.append(overlay);

  const resizeObserver = new ResizeObserver(() => positionOverlay(image));
  resizeObserver.observe(image);
  overlays.set(image, { host, overlay, resizeObserver });
  positionOverlay(image);
}

function score(confidence, threshold, languageCode) {
  const value = Math.min(Math.max(confidence, 0), 1);
  const decisionThreshold = Math.min(Math.max(threshold ?? 0, 0), 1);
  const trigger = document.createElement("div");
  trigger.className = "enough-image-score-trigger";
  trigger.textContent = "i";
  trigger.setAttribute("role", "button");
  trigger.tabIndex = 0;
  trigger.setAttribute(
    "aria-label",
    `${message("aiConfidence", [formatPercent(value, languageCode)], languageCode)}. `
      + message(
        "aiThreshold",
        [formatPercent(decisionThreshold, languageCode)],
        languageCode
      )
  );
  trigger.setAttribute("aria-expanded", "false");
  trigger.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
    const isOpen = trigger.classList.toggle("enough-image-score-trigger--open");
    trigger.setAttribute("aria-expanded", String(isOpen));
  });
  trigger.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      trigger.click();
    }
  });

  const container = document.createElement("div");
  container.className = "enough-image-score-tooltip";

  const bar = document.createElement("div");
  bar.className = "enough-image-score__bar";
  bar.style.setProperty("--confidence", `${value * 100}%`);
  bar.style.setProperty("--threshold", `${decisionThreshold * 100}%`);
  const thresholdMarker = document.createElement("span");
  thresholdMarker.className = "enough-image-score__threshold";
  const valueMarker = document.createElement("span");
  valueMarker.className = "enough-image-score__value";
  bar.append(thresholdMarker, valueMarker);

  const labels = document.createElement("div");
  labels.className = "enough-image-score__labels";
  for (const key of ["real", "uncertain", "ai"]) {
    const label = document.createElement("span");
    label.textContent = message(key, [], languageCode);
    labels.append(label);
  }

  const thresholdLabel = document.createElement("div");
  thresholdLabel.className = "enough-image-score__threshold-label";
  thresholdLabel.textContent = message(
    "aiConfidence",
    [formatPercent(value, languageCode)],
    languageCode
  );

  container.append(bar, labels, thresholdLabel);
  trigger.append(container);
  return trigger;
}

function message(key, substitutions = [], languageCode = "system") {
  const locale = languageCode === "system" ? extensionLocale : languageCode;
  const language = locale.toLowerCase().startsWith("es") ? "es" : "en";
  const template = localizedMessages[language][key];
  if (!template) {
    return browser.i18n.getMessage(key, substitutions) || key;
  }
  return substitutions.reduce(
    (text, substitution, index) =>
      text.replaceAll(`$${index + 1}`, String(substitution)),
    template
  );
}

function formatPercent(value, languageCode = "system") {
  const locale = languageCode === "system" ? extensionLocale : languageCode;
  return new Intl.NumberFormat(locale, {
    maximumFractionDigits: 1,
    minimumFractionDigits: 1,
    style: "percent"
  }).format(value);
}

function c2paMessage(status, languageCode) {
  switch (status) {
  case "aiDeclared":
    return message("c2paAIDeclared", [], languageCode);
  case "digitalCapture":
    return message("c2paDigitalCapture", [], languageCode);
  case "unknownType":
    return message("c2paUnknownType", [], languageCode);
  case "unverified":
  default:
    return message("c2paUnverified", [], languageCode);
  }
}

function chip(text, isReal = false) {
  const chip = document.createElement("span");
  chip.className = isReal
    ? "enough-image-chip enough-image-chip--real"
    : "enough-image-chip";
  chip.textContent = text;
  return chip;
}

function eyeIcon() {
  const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  icon.classList.add("enough-image-reveal__icon");
  icon.setAttribute("aria-hidden", "true");
  icon.setAttribute("fill", "none");
  icon.setAttribute("stroke", "currentColor");
  icon.setAttribute("stroke-linecap", "round");
  icon.setAttribute("stroke-linejoin", "round");
  icon.setAttribute("stroke-width", "2");
  icon.setAttribute("viewBox", "0 0 24 24");

  const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
  path.setAttribute(
    "d",
    "M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6Z"
  );
  const pupil = document.createElementNS("http://www.w3.org/2000/svg", "circle");
  pupil.setAttribute("cx", "12");
  pupil.setAttribute("cy", "12");
  pupil.setAttribute("r", "2.5");
  icon.append(path, pupil);
  return icon;
}

function warningIcon() {
  const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  icon.classList.add("enough-image-warning-icon");
  icon.setAttribute("aria-hidden", "true");
  icon.setAttribute("fill", "currentColor");
  icon.setAttribute("viewBox", "0 0 24 24");

  const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
  path.setAttribute(
    "d",
    "M12 3.5a1.7 1.7 0 0 1 1.47.85l8 13.85A1.7 1.7 0 0 1 20 20.75H4a1.7 1.7 0 0 1-1.47-2.55l8-13.85A1.7 1.7 0 0 1 12 3.5Zm0 4.5a.9.9 0 0 0-.9.9v4.7a.9.9 0 1 0 1.8 0V8.9A.9.9 0 0 0 12 8Zm0 8.25a1.1 1.1 0 1 0 0 2.2 1.1 1.1 0 0 0 0-2.2Z"
  );
  icon.append(path);
  return icon;
}

function removeOverlay(image) {
  const entry = overlays.get(image);
  if (!entry) {
    return;
  }
  entry.resizeObserver.disconnect();
  entry.overlay.remove();
  releaseOverlayHost(entry.host);
  overlays.delete(image);
}

function overlayHostFor(image) {
  let host = image.parentElement;
  while (
    host
    && (
      getComputedStyle(host).display === "contents"
      || ["A", "BUTTON", "PICTURE"].includes(host.tagName)
    )
  ) {
    host = host.parentElement;
  }
  return host;
}

function acquireOverlayHost(host) {
  const entry = overlayHosts.get(host);
  if (entry) {
    entry.count += 1;
    return;
  }

  const originalPosition = host.style.position;
  if (getComputedStyle(host).position === "static") {
    host.style.position = "relative";
  }
  overlayHosts.set(host, { count: 1, originalPosition });
}

function releaseOverlayHost(host) {
  const entry = overlayHosts.get(host);
  if (!entry) {
    return;
  }
  entry.count -= 1;
  if (entry.count === 0) {
    host.style.position = entry.originalPosition;
    overlayHosts.delete(host);
  }
}

function removeOverlaysIn(node) {
  if (node instanceof HTMLImageElement) {
    removeOverlay(node);
  }
  node.querySelectorAll?.("img").forEach(removeOverlay);
}

function positionOverlay(image) {
  const entry = overlays.get(image);
  if (!entry) {
    return;
  }
  const bounds = image.getBoundingClientRect();
  const isVisible = (
    bounds.bottom > 0
    && bounds.right > 0
    && bounds.top < window.innerHeight
    && bounds.left < window.innerWidth
  );
  entry.overlay.hidden = !isVisible;
  if (!isVisible) {
    return;
  }
  if (image.offsetParent === entry.host) {
    entry.overlay.style.left = `${image.offsetLeft}px`;
    entry.overlay.style.top = `${image.offsetTop}px`;
    entry.overlay.style.width = `${image.offsetWidth}px`;
    entry.overlay.style.height = `${image.offsetHeight}px`;
    return;
  }

  const hostBounds = entry.host.getBoundingClientRect();
  entry.overlay.style.left = `${Math.round(bounds.left - hostBounds.left)}px`;
  entry.overlay.style.top = `${Math.round(bounds.top - hostBounds.top)}px`;
  entry.overlay.style.width = `${Math.round(bounds.width)}px`;
  entry.overlay.style.height = `${Math.round(bounds.height)}px`;
}

function positionOverlays() {
  overlays.forEach((_entry, image) => {
    if (!image.isConnected) {
      removeOverlay(image);
      return;
    }
    positionOverlay(image);
  });
}

window.addEventListener("resize", positionOverlays);
window.addEventListener("scroll", positionOverlays, true);

function inspectImage(image) {
  if (image.dataset.enoughStatus || !image.complete) {
    return;
  }
  const url = image.currentSrc || image.src;
  if (!url || url.startsWith("data:") || url.startsWith("blob:")) {
    image.dataset.enoughStatus = "unsupported";
    return;
  }
  if (
    image.naturalWidth < MINIMUM_NATURAL_DIMENSION
    || image.naturalHeight < MINIMUM_NATURAL_DIMENSION
  ) {
    image.dataset.enoughStatus = "too-small";
    return;
  }
  const bounds = image.getBoundingClientRect();
  if (
    bounds.width < MINIMUM_RENDERED_DIMENSION
    || bounds.height < MINIMUM_RENDERED_DIMENSION
  ) {
    image.dataset.enoughStatus = "too-small";
    return;
  }

  image.dataset.enoughStatus = "pending";
  addLoadingOverlay(image);
  console.debug("[Enough] Analyzing image", url);
  browser.runtime.sendMessage({ action: "analyzeImage", url })
    .then((result) => {
      if (!result || typeof result.shouldBlur !== "boolean") {
        throw new Error(
          result?.error || message("analysisError")
        );
      }
      image.dataset.enoughStatus = result.shouldBlur ? "blurred" : "visible";
      if (result.shouldBlur) {
        image.classList.add(blurredClass);
      }
      addOverlay(image, result);
      console.debug("[Enough] Analysis result", {
        url,
        shouldBlur: result.shouldBlur,
        confidence: result.confidence,
        source: result.source
      });
    })
    .catch((error) => {
      image.dataset.enoughStatus = "unavailable";
      addUnavailableOverlay(image);
      console.warn("[Enough] Image analysis failed", { url, error });
    });
}

document.addEventListener("load", (event) => {
  if (event.target instanceof HTMLImageElement) {
    inspectImage(event.target);
  }
}, true);

new MutationObserver((records) => {
  for (const record of records) {
    if (
      record.type === "attributes"
      && record.target instanceof HTMLImageElement
    ) {
        removeOverlay(record.target);
        delete record.target.dataset.enoughStatus;
        delete record.target.dataset.enoughRevealed;
        record.target.classList.remove(blurredClass);
        inspectImage(record.target);
      continue;
    }
    for (const node of record.addedNodes) {
      if (node instanceof Element) {
        inspectImages(node);
        if (node instanceof HTMLImageElement) {
          inspectImage(node);
        }
      }
    }
    for (const node of record.removedNodes) {
      if (node instanceof Element) {
        removeOverlaysIn(node);
      }
    }
  }
}).observe(document.documentElement, {
  attributes: true,
  attributeFilter: ["src", "srcset"],
  childList: true,
  subtree: true
});

inspectImages();
