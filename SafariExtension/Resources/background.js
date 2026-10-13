const MAXIMUM_IMAGE_BYTES = 8 * 1024 * 1024;
const ANALYSIS_VERSION = "sieve-visual-v3";
const CACHE_DATABASE_NAME = "EnoughImageAnalysis";
const CACHE_STORE_NAME = "analyses";
const CACHE_MAXIMUM_ENTRIES = 1_000;
const CACHE_MAXIMUM_AGE_MS = 30 * 24 * 60 * 60 * 1_000;
const inFlightAnalyses = new Map();

browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.action !== "analyzeImage" || typeof message.url !== "string") {
    sendResponse({ error: messageText("analysisError") });
    return false;
  }
  analyzeImage(message.url)
    .then(sendResponse)
    .catch((error) => {
      console.warn("[Enough] Background image analysis failed", {
        url: message.url,
        error
      });
      sendResponse({ error: error.message });
    });
  return true;
});

async function analyzeImage(url) {
  if (!inFlightAnalyses.has(url)) {
    const analysis = analyzeUncachedImage(url);
    inFlightAnalyses.set(url, analysis);
    analysis.then(
      () => inFlightAnalyses.delete(url),
      () => inFlightAnalyses.delete(url)
    );
  }
  return inFlightAnalyses.get(url);
}

async function analyzeUncachedImage(url) {
  let data;
  try {
    data = await downloadImage(url);
  } catch (error) {
    if (!(error instanceof TypeError)) {
      throw error;
    }
    console.debug(
      "[Enough] Safari could not download image; using native download",
      { url, error }
    );
    return analyzeRemoteImage(url);
  }

  const imageHash = await sha256(data);
  const cachedAnalysis = await readCachedAnalysis(imageHash);
  if (cachedAnalysis) {
    console.debug("[Enough] Reusing cached image analysis", { imageHash });
    return presentationFor(cachedAnalysis);
  }

  const reply = await sendNativeMessage({
    action: "analyzeImage",
    imageBase64: arrayBufferToBase64(data)
  });
  if (!reply?.success) {
    throw new Error(reply?.error || messageText("nativeAnalysisError"));
  }
  await cacheAnalysis(imageHash, reply.data);
  return presentationFor(reply.data);
}

async function downloadImage(url) {
  const response = await fetch(url, { credentials: "omit" });
  if (!response.ok) {
    throw new Error(messageText("downloadError", response.status));
  }
  const declaredLength = Number(response.headers.get("content-length") || 0);
  if (declaredLength > MAXIMUM_IMAGE_BYTES) {
    throw new Error(messageText("largeImageError"));
  }
  const data = await response.arrayBuffer();
  if (data.byteLength > MAXIMUM_IMAGE_BYTES) {
    throw new Error(messageText("largeImageError"));
  }
  return data;
}

async function analyzeRemoteImage(url) {
  const reply = await sendNativeMessage({
    action: "analyzeImageURL",
    url
  });
  if (!reply?.success) {
    throw new Error(reply?.error || messageText("nativeAnalysisError"));
  }
  return presentationFor(reply.data);
}

async function presentationFor(analysis) {
  const settings = await currentSettings();
  const presentation = {
    ...analysis,
    appLanguageCode: "en",
    showVerifiedAIC2PA: settings.showVerifiedAIC2PA
  };
  if (typeof analysis?.confidence !== "number") {
    return presentation;
  }

  return {
    ...presentation,
    shouldBlur: analysis.confidence >= settings.aiConfidenceThreshold,
    threshold: settings.aiConfidenceThreshold
  };
}

async function currentSettings() {
  const reply = await sendNativeMessage({ action: "settings" });
  if (
    !reply?.success
    || typeof reply.data?.aiConfidenceThreshold !== "number"
    || typeof reply.data?.showVerifiedAIC2PA !== "boolean"
    || !["system", "en", "es"].includes(reply.data?.appLanguageCode)
  ) {
    throw new Error(messageText("thresholdError"));
  }
  return reply.data;
}

async function readCachedAnalysis(imageHash) {
  const database = await openCacheDatabase();
  const transaction = database.transaction(CACHE_STORE_NAME, "readwrite");
  const store = transaction.objectStore(CACHE_STORE_NAME);
  const entry = await requestResult(store.get(cacheKey(imageHash)));

  if (!entry) {
    await transactionComplete(transaction);
    database.close();
    return null;
  }
  if (Date.now() - entry.createdAt > CACHE_MAXIMUM_AGE_MS) {
    store.delete(entry.key);
    await transactionComplete(transaction);
    database.close();
    return null;
  }

  entry.lastAccessedAt = Date.now();
  store.put(entry);
  await transactionComplete(transaction);
  database.close();
  return entry.analysis;
}

async function cacheAnalysis(imageHash, analysis) {
  const database = await openCacheDatabase();
  const transaction = database.transaction(CACHE_STORE_NAME, "readwrite");
  const store = transaction.objectStore(CACHE_STORE_NAME);
  const now = Date.now();

  store.put({
    key: cacheKey(imageHash),
    analysis,
    createdAt: now,
    lastAccessedAt: now
  });

  const entries = await requestResult(store.getAll());
  const leastRecentlyUsed = entries.sort(
    (left, right) => left.lastAccessedAt - right.lastAccessedAt
  );
  const entriesToRemove = Math.max(0, entries.length - CACHE_MAXIMUM_ENTRIES);
  for (const [index, entry] of leastRecentlyUsed.entries()) {
    if (
      now - entry.createdAt > CACHE_MAXIMUM_AGE_MS
      || index < entriesToRemove
    ) {
      store.delete(entry.key);
    }
  }

  await transactionComplete(transaction);
  database.close();
}

function cacheKey(imageHash) {
  return `${ANALYSIS_VERSION}:${imageHash}`;
}

function openCacheDatabase() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(CACHE_DATABASE_NAME, 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore(CACHE_STORE_NAME, { keyPath: "key" });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function requestResult(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function transactionComplete(transaction) {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error);
    transaction.onabort = () => reject(transaction.error);
  });
}

async function sha256(data) {
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

function sendNativeMessage(message) {
  return new Promise((resolve, reject) => {
    browser.runtime.sendNativeMessage(message, (response) => {
      if (browser.runtime.lastError) {
        reject(new Error(browser.runtime.lastError.message));
        return;
      }
      resolve(response);
    });
  });
}

function messageText(key, substitutions = []) {
  return browser.i18n.getMessage(key, substitutions) || key;
}

function arrayBufferToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  const chunkSize = 0x8000;
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(binary);
}
